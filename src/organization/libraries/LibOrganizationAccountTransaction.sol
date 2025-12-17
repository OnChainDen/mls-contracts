// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { LibOrganizationPolicy } from "./LibOrganizationPolicy.sol";
import { LibOrganizationSignatures } from "./LibOrganizationSignatures.sol";
import { LibOrganizationPolicyStorage } from "./storage/LibOrganizationPolicyStorage.sol";
import { Policies } from "../../libraries/Policies.sol";
import { SignatureUtils } from "../../libraries/SignatureUtils.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title Lib Organization Account Transaction
 * @notice Library for validating account transactions through the Organization contract
 * @dev This library handles validation of transactions to Account contracts
 * @author Den Technologies Inc
 */
library LibOrganizationAccountTransaction {
    /**
     * @notice Emitted when a transaction is rejected by a policy
     * @param reason The reason for the rejection
     */
    error TransactionRejectedByPolicy(string reason);

    /**
     * @notice Emitted when a transaction rejection is not allowed
     * @param reason The reason why the rejection is not allowed
     */
    error TransactionRejectionNotAllowed(string reason);

    /**
     * @notice Emitted when a transaction is rejected because it has insufficient approvals
     * @param required The number of required approvals
     * @param provided The number of provided approvals
     */
    error InsufficientApprovals(uint256 required, uint256 provided);

    /**
     * @notice Emitted when a transaction is rejected because the policy does not exist
     * @param policyId The policy ID that was not found
     */
    error PolicyNotFound(uint256 policyId);

    /**
     * @notice Emitted when a transaction is rejected because the policy does not apply to the transaction
     * @param policyId The policy ID that does not apply
     */
    error PolicyDoesNotApply(uint256 policyId);

    /**
     * @notice Emitted when a transaction has expired
     * @param expirationTimestamp The expiration timestamp that was exceeded
     * @param currentTimestamp The current block timestamp
     */
    error TransactionExpired(uint256 expirationTimestamp, uint256 currentTimestamp);

    /**
     * @notice Emitted when the initiator signature is invalid or missing
     */
    error InvalidInitiatorSignature();

    /**
     * @notice Emitted when signatures bytes are too short (must contain at least initiator signature)
     */
    error InsufficientSignaturesLength();

    /**
     * @notice Validates a transaction against the specified policy
     * @dev The signatures parameter is structured as: [initiatorSignature (65 bytes)][reviewSignatures (N * 65 bytes)]
     *      The initiator signature is verified against the base transaction hash.
     *      Review signatures are verified against a hash that includes the initiator signature,
     *      ensuring reviewers explicitly approve this specific initiation.
     * @param account The account executing the transaction
     * @param to Transaction destination address
     * @param value Transaction value
     * @param data Transaction data
     * @param salt User-provided salt for nonce computation
     * @param expirationTimestamp The timestamp after which the signatures are no longer valid
     * @param policyId The policy ID to validate against
     * @param signatures Signatures for approval verification (initiator signature first, then review signatures)
     */
    function validateTransactionApproval(
        address account,
        address to,
        uint256 value,
        bytes memory data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bytes memory signatures
    )
        internal
        view
    {
        // Check if the transaction has expired
        if (block.timestamp > expirationTimestamp) {
            revert TransactionExpired(expirationTimestamp, block.timestamp);
        }

        // Signatures must contain at least the initiator signature (65 bytes)
        if (signatures.length < 65) {
            revert InsufficientSignaturesLength();
        }

        LibOrganizationPolicyStorage.Layout storage policyStorage = LibOrganizationPolicyStorage.layout();

        // Validate that policy exists
        if (!policyStorage.policyExists[policyId]) {
            revert PolicyNotFound(policyId);
        }

        // Look up policy directly
        Policies.Policy memory policy = policyStorage.policies[policyId];

        // Extract initiator signature (first 65 bytes)
        bytes memory initiatorSignature = SignatureUtils.extractSignature(signatures, 0);

        // Get the base transaction hash that the initiator signs
        bytes32 initiatorTxHash =
            _getInitiatorTransactionHash(account, to, value, data, salt, expirationTimestamp, policyId, true);

        // Recover the initiator address from the signature
        address initiator = ECDSA.recover(initiatorTxHash, initiatorSignature);
        if (initiator == address(0)) {
            revert InvalidInitiatorSignature();
        }

        // Validate that policy applies to transaction with the recovered initiator
        // Note: This includes validating that the initiator is authorized by the policy
        if (!LibOrganizationPolicy.doesPolicyApplyToTransaction(policy, account, to, value, data, initiator)) {
            revert PolicyDoesNotApply(policyId);
        }

        // Case: Policy is AutoApprove
        // Only the initiator signature is required (already validated above)
        if (policy.policyType == Policies.PolicyType.AutoApprove) {
            return;
        }

        // Case: Policy is a manual approval policy
        // Check if the transaction has enough valid review approvals
        if (policy.policyType == Policies.PolicyType.RequireManualApproval) {
            uint256 requiredApprovals = LibOrganizationPolicy.getRequiredApprovals(policy);

            // Extract review signatures (everything after the first 65 bytes)
            bytes memory reviewSignatures = LibOrganizationSignatures.extractReviewSignatures(signatures);

            // Get the review transaction hash that includes the initiator signature
            // This binds reviewers to this specific initiation
            bytes32 reviewTxHash = _getReviewTransactionHash(
                account, to, value, data, salt, expirationTimestamp, policyId, true, initiatorSignature
            );

            // Count valid review approvals
            uint256 validApprovals = LibOrganizationPolicy.getValidApprovals(policy, reviewSignatures, reviewTxHash);

            // Case: Transaction does not have enough valid approvals
            if (validApprovals < requiredApprovals) {
                revert InsufficientApprovals(requiredApprovals, validApprovals);
            }
            return;
        }
    }

    /**
     * @notice Validates that the caller is authorized to reject the given transaction
     * @dev The signatures parameter is structured as: [initiatorSignature (65 bytes)][reviewSignatures (N * 65 bytes)]
     *      For rejection, the initiator signature proves who initiated the transaction being rejected.
     *      Review signatures are verified against a hash that includes the initiator signature.
     * @param account The account for which the transaction is being rejected
     * @param to Transaction destination address
     * @param value Transaction value
     * @param data Transaction data
     * @param salt User-provided salt for nonce computation
     * @param expirationTimestamp The timestamp after which the signatures are no longer valid
     * @param policyId The policy ID to validate against
     * @param signatures Signatures for rejection verification (initiator signature first, then review signatures)
     */
    function validateTransactionRejection(
        address account,
        address to,
        uint256 value,
        bytes memory data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bytes memory signatures
    )
        internal
        view
    {
        // Check if the transaction has expired
        if (block.timestamp > expirationTimestamp) {
            revert TransactionExpired(expirationTimestamp, block.timestamp);
        }

        // Signatures must contain at least the initiator signature (65 bytes)
        if (signatures.length < 65) {
            revert InsufficientSignaturesLength();
        }

        LibOrganizationPolicyStorage.Layout storage policyStorage = LibOrganizationPolicyStorage.layout();

        // Validate that policy exists
        if (!policyStorage.policyExists[policyId]) {
            revert PolicyNotFound(policyId);
        }

        // Look up policy directly
        Policies.Policy memory policy = policyStorage.policies[policyId];

        // Extract initiator signature (first 65 bytes)
        bytes memory initiatorSignature = SignatureUtils.extractSignature(signatures, 0);

        // Get the base transaction hash that the initiator signed (isApproval = true, same as approval)
        // Note: The initiator signed the approval hash, not the rejection hash
        bytes32 initiatorTxHash =
            _getInitiatorTransactionHash(account, to, value, data, salt, expirationTimestamp, policyId, true);

        // Recover the initiator address from the signature
        address initiator = ECDSA.recover(initiatorTxHash, initiatorSignature);
        if (initiator == address(0)) {
            revert InvalidInitiatorSignature();
        }

        // Validate that policy applies to transaction with the recovered initiator
        // Note: This includes validating that the initiator is authorized by the policy
        if (!LibOrganizationPolicy.doesPolicyApplyToTransaction(policy, account, to, value, data, initiator)) {
            revert PolicyDoesNotApply(policyId);
        }

        // Case: Policy is an automatic approval policy
        // Any authorized initiator (as defined by the policy) can reject the transaction
        if (policy.policyType == Policies.PolicyType.AutoApprove) {
            // For AutoApprove rejection, we need a rejection signature from any authorized initiator
            bytes32 rejectionTxHash =
                _getInitiatorTransactionHash(account, to, value, data, salt, expirationTimestamp, policyId, false);

            // Extract the rejection signature (should be at position 1, i.e., bytes 65-129)
            if (signatures.length < 130) {
                revert TransactionRejectionNotAllowed("AutoApprove rejection requires authorized initiator signature");
            }
            bytes memory rejectionSignature = SignatureUtils.extractSignature(signatures, 1);

            // Verify the rejection signature is from an authorized initiator (not necessarily the original initiator)
            address rejectionSigner = ECDSA.recover(rejectionTxHash, rejectionSignature);
            if (!LibOrganizationPolicy.doesTransactionMatchPolicyInitiator(policy, rejectionSigner)) {
                revert TransactionRejectionNotAllowed("Rejection signature must be from an authorized initiator");
            }
            return;
        }

        // Case: Policy is a manual approval policy
        // Check if there are sufficient rejection signatures from reviewers
        if (policy.policyType == Policies.PolicyType.RequireManualApproval) {
            uint256 requiredApprovals = LibOrganizationPolicy.getRequiredApprovals(policy);

            // Extract review signatures (everything after the first 65 bytes)
            bytes memory reviewSignatures = LibOrganizationSignatures.extractReviewSignatures(signatures);

            // Get the review transaction hash for rejection (isApproval = false)
            // This binds reviewers to rejecting this specific initiation
            bytes32 reviewTxHash = _getReviewTransactionHash(
                account, to, value, data, salt, expirationTimestamp, policyId, false, initiatorSignature
            );

            // Count valid review rejections
            uint256 validApprovals = LibOrganizationPolicy.getValidApprovals(policy, reviewSignatures, reviewTxHash);

            // Case: Transaction does not have enough valid rejections
            if (validApprovals < requiredApprovals) {
                revert InsufficientApprovals(requiredApprovals, validApprovals);
            }
            return;
        }
    }

    /**
     * @notice Creates a hash of the transaction for initiator signature verification using EIP-712 typed data
     * @dev This is the base transaction hash that the initiator signs to start the transaction flow
     * @param account The account executing the transaction
     * @param to The destination address of the transaction
     * @param value The value of the transaction
     * @param data The data of the transaction
     * @param salt The user-provided salt for nonce computation
     * @param expirationTimestamp The timestamp after which the signatures are no longer valid
     * @param policyId The policy ID governing this transaction
     * @param isApproval Whether the signature is for an approval or a rejection
     * @return The hash of the transaction formatted for signature verification
     */
    function _getInitiatorTransactionHash(
        address account,
        address to,
        uint256 value,
        bytes memory data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bool isApproval
    )
        private
        view
        returns (bytes32)
    {
        // Create EIP-712 structured data hash
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "InitiateAccountTransaction(address organization,address account,address to,uint256 value,bytes data,uint256 salt,uint256 expirationTimestamp,uint256 policyId,bool isApproval,uint256 chainId)"
                ),
                address(this),
                account,
                to,
                value,
                keccak256(data),
                salt,
                expirationTimestamp,
                policyId,
                isApproval,
                block.chainid
            )
        );

        // Return EIP-712 compatible hash for signature verification
        return MessageHashUtils.toTypedDataHash(_getDomainSeparator(), structHash);
    }

    /**
     * @notice Creates a hash for reviewer signature verification that includes the initiator's signature
     * @dev This hash binds reviewers to a specific initiation by including the initiator's signature.
     *      This ensures reviewers are explicitly approving this particular initiation.
     * @param account The account executing the transaction
     * @param to The destination address of the transaction
     * @param value The value of the transaction
     * @param data The data of the transaction
     * @param salt The user-provided salt for nonce computation
     * @param expirationTimestamp The timestamp after which the signatures are no longer valid
     * @param policyId The policy ID governing this transaction
     * @param isApproval Whether the signature is for an approval or a rejection
     * @param initiatorSignature The initiator's signature that reviewers are approving
     * @return The hash for reviewer signature verification
     */
    function _getReviewTransactionHash(
        address account,
        address to,
        uint256 value,
        bytes memory data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bool isApproval,
        bytes memory initiatorSignature
    )
        private
        view
        returns (bytes32)
    {
        // Create EIP-712 structured data hash that includes the initiator signature hash
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "ReviewAccountTransaction(address organization,address account,address to,uint256 value,bytes data,uint256 salt,uint256 expirationTimestamp,uint256 policyId,bool isApproval,uint256 chainId,bytes initiatorSignature)"
                ),
                address(this),
                account,
                to,
                value,
                keccak256(data),
                salt,
                expirationTimestamp,
                policyId,
                isApproval,
                block.chainid,
                keccak256(initiatorSignature)
            )
        );

        // Return EIP-712 compatible hash for signature verification
        return MessageHashUtils.toTypedDataHash(_getDomainSeparator(), structHash);
    }

    /**
     * @notice Returns the EIP-712 domain separator for this organization
     * @return The domain separator hash
     */
    function _getDomainSeparator() private view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("OnchainCustodyOrganization"),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }
}
