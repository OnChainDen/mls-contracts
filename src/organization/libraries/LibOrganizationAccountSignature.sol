// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { LibOrganizationPolicy } from "./LibOrganizationPolicy.sol";
import { LibOrganizationGuardian } from "./LibOrganizationGuardian.sol";
import { LibOrganizationSignatures } from "./LibOrganizationSignatures.sol";
import { LibOrganizationEIP712 } from "./LibOrganizationEIP712.sol";
import { Policies } from "../../libraries/Policies.sol";
import { SignatureUtils } from "../../libraries/SignatureUtils.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

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
    function isValidSignature(
        address account,
        bytes32 hash,
        bytes memory signature
    )
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

        // Check if the signature request has expired
        if (block.timestamp > expirationTimestamp) {
            return ERC1271_INVALID_VALUE;
        }

        // Verify guardian has approved this signature request
        if (!_isGuardianSignatureValid(account, hash, policyId, expirationTimestamp, guardianSignature)) {
            return ERC1271_INVALID_VALUE;
        }

        // Verify the policy exists in the organization's policy tree
        if (!LibOrganizationPolicy.isPolicyInOrg(policyId, proofs.policy, proofs.policyProof)) {
            return ERC1271_INVALID_VALUE;
        }

        // Policy must be configured for signature operations
        if (proofs.policy.config.transactionType != Policies.TransactionType.Signatures) {
            return ERC1271_INVALID_VALUE;
        }

        // Verify the policy applies to this specific account
        if (!LibOrganizationPolicy.isSourceAccountAllowedByPolicy(proofs.policy, account, proofs.sourceAccountProof)) {
            return ERC1271_INVALID_VALUE;
        }

        // Continue validation in separate function to reduce stack depth
        return _validateSignatures(account, hash, policyId, expirationTimestamp, approverSignatures, proofs);
    }

    /**
     * @notice Validates initiator signature and routes to appropriate approval flow
     * @dev Extracted to separate function to manage stack depth
     * @param account The account address whose signature is being validated
     * @param hash The message hash that was signed
     * @param policyId The policy ID being used for validation
     * @param expirationTimestamp When the signature request expires
     * @param approverSignatures Concatenated signatures from initiator and approvers
     * @param proofs Merkle proofs and policy data
     * @return ERC1271_MAGIC_VALUE if valid, ERC1271_INVALID_VALUE otherwise
     */
    function _validateSignatures(
        address account,
        bytes32 hash,
        uint256 policyId,
        uint256 expirationTimestamp,
        bytes memory approverSignatures,
        Policies.ValidationProofs memory proofs
    )
        private
        view
        returns (bytes4)
    {
        // Need at least one signature (the initiator's)
        if (approverSignatures.length < 65) {
            return ERC1271_INVALID_VALUE;
        }

        // Extract and verify the initiator's signature (first 65 bytes)
        bytes memory initiatorSignature = SignatureUtils.extractSignature(approverSignatures, 0);

        // Compute the hash that the initiator should have signed
        bytes32 initiatorHash = _getInitiatorSignatureHash(account, hash, policyId, expirationTimestamp);

        // Recover the initiator's address from their signature
        address initiator = ECDSA.recover(initiatorHash, initiatorSignature);
        if (initiator == address(0)) {
            return ERC1271_INVALID_VALUE;
        }

        // Verify the initiator is authorized by this policy (with Merkle proofs)
        if (!LibOrganizationPolicy.isInitiatorAuthorized(proofs.policy, initiator, proofs.initiatorProofs)) {
            return ERC1271_INVALID_VALUE;
        }

        // Route to appropriate validation based on policy type
        Policies.PolicyType pType = proofs.policy.config.approval.policyType;

        // AutoApprove: Initiator signature alone is sufficient
        if (pType == Policies.PolicyType.AutoApprove) {
            return ERC1271_MAGIC_VALUE;
        }

        // ManualApproval: Need additional reviewer signatures
        if (pType == Policies.PolicyType.RequireManualApproval) {
            if (
                _hasSufficentValidApprovalSignatures(
                    account, hash, policyId, expirationTimestamp, approverSignatures, initiatorSignature, proofs
                )
            ) {
                return ERC1271_MAGIC_VALUE;
            }
            return ERC1271_INVALID_VALUE;
        }

        return ERC1271_INVALID_VALUE;
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
    )
        private
        view
        returns (bool)
    {
        // Get required number of approvals from policy
        uint256 requiredApprovals = LibOrganizationPolicy.getRequiredApprovals(proofs.policy);

        // Extract reviewer signatures (everything after the initiator signature)
        bytes memory reviewSignatures = LibOrganizationSignatures.extractReviewSignatures(approverSignatures);

        // Compute the hash that reviewers should have signed
        // Note: includes the initiator signature to bind approvals to the specific request
        bytes32 reviewHash = _getReviewSignatureHash(account, hash, policyId, expirationTimestamp, initiatorSignature);

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
    )
        private
        view
        returns (bool)
    {
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
    function _getInitiatorSignatureHash(
        address account,
        bytes32 hash,
        uint256 policyId,
        uint256 expirationTimestamp
    )
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
    )
        private
        view
        returns (bytes32)
    {
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
