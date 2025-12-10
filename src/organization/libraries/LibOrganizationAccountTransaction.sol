// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { LibOrganizationSignatures } from "./LibOrganizationSignatures.sol";
import { LibOrganizationPolicy } from "./LibOrganizationPolicy.sol";
import { LibOrganizationMembersStorage } from "./storage/LibOrganizationMembersStorage.sol";
import { LibOrganizationPolicyStorage } from "./storage/LibOrganizationPolicyStorage.sol";
import { Policies } from "../../libraries/Policies.sol";
import { SignatureUtils } from "../../libraries/SignatureUtils.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

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
     * @notice Validates a transaction against the specified policy
     * @param account The account executing the transaction
     * @param to Transaction destination address
     * @param value Transaction value
     * @param data Transaction data
     * @param salt User-provided salt for nonce computation
     * @param policyId The policy ID to validate against
     * @param signatures Signatures for approval verification
     */
    function validateTransactionApproval(
        address account,
        address to,
        uint256 value,
        bytes memory data,
        uint256 salt,
        uint256 policyId,
        bytes memory signatures
    )
        internal
        view
    {
        LibOrganizationPolicyStorage.Layout storage policyStorage = LibOrganizationPolicyStorage.layout();

        // Validate that policy exists
        if (!policyStorage.policyExists[policyId]) {
            revert PolicyNotFound(policyId);
        }

        // Look up policy directly
        Policies.Policy memory policy = policyStorage.policies[policyId];

        // Validate that policy applies to transaction
        // Note: msg.sender is the guardian who called the Organization
        if (!LibOrganizationPolicy.doesPolicyApplyToTransaction(policy, account, to, value, data, msg.sender)) {
            revert PolicyDoesNotApply(policyId);
        }

        // Case: Policy is a manual approval policy
        // Check if the transaction has enough valid approvals
        if (policy.policyType == Policies.PolicyType.RequireManualApproval) {
            // Get transaction hash for signature verification
            bytes32 txHash = _getTransactionHash(account, to, value, data, salt, policyId, true);
            uint256 requiredApprovals = LibOrganizationPolicy.getRequiredApprovals(policy);
            uint256 validApprovals = _getValidApprovals(policy, signatures, txHash);

            // Case: Transaction does not have enough valid approvals
            if (validApprovals < requiredApprovals) {
                revert InsufficientApprovals(requiredApprovals, validApprovals);
            }
            return;
        }

        // Case: Policy is AutoApprove
        // Require a single signature from any organization member
        if (policy.policyType == Policies.PolicyType.AutoApprove) {
            bytes32 txHash = _getTransactionHash(account, to, value, data, salt, policyId, true);

            // Check if we have a valid signature from any organization member
            if (!_hasValidMemberSignature(signatures, txHash)) {
                revert TransactionRejectedByPolicy(
                    "AutoApprove policy requires a signature from an organization member"
                );
            }
            return;
        }
    }

    /**
     * @notice Validates that the caller is authorized to reject the given transaction
     * @param account The account for which the transaction is being rejected
     * @param to Transaction destination address
     * @param value Transaction value
     * @param data Transaction data
     * @param salt User-provided salt for nonce computation
     * @param policyId The policy ID to validate against
     * @param signatures Signatures for rejection verification
     */
    function validateTransactionRejection(
        address account,
        address to,
        uint256 value,
        bytes memory data,
        uint256 salt,
        uint256 policyId,
        bytes memory signatures
    )
        internal
        view
    {
        LibOrganizationPolicyStorage.Layout storage policyStorage = LibOrganizationPolicyStorage.layout();

        // Validate that policy exists
        if (!policyStorage.policyExists[policyId]) {
            revert PolicyNotFound(policyId);
        }

        // Look up policy directly
        Policies.Policy memory policy = policyStorage.policies[policyId];

        // Validate that policy applies to transaction
        if (!LibOrganizationPolicy.doesPolicyApplyToTransaction(policy, account, to, value, data, msg.sender)) {
            revert PolicyDoesNotApply(policyId);
        }

        // Case: Policy is an automatic approval policy
        // Only valid transaction initiators (as defined by policy) can reject it
        if (policy.policyType == Policies.PolicyType.AutoApprove) {
            // Get transaction hash for signature verification (isApproval = false for rejection)
            bytes32 txHash = _getTransactionHash(account, to, value, data, salt, policyId, false);

            // Check if we have at least one valid signature from an authorized initiator
            if (_hasValidInitiatorSignature(policy, signatures, txHash)) {
                return;
            } else {
                revert TransactionRejectedByPolicy("No valid signature from authorized transaction initiator");
            }
        }

        // Case: Policy is a manual approval policy
        // Check if the caller has sufficient rejection authority
        if (policy.policyType == Policies.PolicyType.RequireManualApproval) {
            // Get transaction hash for signature verification (isApproval = false for rejection)
            bytes32 txHash = _getTransactionHash(account, to, value, data, salt, policyId, false);
            uint256 requiredApprovals = LibOrganizationPolicy.getRequiredApprovals(policy);
            uint256 validApprovals = _getValidApprovals(policy, signatures, txHash);

            // Case: Transaction does not have enough valid rejections
            if (validApprovals < requiredApprovals) {
                revert InsufficientApprovals(requiredApprovals, validApprovals);
            }
            return;
        }
    }

    /**
     * @notice Verifies signatures and returns the number of valid approvals
     * @param policy The policy requiring approval
     * @param signatures The signatures to verify
     * @param txHash The hash of the transaction
     * @return The number of valid approvals
     */
    function _getValidApprovals(
        Policies.Policy memory policy,
        bytes memory signatures,
        bytes32 txHash
    )
        private
        view
        returns (uint8)
    {
        // Case: No signatures provided
        if (signatures.length == 0) return 0;

        // Each signature is 65 bytes (r: 32, s: 32, v: 1)
        uint8 signatureCount = uint8(signatures.length / 65);
        uint8 validApprovals = 0;

        // Track last signer to prevent duplicates (similar to Safe contracts)
        address lastSigner = address(0);

        // Iterate over signatures to count valid approvals
        for (uint8 i = 0; i < signatureCount; ++i) {
            bytes memory signature = SignatureUtils.extractSignature(signatures, i);

            // Extract signer address from signature
            address signer = LibOrganizationSignatures.extractSigner(signature);

            // Skip if signer is invalid
            if (signer == address(0)) continue;

            // Check for duplicate signers - signers must be unique and in ascending order
            if (signer <= lastSigner) continue;

            // Update last signer for next iteration
            lastSigner = signer;

            // Verify the signature using ERC-1271
            if (!SignatureChecker.isValidSignatureNow(signer, txHash, signature)) {
                continue;
            }

            // Check if signer is authorized based on policy
            if (LibOrganizationPolicy.isSignerAuthorizedForPolicy(policy, signer)) {
                ++validApprovals;
            }
        }

        return validApprovals;
    }

    /**
     * @notice Checks if there is at least one valid signature from an authorized transaction initiator
     * @param policy The policy to check against
     * @param signatures The signatures to verify
     * @param txHash The hash of the transaction
     * @return True if there is at least one valid signature from an authorized initiator
     */
    function _hasValidInitiatorSignature(
        Policies.Policy memory policy,
        bytes memory signatures,
        bytes32 txHash
    )
        private
        view
        returns (bool)
    {
        // Case: No signatures provided
        if (signatures.length == 0) return false;

        // Each signature is 65 bytes (r: 32, s: 32, v: 1)
        uint8 signatureCount = uint8(signatures.length / 65);

        // Iterate over signatures to find at least one valid initiator signature
        for (uint8 i = 0; i < signatureCount; ++i) {
            bytes memory signature = SignatureUtils.extractSignature(signatures, i);

            // Extract signer address from signature
            address signer = LibOrganizationSignatures.extractSigner(signature);

            // Skip if signer is invalid
            if (signer == address(0)) continue;

            // Verify the signature using ERC-1271
            if (!SignatureChecker.isValidSignatureNow(signer, txHash, signature)) {
                continue;
            }

            // Check if signer is authorized as a transaction initiator based on policy
            if (LibOrganizationPolicy.isSignerAuthorizedAsInitiator(policy, signer)) {
                return true;
            }
        }

        return false;
    }

    /**
     * @notice Checks if there is a valid signature from any organization member
     * @param signatures The signature to verify (expected to be exactly 65 bytes)
     * @param txHash The hash of the transaction
     * @return True if there is a valid signature from any organization member
     */
    function _hasValidMemberSignature(bytes memory signatures, bytes32 txHash) private view returns (bool) {
        // Case: No signature provided or incorrect length (must be exactly 65 bytes)
        if (signatures.length != 65) return false;

        // Extract signer address from signature
        address signer = LibOrganizationSignatures.extractSigner(signatures);

        // Case: Signer is invalid
        if (signer == address(0)) return false;

        // Verify the signature using ERC-1271
        if (!SignatureChecker.isValidSignatureNow(signer, txHash, signatures)) {
            return false;
        }

        // Check if signer is a member of the organization
        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();
        uint8 memberId = membersLayout.addressToMemberId[signer];
        return memberId != 0;
    }

    /**
     * @notice Creates a hash of the transaction for signature verification using EIP-712 typed data
     * @param account The account executing the transaction
     * @param to The destination address of the transaction
     * @param value The value of the transaction
     * @param data The data of the transaction
     * @param salt The user-provided salt for nonce computation
     * @param policyId The policy ID governing this transaction
     * @param isApproval Whether the signature is for an approval or a rejection
     * @return The hash of the transaction formatted for ERC-1271 signature verification
     */
    function _getTransactionHash(
        address account,
        address to,
        uint256 value,
        bytes memory data,
        uint256 salt,
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
                    "ExecuteAccountTransaction(address organization,address account,address to,uint256 value,bytes data,uint256 salt,uint256 policyId,bool isApproval,uint256 chainId)"
                ),
                address(this),
                account,
                to,
                value,
                keccak256(data),
                salt,
                policyId,
                isApproval,
                block.chainid
            )
        );

        // Return EIP-712 compatible hash for ERC-1271 signature verification
        return MessageHashUtils.toTypedDataHash(
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256("OnchainCustodyOrganization"),
                    keccak256("1"),
                    block.chainid,
                    address(this)
                )
            ),
            structHash
        );
    }
}
