// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {BytesUtils} from "libraries/BytesUtils.sol";
import {SignatureUtils} from "libraries/SignatureUtils.sol";
import {LibOrganizationEIP712} from "organization/libraries/LibOrganizationEIP712.sol";
import {LibOrganizationGuardian} from "organization/libraries/LibOrganizationGuardian.sol";
import {LibOrganizationPolicy} from "organization/libraries/LibOrganizationPolicy.sol";
import {LibOrganizationTxRecovery} from "organization/libraries/LibOrganizationTxRecovery.sol";
import {PolicyType, TransactionType, ValidationProofs} from "types/PolicyTypes.sol";

/**
 * @title Lib Organization Account Signature
 * @dev Library for validating ERC-1271 signatures through the Organization contract.
 *      This library enables smart accounts to sign messages in a policy-controlled manner.
 *      When an external contract calls isValidSignature() on an Account, the Account
 *      delegates to the Organization, which uses this library to validate that:
 *      1. (Recovery path) If type prefix is 0x00, validates recovery signature
 *      2. (Policy path) If type prefix is 0x01, validates policy-based signature:
 *         - The signature request hasn't expired
 *         - The guardian has approved the signature request
 *         - A valid policy exists for signature operations
 *         - The policy applies to the requesting account
 *         - The initiator is authorized by the policy
 *         - Required approvals have been collected (for manual approval policies)
 *
 *      Signature format: | type (1 byte) | signature data (variable) |
 *      - 0x00 = Recovery signature (raw signature from recovery address)
 *      - 0x01 = Policy-based signature (ABI-encoded policy data and proofs)
 *
 *      Policy existence is verified via merkle proof. Policy data is provided in calldata.
 * @author Den Technologies Inc
 */
library LibOrganizationAccountSignature {
    /// @dev ERC-1271 magic value returned when signature is valid.
    /// Equals bytes4(keccak256("isValidSignature(bytes32,bytes)")) = 0x1626ba7e
    bytes4 internal constant ERC1271_MAGIC_VALUE = IERC1271.isValidSignature.selector;

    /// @dev Value returned when signature validation fails per ERC-1271 standard
    bytes4 internal constant ERC1271_INVALID_VALUE = 0xffffffff;

    /// @dev Signature type prefix for recovery signatures
    uint8 internal constant SIGNATURE_TYPE_RECOVERY = 0x00;

    /// @dev Signature type prefix for policy-based signatures
    uint8 internal constant SIGNATURE_TYPE_POLICY = 0x01;

    /**
     * @dev Validates an ERC-1271 signature for a given account.
     *      The signature must be prefixed with a type byte:
     *      - 0x00: Recovery signature (if recovery is supported AND enabled)
     *      - 0x01: Policy-based signature (ABI-encoded with policy info and proofs)
     * @param account The account address whose signature is being validated
     * @param hash The message hash that was signed
     * @param signature Type-prefixed signature data
     * @return magicValue ERC1271_MAGIC_VALUE if valid, ERC1271_INVALID_VALUE otherwise
     */
    function isValidSignature(address account, bytes32 hash, bytes memory signature)
        public
        view
        returns (bytes4 magicValue)
    {
        // Case: Empty signature
        if (signature.length == 0) {
            return ERC1271_INVALID_VALUE;
        }

        // Extract the type prefix byte
        uint8 signatureType = uint8(signature[0]);

        // Strip the type prefix to get the signature data
        bytes memory signatureData = BytesUtils.sliceFrom(signature, 1);

        // Route based on signature type
        if (signatureType == SIGNATURE_TYPE_RECOVERY) {
            return _validateRecoverySignature(hash, signatureData);
        }

        if (signatureType == SIGNATURE_TYPE_POLICY) {
            return _validatePolicyBasedSignature(account, hash, signatureData);
        }

        // Unknown signature type
        return ERC1271_INVALID_VALUE;
    }

    /**
     * @dev Validates a recovery signature.
     *      Recovery signatures bypass all guardian and policy checks.
     * @param hash The message hash that was signed
     * @param signatureData The raw recovery signature (without type prefix)
     * @return magicValue ERC1271_MAGIC_VALUE if valid, ERC1271_INVALID_VALUE otherwise
     */
    function _validateRecoverySignature(bytes32 hash, bytes memory signatureData)
        private
        view
        returns (bytes4 magicValue)
    {
        // Recovery must be both supported AND enabled
        if (
            !LibOrganizationTxRecovery.isRecoverySupportedForTxAndERC1271()
                || !LibOrganizationTxRecovery.isRecoveryEnabledForTxAndERC1271()
        ) {
            return ERC1271_INVALID_VALUE;
        }

        // Validate the recovery signature
        if (LibOrganizationTxRecovery.isValidRecoverySignature(hash, signatureData)) {
            return ERC1271_MAGIC_VALUE;
        }

        return ERC1271_INVALID_VALUE;
    }

    /**
     * @dev Validates a policy-based signature.
     *      The signatureData is ABI-encoded and contains:
     *      - policyId: ID of the policy authorizing this signature
     *      - expirationTimestamp: When the signature request expires
     *      - initiatorSignature: The initiator's signature
     *      - reviewSignatures: The reviewer signatures (empty for auto-approve policies)
     *      - guardianSignature: Guardian's approval of the signature request
     *      - proofs: Merkle proofs and policy data for validation
     * @param account The account address whose signature is being validated
     * @param hash The message hash that was signed
     * @param signatureData ABI-encoded signature data (without type prefix)
     * @return magicValue ERC1271_MAGIC_VALUE if valid, ERC1271_INVALID_VALUE otherwise
     */
    function _validatePolicyBasedSignature(address account, bytes32 hash, bytes memory signatureData)
        private
        view
        returns (bytes4 magicValue)
    {
        // Decode the packed signature data
        (
            uint256 policyId,
            uint256 expirationTimestamp,
            bytes memory initiatorSignature,
            bytes memory reviewSignatures,
            bytes memory guardianSignature,
            ValidationProofs memory proofs
        ) = abi.decode(signatureData, (uint256, uint256, bytes, bytes, bytes, ValidationProofs));

        // Case: Signature request has expired
        if (block.timestamp > expirationTimestamp) {
            return ERC1271_INVALID_VALUE;
        }

        // Case: No initiator signature provided
        if (initiatorSignature.length == 0) {
            return ERC1271_INVALID_VALUE;
        }

        // Compute the initiator singature hash (used for both guardian and initiator signature validation)
        bytes32 initiatorSignatureHash = _getInitiatorSignatureHash(account, hash, policyId, expirationTimestamp);

        // Validate guardian signature
        {
            address guardianAddress = LibOrganizationGuardian.getGuardian();

            // Recover guardian signer and compare (returns invalid if signature is malformed)
            (bool guardianValid, address recoveredGuardian) =
                SignatureUtils.tryRecoverSigner(guardianSignature, initiatorSignatureHash);
            if (!guardianValid || recoveredGuardian != guardianAddress) {
                return ERC1271_INVALID_VALUE;
            }
        }

        // Recover initiator signer
        (bool initiatorValid, address initiator) =
            SignatureUtils.tryRecoverSigner(initiatorSignature, initiatorSignatureHash);
        if (!initiatorValid) {
            return ERC1271_INVALID_VALUE;
        }

        // Case: Signature is not allowed by the policy
        if (!_isERC1271SignatureAllowedByPolicy(account, initiator, policyId, proofs)) {
            return ERC1271_INVALID_VALUE;
        }

        PolicyType pType = proofs.policy.config.approval.policyType;

        // Case: Policy is an AutoApprove approval policy (Guardian and initiator signatures are sufficient)
        if (pType == PolicyType.AutoApprove) {
            return ERC1271_MAGIC_VALUE;
        }

        // Case: Policy is a ManualApproval approval policy (Need to check if we have enough valid approval signatures)
        if (pType == PolicyType.RequireManualApproval) {
            // Case: Sufficient valid approval signatures are provided
            if (_hasSufficientValidApprovalSignatures({
                    account: account,
                    hash: hash,
                    policyId: policyId,
                    expirationTimestamp: expirationTimestamp,
                    reviewSignatures: reviewSignatures,
                    initiatorSignature: initiatorSignature,
                    proofs: proofs
                })) {
                return ERC1271_MAGIC_VALUE;
            }
        }

        return ERC1271_INVALID_VALUE;
    }

    /**
     * @dev Checks if an ERC-1271 signature operation is allowed by the policy.
     *      Validates that:
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
        ValidationProofs memory proofs
    ) private view returns (bool) {
        // Case: Policy is not in the organization's policy tree
        if (!LibOrganizationPolicy.isPolicyInOrg(policyId, proofs.policy, proofs.policyProof)) {
            return false;
        }

        // Case: Policy can't be used for signature operations
        if (proofs.policy.config.transactionType != TransactionType.Signatures) {
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
     * @dev Checks if manual approval signatures meet the required threshold.
     *      Validates review signatures against required threshold.
     * @param account The account address whose signature is being validated
     * @param hash The message hash that was signed
     * @param policyId The policy ID being used for validation
     * @param expirationTimestamp When the signature request expires
     * @param reviewSignatures The reviewer signatures
     * @param initiatorSignature The initiator's signature (for hash binding)
     * @param proofs Merkle proofs and policy data
     * @return True if enough valid approvals, false otherwise
     */
    function _hasSufficientValidApprovalSignatures(
        address account,
        bytes32 hash,
        uint256 policyId,
        uint256 expirationTimestamp,
        bytes memory reviewSignatures,
        bytes memory initiatorSignature,
        ValidationProofs memory proofs
    ) private view returns (bool) {
        // Compute the hash that reviewers should have signed
        // Note: includes the initiator signature to bind approvals to the specific request
        bytes32 reviewHash = _getReviewSignatureHash({
            account: account,
            hash: hash,
            policyId: policyId,
            expirationTimestamp: expirationTimestamp,
            initiatorSignature: initiatorSignature
        });

        // Check if there are enough valid approvals (with Merkle proofs for membership verification)
        return LibOrganizationPolicy.areApprovalsValid({
            policy: proofs.policy,
            signatures: reviewSignatures,
            messageHash: reviewHash,
            approverProofs: proofs.approverProofs
        });
    }

    /**
     * @dev Computes the EIP-712 hash for initiator signatures.
     *      Creates a typed data hash following EIP-712 standard for the
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
                LibOrganizationEIP712.INITIATE_SIGNATURE_VALIDATION_TYPEHASH,
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
     * @dev Computes the EIP-712 hash for reviewer signatures.
     *      Creates a typed data hash for the ReviewSignatureValidation struct type.
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
                LibOrganizationEIP712.REVIEW_SIGNATURE_VALIDATION_TYPEHASH,
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
