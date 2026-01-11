// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Policies} from "../../libraries/Policies.sol";
import {SignatureUtils} from "../../libraries/SignatureUtils.sol";
import {LibOrganizationEIP712} from "./LibOrganizationEIP712.sol";
import {LibOrganizationGuardian} from "./LibOrganizationGuardian.sol";
import {LibOrganizationPolicy} from "./LibOrganizationPolicy.sol";
import {LibOrganizationSignatures} from "./LibOrganizationSignatures.sol";

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/**
 * @title Lib Organization Account Signature
 * @notice Library for validating ERC-1271 signatures through the Organization contract
 * @dev This library enables smart accounts to sign messages in a policy-controlled manner.
 *      When an external contract calls isValidSignature() on an Account, the Account
 *      delegates to the Organization, which uses this library to validate that:
 *      1. The signature request hasn't expired
 *      2. The guardian has approved the signature request
 *      3. A valid policy exists for signature operations
 *      4. The policy applies to the requesting account
 *      5. The initiator is authorized by the policy
 *      6. Required approvals have been collected (for manual approval policies)
 *
 *      Policy existence is verified via merkle proof. Policy data is provided in calldata.
 * @author Den Technologies Inc
 */
library LibOrganizationAccountSignature {
    /// @notice ERC-1271 magic value returned when signature is valid
    bytes4 internal constant ERC1271_MAGIC_VALUE = 0x1626ba7e;

    /// @notice Value returned when signature validation fails
    bytes4 internal constant ERC1271_INVALID_VALUE = 0xffffffff;

    /**
     * @notice Validates an ERC-1271 signature for a given account
     * @dev The signature parameter is ABI-encoded and contains:
     *      - policyId: ID of the policy authorizing this signature
     *      - expirationTimestamp: When the signature request expires
     *      - approverSignatures: Concatenated signatures (initiator + reviewers)
     *      - guardianSignature: Guardian's approval of the signature request
     *      - proofs: Merkle proofs and policy data for validation
     * @param account The account address whose signature is being validated
     * @param hash The message hash that was signed
     * @param signature ABI-encoded signature data containing policy info and proofs
     * @return magicValue ERC1271_MAGIC_VALUE if valid, ERC1271_INVALID_VALUE otherwise
     */
    function isValidSignature(address account, bytes32 hash, bytes memory signature)
        internal
        view
        returns (bytes4 magicValue)
    {
        // Decode the packed signature data
        (
            uint256 policyId,
            uint256 expirationTimestamp,
            bytes memory approverSignatures,
            bytes memory guardianSignature,
            Policies.ValidationProofs memory proofs
        ) = abi.decode(signature, (uint256, uint256, bytes, bytes, Policies.ValidationProofs));

        // Case: Signature request has expired
        if (block.timestamp > expirationTimestamp) {
            return ERC1271_INVALID_VALUE;
        }

        // Case: Guardian signature is invalid
        if (
            !_isGuardianSignatureValid({
                account: account,
                hash: hash,
                policyId: policyId,
                expirationTimestamp: expirationTimestamp,
                guardianSignature: guardianSignature
            })
        ) {
            return ERC1271_INVALID_VALUE;
        }

        bytes memory initiatorSignature = SignatureUtils.extractSignature(approverSignatures, 0);
        bytes32 initiatorHash = _getInitiatorSignatureHash(account, hash, policyId, expirationTimestamp);
        address initiator = ECDSA.recover(initiatorHash, initiatorSignature);

        // Case: Initiator signature is invalid
        if (initiator == address(0)) {
            return ERC1271_INVALID_VALUE;
        }

        // Case: Signature is not allowed by the policy
        if (!_isERC1271SignatureAllowedByPolicy(account, initiator, policyId, proofs)) {
            return ERC1271_INVALID_VALUE;
        }

        Policies.PolicyType pType = proofs.policy.config.approval.policyType;

        // Case: Policy is an AutoApprove approval policy (Guardian and initiator signatures are sufficient)
        if (pType == Policies.PolicyType.AutoApprove) {
            return ERC1271_MAGIC_VALUE;
        }

        // Case: Policy is a ManualApproval approval policy (Need to check if we have enough valid approval signatures)
        if (pType == Policies.PolicyType.RequireManualApproval) {
            // Case: Sufficient valid approval signatures are provided
            if (
                _hasSufficentValidApprovalSignatures({
                    account: account,
                    hash: hash,
                    policyId: policyId,
                    expirationTimestamp: expirationTimestamp,
                    approverSignatures: approverSignatures,
                    initiatorSignature: initiatorSignature,
                    proofs: proofs
                })
            ) {
                return ERC1271_MAGIC_VALUE;
            }
        }

        return ERC1271_INVALID_VALUE;
    }

    /**
     * @notice Checks if an ERC-1271 signature operation is allowed by the policy
     * @dev Validates that:
     *      1. The policy exists in the organization's policy tree
     *      2. The policy is configured for signature operations
     *      3. The policy applies to the source account
     *      4. The initiator is authorized by the policy
     * @param account The account address whose signature is being validated
     * @param initiator The address that initiated the signature request
     * @param policyId The ID of the policy being used for validation
     * @param proofs Merkle proofs and policy data for validation
     * @return True if the signature is allowed by the policy, false otherwise
     */
    // forge-lint: disable-next-line(mixed-case-function)
    function _isERC1271SignatureAllowedByPolicy(
        address account,
        address initiator,
        uint256 policyId,
        Policies.ValidationProofs memory proofs
    ) private view returns (bool) {
        // Case: Policy is not in the organization's policy tree
        if (!LibOrganizationPolicy.isPolicyInOrg(policyId, proofs.policy, proofs.policyProof)) {
            return false;
        }

        // Case: Policy can't be used for signature operations
        if (proofs.policy.config.transactionType != Policies.TransactionType.Signatures) {
            return false;
        }

        // Case: Policy doesn't apply to this specific source account
        if (!LibOrganizationPolicy.isSourceAccountAllowedByPolicy(proofs.policy, account, proofs.sourceAccountProof)) {
            return false;
        }

        // Case: Initiator is not authorized by this policy
        if (!LibOrganizationPolicy.isInitiatorAuthorized(proofs.policy, initiator, proofs.initiatorProofs)) {
            return false;
        }

        return true;
    }

    /**
     * @notice Checks if manual approval signatures meet the required threshold
     * @dev Extracts reviewer signatures (all after the first initiator signature),
     *      computes the review hash, and counts valid approvals from authorized approvers.
     * @param account The account address whose signature is being validated
     * @param hash The message hash that was signed
     * @param policyId The policy ID being used for validation
     * @param expirationTimestamp When the signature request expires
     * @param approverSignatures Concatenated signatures from initiator and approvers
     * @param initiatorSignature The initiator's signature
     * @param proofs Merkle proofs and policy data
     * @return True if enough valid approvals, false otherwise
     */
    function _hasSufficentValidApprovalSignatures(
        address account,
        bytes32 hash,
        uint256 policyId,
        uint256 expirationTimestamp,
        bytes memory approverSignatures,
        bytes memory initiatorSignature,
        Policies.ValidationProofs memory proofs
    ) private view returns (bool) {
        // Case: Not enough data provided to check for valid approval signatures
        if (approverSignatures.length < 65) {
            return false;
        }

        // Get required number of approvals from policy
        uint256 requiredApprovals = LibOrganizationPolicy.getRequiredApprovals(proofs.policy);

        // Extract reviewer signatures (everything after the initiator signature)
        bytes memory reviewSignatures = LibOrganizationSignatures.extractReviewSignatures(approverSignatures);

        // Compute the hash that reviewers should have signed
        // Note: includes the initiator signature to bind approvals to the specific request
        bytes32 reviewHash = _getReviewSignatureHash({
            account: account,
            hash: hash,
            policyId: policyId,
            expirationTimestamp: expirationTimestamp,
            initiatorSignature: initiatorSignature
        });

        // Count valid approvals from authorized signers (with Merkle proofs for membership verification)
        uint256 validApprovals =
            LibOrganizationPolicy.getValidApprovals(proofs.policy, reviewSignatures, reviewHash, proofs.approverProofs);

        return validApprovals >= requiredApprovals;
    }

    /**
     * @notice Checks if the guardian's signature is valid for an ERC-1271 signature request
     * @dev The guardian provides an additional layer of security by approving
     *      signature requests off-chain before they can be validated on-chain.
     * @param account The account whose signature is being validated
     * @param hash The message hash being signed
     * @param policyId The policy ID being used
     * @param expirationTimestamp When the request expires
     * @param guardianSignature The guardian's signature
     * @return True if guardian signature is valid
     */
    function _isGuardianSignatureValid(
        address account,
        bytes32 hash,
        uint256 policyId,
        uint256 expirationTimestamp,
        bytes memory guardianSignature
    ) private view returns (bool) {
        address guardianAddress = LibOrganizationGuardian.getGuardian();

        // Guardian signs the same hash structure as the initiator
        bytes32 guardianMessageHash = _getInitiatorSignatureHash(account, hash, policyId, expirationTimestamp);

        // Use SignatureChecker to support both EOA and smart contract guardians
        return SignatureChecker.isValidSignatureNow(guardianAddress, guardianMessageHash, guardianSignature);
    }

    /**
     * @notice Computes the EIP-712 hash for initiator signatures
     * @dev Creates a typed data hash following EIP-712 standard for the
     *      InitiateSignatureValidation struct type.
     * @param account The account whose signature is being validated
     * @param hash The message hash being signed
     * @param policyId The policy ID being used
     * @param expirationTimestamp When the request expires
     * @return The EIP-712 typed data hash for signing
     */
    function _getInitiatorSignatureHash(address account, bytes32 hash, uint256 policyId, uint256 expirationTimestamp)
        private
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "InitiateSignatureValidation(address organization,address account,bytes32 hash,uint256 policyId,uint256 expirationTimestamp,uint256 chainId)"
                ),
                address(this),
                account,
                hash,
                policyId,
                expirationTimestamp,
                block.chainid
            )
        );

        return MessageHashUtils.toTypedDataHash(LibOrganizationEIP712.getDomainSeparator(), structHash);
    }

    /**
     * @notice Computes the EIP-712 hash for reviewer signatures
     * @dev Creates a typed data hash for the ReviewSignatureValidation struct type.
     *      Includes the initiator signature to bind approval to a specific request.
     * @param account The account whose signature is being validated
     * @param hash The message hash being signed
     * @param policyId The policy ID being used
     * @param expirationTimestamp When the request expires
     * @param initiatorSignature The initiator's signature (included in hash)
     * @return The EIP-712 typed data hash for signing
     */
    function _getReviewSignatureHash(
        address account,
        bytes32 hash,
        uint256 policyId,
        uint256 expirationTimestamp,
        bytes memory initiatorSignature
    ) private view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "ReviewSignatureValidation(address organization,address account,bytes32 hash,uint256 policyId,uint256 expirationTimestamp,uint256 chainId,bytes initiatorSignature)"
                ),
                address(this),
                account,
                hash,
                policyId,
                expirationTimestamp,
                block.chainid,
                keccak256(initiatorSignature)
            )
        );

        return MessageHashUtils.toTypedDataHash(LibOrganizationEIP712.getDomainSeparator(), structHash);
    }
}
