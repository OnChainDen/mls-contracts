// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAccountTransaction} from "interfaces/organization/IOrganizationAccountTransaction.sol";
import {SignatureUtils} from "libraries/SignatureUtils.sol";
import {TokenTransferUtils} from "libraries/TokenTransferUtils.sol";
import {LibOrganizationEIP712} from "organization/libraries/LibOrganizationEIP712.sol";
import {LibOrganizationPolicy} from "organization/libraries/LibOrganizationPolicy.sol";
import {Policy, PolicyType, RateLimitType, TransactionType, ValidationProofs} from "types/PolicyTypes.sol";

/**
 * @title Lib Organization Account Transaction
 * @dev Library for validating account transactions through the Organization contract.
 *      This library handles the core transaction validation logic for the organization.
 *      It validates that:
 *      1. The transaction hasn't expired
 *      2. A valid policy exists and applies to this transaction
 *      3. The initiator is authorized by the policy
 *      4. Required approvals have been collected (for manual approval policies)
 *      5. Rate limits are not exceeded
 *
 *      Policies are verified via merkle proofs against the organization's policy root.
 *      Members and groups are verified via direct mapping lookups.
 *
 *      The library supports both transaction approval and rejection flows.
 *      Rejections require the same authorization level as approvals to prevent
 *      unauthorized actors from blocking legitimate transactions.
 * @author Den Technologies Inc
 */
library LibOrganizationAccountTransaction {
    /**
     * @dev Struct to reduce stack depth when passing transaction parameters.
     *      Groups common transaction parameters that are used across multiple functions.
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

    /**
     * @dev Validates a transaction against the specified policy using merkle proofs.
     *      Main entry point for transaction approval validation. This function:
     *      1. Verifies the transaction hasn't expired
     *      2. Validates the initiator signature
     *      3. Checks that the policy applies to this transaction
     *      4. Routes to appropriate approval flow based on policy type
     *      5. Updates rate limits if applicable
     *      Reverts on validation failure.
     * @param account The source account executing the transaction
     * @param to The destination address
     * @param value The ETH value being sent
     * @param data The transaction calldata
     * @param salt Unique salt for replay protection
     * @param expirationTimestamp When the authorization expires
     * @param policyId The policy ID authorizing this transaction
     * @param initiatorSignature The initiator's signature authorizing the transaction
     * @param reviewSignatures The reviewer signatures (empty for auto-approve policies)
     * @param proofs Policy data, merkle proofs, and group IDs for validation
     */
    function validateTransactionApprovalOrRevert(
        address account,
        address to,
        uint256 value,
        bytes calldata data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bytes memory initiatorSignature,
        bytes memory reviewSignatures,
        ValidationProofs calldata proofs
    ) internal {
        // Check transaction hasn't expired
        if (block.timestamp > expirationTimestamp) {
            revert IOrganizationAccountTransaction.TransactionExpired(expirationTimestamp, block.timestamp);
        }

        // Need a valid initiator signature
        if (initiatorSignature.length == 0) {
            revert IOrganizationAccountTransaction.InsufficientSignaturesLength();
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

        // Compute the hash the initiator should have signed and recover the signer
        bytes32 initiatorTxHash = _computeInitiatorHashFromParams(params, data, true);
        address initiator = SignatureUtils.recoverSignerOrRevert(initiatorSignature, initiatorTxHash);

        // Verify the policy exists and applies to this specific transaction
        if (!LibOrganizationPolicy.isTransactionAllowedByPolicy({
                policyId: policyId,
                sourceAccount: account,
                to: to,
                value: value,
                data: data,
                initiator: initiator,
                proofs: proofs
            })) {
            revert IOrganizationAccountTransaction.PolicyDoesNotApply(policyId);
        }

        PolicyType approvalPolicyType = proofs.policy.config.approval.policyType;

        // Case: Policy requires manual approval
        // Validate that we have enough valid approvals
        if (approvalPolicyType == PolicyType.RequireManualApproval) {
            _validateManualConfirmationOrRevert({
                params: params,
                data: data,
                reviewSignatures: reviewSignatures,
                initiatorSignature: initiatorSignature,
                proofs: proofs,
                isApproval: true
            });
        } else if (approvalPolicyType != PolicyType.AutoApprove) {
            // Fail closed on unknown approval-policy enum values.
            revert IOrganizationAccountTransaction.PolicyDoesNotApply(policyId);
        }

        // Update rate limits if applicable (for all policy types)
        _validateAndUpdateRateLimitOrRevert({params: params, data: data, initiator: initiator, policy: proofs.policy});
    }

    /**
     * @dev Validates and updates rate limits for approved transactions.
     *      Only applies if the policy has TimeInterval rate limit.
     *      For `TokenTransfers` policies the bucket accrues the transferred token amount.
     *      For all other `transactionType` values (including `Any`) it accrues `1` per call
     *      even when the calldata is an ERC-20 transfer.
     *      Reverts if the limit would be exceeded.
     * @param params The packed transaction parameters
     * @param data The transaction calldata
     * @param initiator The initiator's address
     * @param policy The policy being used
     */
    function _validateAndUpdateRateLimitOrRevert(
        TxParams memory params,
        bytes calldata data,
        address initiator,
        Policy calldata policy
    ) internal {
        RateLimitType rateLimitType = policy.config.rateLimit.limitType;

        // Case: Policy explicitly disables rate limiting.
        if (rateLimitType == RateLimitType.None) {
            return;
        }

        // Case: Unknown rate-limit enum value fails closed.
        if (rateLimitType != RateLimitType.TimeInterval) {
            revert IOrganizationAccountTransaction.UnknownRateLimitType(params.policyId);
        }

        // Determine the actual destination (may differ for token transfers)
        address destination = LibOrganizationPolicy.getActualDestination(params.to, data, params.value);

        // Usage unit is keyed off `transactionType`, not calldata shape, so non-`TokenTransfers`
        // policies (notably `Any`) always accrue `1` even when the call is an ERC-20 transfer.
        uint256 usageAmount;
        if (policy.config.transactionType == TransactionType.TokenTransfers) {
            usageAmount = TokenTransferUtils.extractTransferAmount(data, params.value);
        } else {
            usageAmount = 1;
        }

        // Check limit and update usage tracking
        bool withinLimit = LibOrganizationPolicy.checkAndUpdateRateLimit({
            policyId: params.policyId,
            policy: policy,
            account: params.account,
            destination: destination,
            initiator: initiator,
            usageAmount: usageAmount
        });

        if (!withinLimit) {
            revert IOrganizationAccountTransaction.RateLimitExceeded(params.policyId);
        }
    }

    /**
     * @dev Validates that the caller is authorized to reject the given transaction.
     *      Rejection validation ensures that only authorized parties can reject transactions.
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
     * @param initiatorSignature The initiator's signature for the original transaction
     * @param reviewSignatures The reviewer signatures authorizing the rejection
     * @param proofs Policy data, merkle proofs, and group IDs for validation
     */
    function validateTransactionRejectionOrRevert(
        address account,
        address to,
        uint256 value,
        bytes calldata data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bytes memory initiatorSignature,
        bytes memory reviewSignatures,
        ValidationProofs calldata proofs
    ) internal view {
        // Check transaction hasn't expired (can only reject pending transactions)
        if (block.timestamp > expirationTimestamp) {
            revert IOrganizationAccountTransaction.TransactionExpired(expirationTimestamp, block.timestamp);
        }

        // Need a valid initiator signature
        if (initiatorSignature.length == 0) {
            revert IOrganizationAccountTransaction.InsufficientSignaturesLength();
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

        // Compute the hash the initiator should have signed and recover the signer
        bytes32 initiatorTxHash = _computeInitiatorHashFromParams(params, data, true);
        address initiator = SignatureUtils.recoverSignerOrRevert(initiatorSignature, initiatorTxHash);

        // Verify policy applies to this transaction
        if (!LibOrganizationPolicy.isTransactionAllowedByPolicy({
                policyId: policyId,
                sourceAccount: account,
                to: to,
                value: value,
                data: data,
                initiator: initiator,
                proofs: proofs
            })) {
            revert IOrganizationAccountTransaction.PolicyDoesNotApply(policyId);
        }

        // Route to appropriate rejection validation based on policy type
        PolicyType policyType = proofs.policy.config.approval.policyType;

        // AutoApprove: Need an authorized initiator to sign the rejection
        if (policyType == PolicyType.AutoApprove) {
            _validateAutoApproveRejectionOrRevert({
                params: params, data: data, reviewSignatures: reviewSignatures, proofs: proofs
            });
        }
        // ManualApproval: Need threshold approvals for the rejection
        else if (policyType == PolicyType.RequireManualApproval) {
            _validateManualConfirmationOrRevert({
                params: params,
                data: data,
                reviewSignatures: reviewSignatures,
                initiatorSignature: initiatorSignature,
                proofs: proofs,
                isApproval: false
            });
        } else {
            revert IOrganizationAccountTransaction.PolicyDoesNotApply(policyId);
        }
    }

    /**
     * @dev Validates rejection for auto-approve policies.
     *      For auto-approve policies, rejection requires a signature from
     *      an authorized initiator signing the rejection hash (isApproval = false).
     *      Supports both EOA (ECDSA) and ERC-1271 (smart contract) signatures.
     * @param params The packed transaction parameters
     * @param data The transaction calldata
     * @param reviewSignatures The rejection signature from an authorized initiator
     * @param proofs Policy data, merkle proofs, and group IDs for validation
     */
    function _validateAutoApproveRejectionOrRevert(
        TxParams memory params,
        bytes calldata data,
        bytes memory reviewSignatures,
        ValidationProofs calldata proofs
    ) internal view {
        // Compute the rejection hash (isApproval = false)
        bytes32 rejectionTxHash = _computeInitiatorHashFromParams(params, data, false);

        // Case: No rejection signature provided
        if (reviewSignatures.length == 0) {
            revert IOrganizationAccountTransaction.TransactionRejectionNotAllowed();
        }

        // Recover the rejection signer (starts at offset 0 since reviewSignatures is separate)
        address rejectionSigner = SignatureUtils.recoverSignerOrRevert(reviewSignatures, rejectionTxHash);

        // Verify the rejection signer is an authorized initiator for this policy
        if (!LibOrganizationPolicy.isInitiatorAuthorized(proofs.policy, rejectionSigner)) {
            revert IOrganizationAccountTransaction.TransactionRejectionNotAllowed();
        }
    }

    /**
     * @dev Validates manual approval/rejection signatures meet the required threshold.
     *      Validates review signatures against required threshold.
     *      Used for both approval and rejection flows - the isApproval flag determines
     *      which hash is computed for signature verification.
     * @param params The packed transaction parameters
     * @param data The transaction calldata
     * @param reviewSignatures The reviewer signatures
     * @param initiatorSignature The initiator's signature (for hash binding)
     * @param proofs Policy data, merkle proofs, and group IDs for validation
     * @param isApproval True for approval validation, false for rejection validation
     */
    function _validateManualConfirmationOrRevert(
        TxParams memory params,
        bytes calldata data,
        bytes memory reviewSignatures,
        bytes memory initiatorSignature,
        ValidationProofs calldata proofs,
        bool isApproval
    ) internal view {
        // Get required approval count from policy
        uint256 requiredApprovals = LibOrganizationPolicy.getRequiredApprovals(proofs.policy);

        // Compute hash that reviewers should have signed
        // Includes initiator signature to bind approvals to specific request
        bytes32 reviewTxHash = _computeReviewHashFromParams(params, data, isApproval, initiatorSignature);

        // Check if there are enough valid approvals (with mapping lookups for membership verification)
        bool approvalsValid = LibOrganizationPolicy.areApprovalsValid({
            policy: proofs.policy, signatures: reviewSignatures, messageHash: reviewTxHash
        });

        if (!approvalsValid) {
            revert IOrganizationAccountTransaction.InsufficientApprovals(requiredApprovals, 0);
        }
    }

    /**
     * @dev Computes the EIP-712 hash for initiator signatures.
     *      Creates a typed data hash following EIP-712 standard for the
     *      InitiateAccountTransaction struct type. The isApproval flag
     *      distinguishes between approval and rejection signatures.
     * @param params The packed transaction parameters
     * @param data The transaction calldata
     * @param isApproval True for approval, false for rejection
     * @return The EIP-712 typed data hash for signing
     */
    function _computeInitiatorHashFromParams(TxParams memory params, bytes calldata data, bool isApproval)
        internal
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                LibOrganizationEIP712.INITIATE_ACCOUNT_TRANSACTION_TYPEHASH,
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

        return LibOrganizationEIP712.computeTypedDataHash(structHash);
    }

    /**
     * @dev Computes the EIP-712 hash for reviewer signatures.
     *      Creates a typed data hash for the ReviewAccountTransaction struct type.
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
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                LibOrganizationEIP712.REVIEW_ACCOUNT_TRANSACTION_TYPEHASH,
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

        return LibOrganizationEIP712.computeTypedDataHash(structHash);
    }
}
