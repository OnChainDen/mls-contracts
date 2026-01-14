// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IOrganizationAccountTransaction} from "../../interfaces/organization/IOrganizationAccountTransaction.sol";
import {SignatureUtils} from "../../libraries/SignatureUtils.sol";
import {TokenTransferUtils} from "../../libraries/TokenTransferUtils.sol";
import {Policy, PolicyLimitation, PolicyType, TransactionType, ValidationProofs} from "../../types/PolicyTypes.sol";
import {LibOrganizationEIP712} from "./LibOrganizationEIP712.sol";
import {LibOrganizationPolicy} from "./LibOrganizationPolicy.sol";
import {LibOrganizationSignatures} from "./LibOrganizationSignatures.sol";

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title Lib Organization Account Transaction
 * @dev Library for validating account transactions through the Organization contract
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
     * @dev Struct to reduce stack depth when passing transaction parameters
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

    /**
     * @dev Validates a transaction against the specified policy using merkle proofs
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
        ValidationProofs calldata proofs
    ) internal {
        // Check transaction hasn't expired
        if (block.timestamp > expirationTimestamp) {
            revert IOrganizationAccountTransaction.TransactionExpired(expirationTimestamp, block.timestamp);
        }

        // Need at least one signature (initiator's SIGNATURE_LENGTH-byte signature)
        if (signatures.length < SignatureUtils.SIGNATURE_LENGTH) {
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

        // Extract initiator signature and recover signer address
        bytes memory initiatorSignature = SignatureUtils.extractSignature(signatures, 0);
        address initiator = _recoverInitiatorFromParams(params, data, initiatorSignature);

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

        // Case: Policy requires manual approval
        // Validate that we have enough valid approvals
        if (proofs.policy.config.approval.policyType == PolicyType.RequireManualApproval) {
            _validateManualConfirmationOrRevert({
                params: params,
                data: data,
                signatures: signatures,
                initiatorSignature: initiatorSignature,
                proofs: proofs,
                isApproval: true
            });
        }

        // Update time-based limits if applicable (for all policy types)
        _validateAndUpdateTimeBasedLimitOrRevert({
            params: params, data: data, initiator: initiator, policy: proofs.policy
        });
    }

    /**
     * @dev Validates that the caller is authorized to reject the given transaction
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
        ValidationProofs calldata proofs
    ) internal view {
        // Check transaction hasn't expired (can only reject pending transactions)
        if (block.timestamp > expirationTimestamp) {
            revert IOrganizationAccountTransaction.TransactionExpired(expirationTimestamp, block.timestamp);
        }

        // Need at least one signature
        if (signatures.length < SignatureUtils.SIGNATURE_LENGTH) {
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

        // Extract initiator signature and recover original initiator
        bytes memory initiatorSignature = SignatureUtils.extractSignature(signatures, 0);
        address initiator = _recoverInitiatorFromParams(params, data, initiatorSignature);

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
        PolicyType pType = proofs.policy.config.approval.policyType;

        // AutoApprove: Need an authorized initiator to sign the rejection
        if (pType == PolicyType.AutoApprove) {
            _validateAutoApproveRejectionOrRevert({params: params, data: data, signatures: signatures, proofs: proofs});
        }
        // ManualApproval: Need threshold approvals for the rejection
        else if (pType == PolicyType.RequireManualApproval) {
            _validateManualConfirmationOrRevert({
                params: params,
                data: data,
                signatures: signatures,
                initiatorSignature: initiatorSignature,
                proofs: proofs,
                isApproval: false
            });
        }
    }

    /**
     * @dev Validates and updates time-based limits for approved transactions
     * @dev Only applies if the policy has TimeInterval limitation.
     *      For token transfers, tracks the transfer amount.
     *      For other transactions, tracks count (usage = 1).
     *      Reverts if the limit would be exceeded.
     * @param params The packed transaction parameters
     * @param data The transaction calldata
     * @param initiator The initiator's address
     * @param policy The policy being used
     */
    function _validateAndUpdateTimeBasedLimitOrRevert(
        TxParams memory params,
        bytes calldata data,
        address initiator,
        Policy calldata policy
    ) private {
        // Only process if policy has time-based limits
        if (policy.config.timeLimit.limitation != PolicyLimitation.TimeInterval) {
            return;
        }

        // Determine the actual destination (may differ for token transfers)
        address destination = LibOrganizationPolicy.getActualDestination(params.to, data, params.value);

        // Calculate usage amount: token amount for transfers, 1 for other transactions
        uint256 usageAmount;
        if (policy.config.transactionType == TransactionType.TokenTransfers) {
            usageAmount = TokenTransferUtils.extractTransferAmount(data, params.value);
        } else {
            usageAmount = 1; // Count-based limit for non-transfer transactions
        }

        // Check limit and update usage tracking
        bool withinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit({
            policyId: params.policyId,
            policy: policy,
            account: params.account,
            destination: destination,
            initiator: initiator,
            usageAmount: usageAmount
        });

        if (!withinLimit) {
            revert IOrganizationAccountTransaction.TimeBasedLimitExceeded(params.policyId);
        }
    }

    /**
     * @dev Validates rejection for auto-approve policies
     * @dev For auto-approve policies, rejection requires a second signature from
     *      an authorized initiator signing the rejection hash (isApproval = false)
     * @param params The packed transaction parameters
     * @param data The transaction calldata
     * @param signatures The signatures (original initiator + rejection signer)
     * @param proofs Merkle proofs and policy data
     */
    function _validateAutoApproveRejectionOrRevert(
        TxParams memory params,
        bytes calldata data,
        bytes memory signatures,
        ValidationProofs calldata proofs
    ) private view {
        // Compute the rejection hash (isApproval = false)
        bytes32 rejectionTxHash = _computeInitiatorHashFromParams(params, data, false);

        // Need a second signature for rejection authorization
        if (signatures.length < 130) {
            revert IOrganizationAccountTransaction.TransactionRejectionNotAllowed();
        }
        bytes memory rejectionSignature = SignatureUtils.extractSignature(signatures, 1);

        // Verify the rejection signer is an authorized initiator for this policy
        address rejectionSigner = ECDSA.recover(rejectionTxHash, rejectionSignature);
        if (!LibOrganizationPolicy.isInitiatorAuthorized(proofs.policy, rejectionSigner, proofs.initiatorProofs)) {
            revert IOrganizationAccountTransaction.TransactionRejectionNotAllowed();
        }
    }

    /**
     * @dev Recovers the initiator address from the transaction parameters and signature
     * @dev Computes the EIP-712 hash of the transaction and recovers the signer
     * @param params The packed transaction parameters
     * @param data The transaction calldata
     * @param initiatorSignature The initiator's ECDSA signature
     * @return The recovered initiator address
     */
    function _recoverInitiatorFromParams(TxParams memory params, bytes calldata data, bytes memory initiatorSignature)
        private
        view
        returns (address)
    {
        // Compute the hash the initiator should have signed (isApproval = true)
        bytes32 initiatorTxHash = _computeInitiatorHashFromParams(params, data, true);

        // Recover signer from signature (reverts on invalid signature)
        return ECDSA.recover(initiatorTxHash, initiatorSignature);
    }

    /**
     * @dev Validates manual approval/rejection signatures meet the required threshold
     * @dev Extracts reviewer signatures and validates against required threshold.
     *      Used for both approval and rejection flows - the isApproval flag determines
     *      which hash is computed for signature verification.
     * @param params The packed transaction parameters
     * @param data The transaction calldata
     * @param signatures All signatures (initiator + reviewers)
     * @param initiatorSignature The initiator's signature
     * @param proofs Merkle proofs and policy data
     * @param isApproval True for approval validation, false for rejection validation
     */
    function _validateManualConfirmationOrRevert(
        TxParams memory params,
        bytes calldata data,
        bytes memory signatures,
        bytes memory initiatorSignature,
        ValidationProofs calldata proofs,
        bool isApproval
    ) private view {
        // Get required approval count from policy
        uint256 requiredApprovals = LibOrganizationPolicy.getRequiredApprovals(proofs.policy);

        // Extract reviewer signatures (everything after initiator signature)
        bytes memory reviewSignatures = LibOrganizationSignatures.extractReviewSignatures(signatures);

        // Compute hash that reviewers should have signed
        // Includes initiator signature to bind approvals to specific request
        bytes32 reviewTxHash = _computeReviewHashFromParams(params, data, isApproval, initiatorSignature);

        // Count valid approvals from authorized signers (with Merkle proofs for membership verification)
        uint256 validApprovals = LibOrganizationPolicy.getValidApprovals(
            proofs.policy, reviewSignatures, reviewTxHash, proofs.approverProofs
        );

        if (validApprovals < requiredApprovals) {
            revert IOrganizationAccountTransaction.InsufficientApprovals(requiredApprovals, validApprovals);
        }
    }

    /**
     * @dev Computes the EIP-712 hash for initiator signatures
     * @dev Creates a typed data hash following EIP-712 standard for the
     *      InitiateAccountTransaction struct type. The isApproval flag
     *      distinguishes between approval and rejection signatures.
     * @param params The packed transaction parameters
     * @param data The transaction calldata
     * @param isApproval True for approval, false for rejection
     * @return The EIP-712 typed data hash for signing
     */
    function _computeInitiatorHashFromParams(TxParams memory params, bytes calldata data, bool isApproval)
        private
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
     * @dev Computes the EIP-712 hash for reviewer signatures
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
    ) private view returns (bytes32) {
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
