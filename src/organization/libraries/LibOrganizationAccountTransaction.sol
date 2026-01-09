// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { LibOrganizationPolicy } from "./LibOrganizationPolicy.sol";
import { LibOrganizationSignatures } from "./LibOrganizationSignatures.sol";
import { LibOrganizationEIP712 } from "./LibOrganizationEIP712.sol";
import { Policies } from "../../libraries/Policies.sol";
import { SignatureUtils } from "../../libraries/SignatureUtils.sol";
import { TokenTransferUtils } from "../../libraries/TokenTransferUtils.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title Lib Organization Account Transaction
 * @notice Library for validating account transactions through the Organization contract
 * @dev This library handles the core transaction validation logic for the organization.
 *      It validates that:
 *      1. The transaction hasn't expired
 *      2. A valid policy exists and applies to this transaction
 *      3. The initiator is authorized by the policy
 *      4. Required approvals have been collected (for manual approval policies)
 *      5. Time-based limits are not exceeded
 *
 *      Policies are verified via merkle proofs. Policy data is provided in calldata
 *      and verified against the organization's policy merkle root.
 *
 *      The library supports both transaction approval and rejection flows.
 *      Rejections require the same authorization level as approvals to prevent
 *      unauthorized actors from blocking legitimate transactions.
 * @author Den Technologies Inc
 */
library LibOrganizationAccountTransaction {
    /**
     * @notice Struct to reduce stack depth when passing transaction parameters
     * @dev Groups common transaction parameters that are used across multiple functions
     * @param account The source account executing the transaction
     * @param to The destination address
     * @param value The ETH value being sent
     * @param salt Unique salt to prevent replay attacks
     * @param expirationTimestamp When the transaction authorization expires
     * @param policyId The policy being used to authorize this transaction
     */
    struct TxParams {
        address account;
        address to;
        uint256 value;
        uint256 salt;
        uint256 expirationTimestamp;
        uint256 policyId;
    }

    // ================================
    // ERRORS
    // ================================

    /// @notice Thrown when a transaction is rejected due to policy rules
    error TransactionRejectedByPolicy(string reason);

    /// @notice Thrown when a rejection attempt is not authorized
    error TransactionRejectionNotAllowed(string reason);

    /// @notice Thrown when not enough valid approval signatures are provided
    error InsufficientApprovals(uint256 required, uint256 provided);

    /// @notice Thrown when the policy doesn't apply to this transaction
    error PolicyDoesNotApply(uint256 policyId);

    /// @notice Thrown when the transaction authorization has expired
    error TransactionExpired(uint256 expirationTimestamp, uint256 currentTimestamp);

    /// @notice Thrown when the initiator signature is invalid or missing
    error InvalidInitiatorSignature();

    /// @notice Thrown when the signatures bytes is too short
    error InsufficientSignaturesLength();

    /// @notice Thrown when the transaction exceeds the policy's time-based limit
    error TimeBasedLimitExceeded(uint256 policyId);

    // ================================
    // TRANSACTION APPROVAL
    // ================================

    /**
     * @notice Validates a transaction against the specified policy using merkle proofs
     * @dev Main entry point for transaction approval validation. This function:
     *      1. Verifies the transaction hasn't expired
     *      2. Extracts and validates the initiator signature
     *      3. Checks that the policy applies to this transaction
     *      4. Routes to appropriate approval flow based on policy type
     *      5. Updates time-based limits if applicable
     *      Reverts on validation failure.
     * @param account The source account executing the transaction
     * @param to The destination address
     * @param value The ETH value being sent
     * @param data The transaction calldata
     * @param salt Unique salt for replay protection
     * @param expirationTimestamp When the authorization expires
     * @param policyId The policy ID authorizing this transaction
     * @param signatures Concatenated signatures (initiator + optional approvers)
     * @param proofs Merkle proofs and policy data for validation
     */
    function validateTransactionApprovalOrRevert(
        address account,
        address to,
        uint256 value,
        bytes calldata data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bytes memory signatures,
        Policies.ValidationProofs calldata proofs
    )
        internal
    {
        // Check transaction hasn't expired
        if (block.timestamp > expirationTimestamp) {
            revert TransactionExpired(expirationTimestamp, block.timestamp);
        }

        // Need at least one signature (initiator's 65-byte signature)
        if (signatures.length < 65) {
            revert InsufficientSignaturesLength();
        }

        // Pack parameters into struct to manage stack depth
        TxParams memory params = TxParams({
            account: account,
            to: to,
            value: value,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            policyId: policyId
        });

        // Extract initiator signature and recover signer address
        bytes memory initiatorSignature = SignatureUtils.extractSignature(signatures, 0);
        address initiator = _recoverInitiatorFromParams(params, data, initiatorSignature);

        // Verify the policy exists and applies to this specific transaction
        if (!LibOrganizationPolicy.isTransactionAllowedByPolicy(policyId, account, to, value, data, initiator, proofs))
        {
            revert PolicyDoesNotApply(policyId);
        }

        // Route to appropriate approval flow based on policy type
        _processApproval(params, data, signatures, initiatorSignature, initiator, proofs);
    }

    /**
     * @notice Recovers the initiator address from the transaction parameters and signature
     * @dev Computes the EIP-712 hash of the transaction and recovers the signer
     * @param params The packed transaction parameters
     * @param data The transaction calldata
     * @param initiatorSignature The initiator's ECDSA signature
     * @return The recovered initiator address
     */
    function _recoverInitiatorFromParams(
        TxParams memory params,
        bytes calldata data,
        bytes memory initiatorSignature
    )
        private
        view
        returns (address)
    {
        // Compute the hash the initiator should have signed (isApproval = true)
        bytes32 initiatorTxHash = _computeInitiatorHashFromParams(params, data, true);

        // Recover signer from signature
        address initiator = ECDSA.recover(initiatorTxHash, initiatorSignature);
        if (initiator == address(0)) {
            revert InvalidInitiatorSignature();
        }
        return initiator;
    }

    /**
     * @notice Routes approval validation based on policy type
     * @dev For AutoApprove policies, just updates time limits.
     *      For ManualApproval policies, validates reviewer signatures first.
     * @param params The packed transaction parameters
     * @param data The transaction calldata
     * @param signatures All signatures (initiator + reviewers)
     * @param initiatorSignature The initiator's signature (extracted)
     * @param initiator The initiator's address
     * @param proofs Merkle proofs and policy data
     */
    function _processApproval(
        TxParams memory params,
        bytes calldata data,
        bytes memory signatures,
        bytes memory initiatorSignature,
        address initiator,
        Policies.ValidationProofs calldata proofs
    )
        private
    {
        Policies.PolicyType pType = proofs.policy.config.approval.policyType;

        // AutoApprove: Initiator signature alone is sufficient
        if (pType == Policies.PolicyType.AutoApprove) {
            _updateTimeLimitForAutoApprove(params, data, initiator, proofs.policy);
            return;
        }

        // ManualApproval: Validate reviewer signatures meet threshold
        if (pType == Policies.PolicyType.RequireManualApproval) {
            _validateAndUpdateManualApproval(params, data, signatures, initiatorSignature, initiator, proofs);
        }
    }

    /**
     * @notice Updates time-based limits for auto-approve transactions
     * @dev Only applies if the policy has TimeInterval limitation.
     *      For token transfers, tracks the transfer amount.
     *      For other transactions, tracks count (usage = 1).
     * @param params The packed transaction parameters
     * @param data The transaction calldata
     * @param initiator The initiator's address
     * @param policy The policy being used
     */
    function _updateTimeLimitForAutoApprove(
        TxParams memory params,
        bytes calldata data,
        address initiator,
        Policies.Policy calldata policy
    )
        private
    {
        // Only process if policy has time-based limits
        if (policy.config.timeLimit.limitation != Policies.PolicyLimitation.TimeInterval) {
            return;
        }

        // Determine the actual destination (may differ for token transfers)
        address destination = LibOrganizationPolicy.getActualDestination(params.to, data, params.value);

        // Calculate usage amount: token amount for transfers, 1 for other transactions
        uint256 usageAmount;
        if (policy.config.transactionType == Policies.TransactionType.TokenTransfers) {
            usageAmount = TokenTransferUtils.extractTransferAmount(data, params.value);
        } else {
            usageAmount = 1; // Count-based limit for non-transfer transactions
        }

        // Check limit and update usage tracking
        bool withinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            params.policyId, policy, params.account, destination, initiator, usageAmount
        );

        if (!withinLimit) {
            revert TimeBasedLimitExceeded(params.policyId);
        }
    }

    /**
     * @notice Validates manual approval signatures and updates time limits
     * @dev Extracts reviewer signatures, validates against required threshold,
     *      then updates time-based limits if all approvals are valid.
     * @param params The packed transaction parameters
     * @param data The transaction calldata
     * @param signatures All signatures (initiator + reviewers)
     * @param initiatorSignature The initiator's signature
     * @param initiator The initiator's address
     * @param proofs Merkle proofs and policy data
     */
    function _validateAndUpdateManualApproval(
        TxParams memory params,
        bytes calldata data,
        bytes memory signatures,
        bytes memory initiatorSignature,
        address initiator,
        Policies.ValidationProofs calldata proofs
    )
        private
    {
        // Get required approval count from policy
        uint256 requiredApprovals = LibOrganizationPolicy.getRequiredApprovals(proofs.policy);

        // Extract reviewer signatures (everything after initiator signature)
        bytes memory reviewSignatures = LibOrganizationSignatures.extractReviewSignatures(signatures);

        // Compute hash that reviewers should have signed
        // Includes initiator signature to bind approvals to specific request
        bytes32 reviewTxHash = _computeReviewHashFromParams(params, data, true, initiatorSignature);

        // Count valid approvals from authorized signers (with Merkle proofs for membership verification)
        uint256 validApprovals = LibOrganizationPolicy.getValidApprovals(
            proofs.policy, reviewSignatures, reviewTxHash, proofs.approverProofs
        );

        if (validApprovals < requiredApprovals) {
            revert InsufficientApprovals(requiredApprovals, validApprovals);
        }

        // Update time limits after successful approval validation
        _updateTimeLimitForAutoApprove(params, data, initiator, proofs.policy);
    }

    // ================================
    // TRANSACTION REJECTION
    // ================================

    /**
     * @notice Validates that the caller is authorized to reject the given transaction
     * @dev Rejection validation ensures that only authorized parties can reject transactions.
     *      This prevents griefing attacks where unauthorized actors could reject
     *      legitimate pending transactions.
     *      Reverts on validation failure.
     *
     *      For AutoApprove policies: requires a second initiator signature authorizing rejection
     *      For ManualApproval policies: requires threshold approvals for the rejection
     * @param account The source account of the transaction being rejected
     * @param to The destination address of the transaction
     * @param value The ETH value of the transaction
     * @param data The transaction calldata
     * @param salt The transaction salt
     * @param expirationTimestamp When the transaction expires
     * @param policyId The policy ID for the transaction
     * @param signatures Rejection signatures
     * @param proofs Merkle proofs and policy data
     */
    function validateTransactionRejectionOrRevert(
        address account,
        address to,
        uint256 value,
        bytes calldata data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bytes memory signatures,
        Policies.ValidationProofs calldata proofs
    )
        internal
        view
    {
        // Check transaction hasn't expired (can only reject pending transactions)
        if (block.timestamp > expirationTimestamp) {
            revert TransactionExpired(expirationTimestamp, block.timestamp);
        }

        // Need at least one signature
        if (signatures.length < 65) {
            revert InsufficientSignaturesLength();
        }

        // Pack parameters into struct
        TxParams memory params = TxParams({
            account: account,
            to: to,
            value: value,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            policyId: policyId
        });

        // Extract initiator signature and recover original initiator
        bytes memory initiatorSignature = SignatureUtils.extractSignature(signatures, 0);
        address initiator = _recoverInitiatorFromParams(params, data, initiatorSignature);

        // Verify policy applies to this transaction
        if (!LibOrganizationPolicy.isTransactionAllowedByPolicy(policyId, account, to, value, data, initiator, proofs))
        {
            revert PolicyDoesNotApply(policyId);
        }

        // Route to appropriate rejection validation
        _processRejection(params, data, signatures, initiatorSignature, proofs);
    }

    /**
     * @notice Routes rejection validation based on policy type
     * @dev Different policy types have different rejection requirements
     * @param params The packed transaction parameters
     * @param data The transaction calldata
     * @param signatures The rejection signatures
     * @param initiatorSignature The original initiator's signature
     * @param proofs Merkle proofs and policy data
     */
    function _processRejection(
        TxParams memory params,
        bytes calldata data,
        bytes memory signatures,
        bytes memory initiatorSignature,
        Policies.ValidationProofs calldata proofs
    )
        private
        view
    {
        Policies.PolicyType pType = proofs.policy.config.approval.policyType;

        // AutoApprove: Need an authorized initiator to sign the rejection
        if (pType == Policies.PolicyType.AutoApprove) {
            _validateAutoApproveRejection(params, data, signatures, proofs);
            return;
        }

        // ManualApproval: Need threshold approvals for the rejection
        if (pType == Policies.PolicyType.RequireManualApproval) {
            _validateManualRejection(params, data, signatures, initiatorSignature, proofs);
        }
    }

    /**
     * @notice Validates rejection for auto-approve policies
     * @dev For auto-approve policies, rejection requires a second signature from
     *      an authorized initiator signing the rejection hash (isApproval = false)
     * @param params The packed transaction parameters
     * @param data The transaction calldata
     * @param signatures The signatures (original initiator + rejection signer)
     * @param proofs Merkle proofs and policy data
     */
    function _validateAutoApproveRejection(
        TxParams memory params,
        bytes calldata data,
        bytes memory signatures,
        Policies.ValidationProofs calldata proofs
    )
        private
        view
    {
        // Compute the rejection hash (isApproval = false)
        bytes32 rejectionTxHash = _computeInitiatorHashFromParams(params, data, false);

        // Need a second signature for rejection authorization
        if (signatures.length < 130) {
            revert TransactionRejectionNotAllowed("AutoApprove rejection requires authorized initiator signature");
        }
        bytes memory rejectionSignature = SignatureUtils.extractSignature(signatures, 1);

        // Verify the rejection signer is an authorized initiator for this policy
        address rejectionSigner = ECDSA.recover(rejectionTxHash, rejectionSignature);
        if (!LibOrganizationPolicy.isInitiatorAuthorized(proofs.policy, rejectionSigner, proofs.initiatorProofs)) {
            revert TransactionRejectionNotAllowed("Rejection signature must be from an authorized initiator");
        }
    }

    /**
     * @notice Validates rejection for manual approval policies
     * @dev For manual approval policies, rejection requires the same threshold
     *      of approvals as a regular transaction, but signing the rejection hash
     * @param params The packed transaction parameters
     * @param data The transaction calldata
     * @param signatures All rejection signatures
     * @param initiatorSignature The original initiator's signature
     * @param proofs Merkle proofs and policy data
     */
    function _validateManualRejection(
        TxParams memory params,
        bytes calldata data,
        bytes memory signatures,
        bytes memory initiatorSignature,
        Policies.ValidationProofs calldata proofs
    )
        private
        view
    {
        // Get required approval count
        uint256 requiredApprovals = LibOrganizationPolicy.getRequiredApprovals(proofs.policy);

        // Extract reviewer signatures
        bytes memory reviewSignatures = LibOrganizationSignatures.extractReviewSignatures(signatures);

        // Compute rejection review hash (isApproval = false)
        bytes32 reviewTxHash = _computeReviewHashFromParams(params, data, false, initiatorSignature);

        // Count valid rejection approvals (with Merkle proofs for membership verification)
        uint256 validApprovals = LibOrganizationPolicy.getValidApprovals(
            proofs.policy, reviewSignatures, reviewTxHash, proofs.approverProofs
        );

        if (validApprovals < requiredApprovals) {
            revert InsufficientApprovals(requiredApprovals, validApprovals);
        }
    }

    // ================================
    // EIP-712 HASH COMPUTATION
    // ================================

    /**
     * @notice Computes the EIP-712 hash for initiator signatures
     * @dev Creates a typed data hash following EIP-712 standard for the
     *      InitiateAccountTransaction struct type. The isApproval flag
     *      distinguishes between approval and rejection signatures.
     * @param params The packed transaction parameters
     * @param data The transaction calldata
     * @param isApproval True for approval, false for rejection
     * @return The EIP-712 typed data hash for signing
     */
    function _computeInitiatorHashFromParams(
        TxParams memory params,
        bytes calldata data,
        bool isApproval
    )
        private
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "InitiateAccountTransaction(address organization,address account,address to,uint256 value,bytes data,uint256 salt,uint256 expirationTimestamp,uint256 policyId,bool isApproval,uint256 chainId)"
                ),
                address(this),
                params.account,
                params.to,
                params.value,
                keccak256(data),
                params.salt,
                params.expirationTimestamp,
                params.policyId,
                isApproval,
                block.chainid
            )
        );

        return MessageHashUtils.toTypedDataHash(LibOrganizationEIP712.getDomainSeparator(), structHash);
    }

    /**
     * @notice Computes the EIP-712 hash for reviewer signatures
     * @dev Creates a typed data hash for the ReviewAccountTransaction struct type.
     *      Includes the initiator signature to bind approvals to a specific request.
     * @param params The packed transaction parameters
     * @param data The transaction calldata
     * @param isApproval True for approval, false for rejection
     * @param initiatorSignature The initiator's signature (included in hash)
     * @return The EIP-712 typed data hash for signing
     */
    function _computeReviewHashFromParams(
        TxParams memory params,
        bytes calldata data,
        bool isApproval,
        bytes memory initiatorSignature
    )
        private
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "ReviewAccountTransaction(address organization,address account,address to,uint256 value,bytes data,uint256 salt,uint256 expirationTimestamp,uint256 policyId,bool isApproval,uint256 chainId,bytes initiatorSignature)"
                ),
                address(this),
                params.account,
                params.to,
                params.value,
                keccak256(data),
                params.salt,
                params.expirationTimestamp,
                params.policyId,
                isApproval,
                block.chainid,
                keccak256(initiatorSignature)
            )
        );

        return MessageHashUtils.toTypedDataHash(LibOrganizationEIP712.getDomainSeparator(), structHash);
    }
}
