// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { LibOrganizationPolicy } from "./LibOrganizationPolicy.sol";
import { LibOrganizationGuardian } from "./LibOrganizationGuardian.sol";
import { LibOrganizationSignatures } from "./LibOrganizationSignatures.sol";
import { LibOrganizationPolicyStorage } from "./storage/LibOrganizationPolicyStorage.sol";
import { Policies } from "../../libraries/Policies.sol";
import { SignatureUtils } from "../../libraries/SignatureUtils.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title Lib Organization Account Signature
 * @notice Library for validating ERC-1271 signatures through the Organization contract
 * @dev This library handles validation of signatures for Account contracts following ERC-1271
 * @author Den Technologies Inc
 */
library LibOrganizationAccountSignature {
    /// @notice ERC-1271 magic value returned when signature is valid
    bytes4 internal constant ERC1271_MAGIC_VALUE = 0x1626ba7e;

    /// @notice Value returned when signature is invalid
    bytes4 internal constant ERC1271_INVALID_VALUE = 0xffffffff;

    /**
     * @notice Validates an ERC-1271 signature for a given account
     * @dev The signature parameter is expected to be ABI-encoded as:
     *      (uint256 policyId, uint256 expirationTimestamp, bytes approverSignatures, bytes guardianSignature)
     *      The approverSignatures is structured as: [initiatorSignature (65 bytes)][reviewSignatures (N * 65 bytes)]
     *      The initiator signature is verified against the initiator hash.
     *      Review signatures are verified against a hash that includes the initiator signature.
     *      Note: Time-based limits are checked but NOT updated due to ERC-1271 view requirement.
     * @param account The account address on behalf of which the signature is being validated
     * @param hash The original hash that was signed
     * @param signature The encoded signature data containing policyId, expiration, approver signatures, and guardian
     * signature
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
        // Decode the signature data
        (uint256 policyId, uint256 expirationTimestamp, bytes memory approverSignatures, bytes memory guardianSignature)
        = abi.decode(signature, (uint256, uint256, bytes, bytes));

        // 0. Check if the signature has expired
        if (block.timestamp > expirationTimestamp) {
            return ERC1271_INVALID_VALUE;
        }

        // 1. Verify guardian signature
        if (!_verifyGuardianSignature(account, hash, policyId, expirationTimestamp, guardianSignature)) {
            return ERC1271_INVALID_VALUE;
        }

        // 2. Retrieve and verify policy
        LibOrganizationPolicyStorage.Layout storage policyStorage = LibOrganizationPolicyStorage.layout();

        // Check policy exists
        if (!policyStorage.policyExists[policyId]) {
            return ERC1271_INVALID_VALUE;
        }

        Policies.Policy memory policy = policyStorage.policies[policyId];

        // Check policy is for signatures
        if (policy.transactionType != Policies.TransactionType.Signatures) {
            return ERC1271_INVALID_VALUE;
        }

        // Check policy applies to this account
        if (!LibOrganizationPolicy.doesTransactionMatchPolicySourceAccounts(policy, account)) {
            return ERC1271_INVALID_VALUE;
        }

        // 3. Validate initiator signature
        // approverSignatures must contain at least the initiator signature (65 bytes)
        if (approverSignatures.length < 65) {
            return ERC1271_INVALID_VALUE;
        }

        // Extract initiator signature (first 65 bytes)
        bytes memory initiatorSignature = SignatureUtils.extractSignature(approverSignatures, 0);

        // Get the initiator hash that the initiator signs
        bytes32 initiatorHash = _getInitiatorSignatureHash(account, hash, policyId, expirationTimestamp);

        // Recover the initiator address from the signature
        address initiator = ECDSA.recover(initiatorHash, initiatorSignature);
        if (initiator == address(0)) {
            return ERC1271_INVALID_VALUE;
        }

        // Validate that the initiator is authorized by the policy
        if (!LibOrganizationPolicy.doesTransactionMatchPolicyInitiator(policy, initiator)) {
            return ERC1271_INVALID_VALUE;
        }

        // 4. Check time-based limits (view only - does not update usage)
        // Note: Due to ERC-1271 view requirement, we cannot update usage tracking for signatures
        if (!_checkTimeBasedLimit(policyId, policy, account, initiator)) {
            return ERC1271_INVALID_VALUE;
        }

        // 5. For AutoApprove policies, only the initiator signature is required (already validated)
        if (policy.policyType == Policies.PolicyType.AutoApprove) {
            return ERC1271_MAGIC_VALUE;
        }

        // 6. For manual approval policies, verify review signatures
        if (policy.policyType == Policies.PolicyType.RequireManualApproval) {
            uint256 requiredApprovals = LibOrganizationPolicy.getRequiredApprovals(policy);

            // Extract review signatures (everything after the first 65 bytes)
            bytes memory reviewSignatures = LibOrganizationSignatures.extractReviewSignatures(approverSignatures);

            // Get the review hash that includes the initiator signature
            bytes32 reviewHash =
                _getReviewSignatureHash(account, hash, policyId, expirationTimestamp, initiatorSignature);

            // Count valid review approvals
            uint256 validApprovals = LibOrganizationPolicy.getValidApprovals(policy, reviewSignatures, reviewHash);

            if (validApprovals >= requiredApprovals) {
                return ERC1271_MAGIC_VALUE;
            }
        }

        return ERC1271_INVALID_VALUE;
    }

    /**
     * @notice Checks time-based limits for a signature (view only, does not update)
     * @dev Due to ERC-1271 view requirement, we can only check but not update usage
     * @param policyId The policy ID
     * @param policy The policy to check against
     * @param account The account address
     * @param initiator The initiator address
     * @return True if within limit, false otherwise
     */
    function _checkTimeBasedLimit(
        uint256 policyId,
        Policies.Policy memory policy,
        address account,
        address initiator
    )
        private
        view
        returns (bool)
    {
        // Skip if no time-based limitation
        if (policy.limitation != Policies.PolicyLimitation.TimeInterval) {
            return true;
        }

        // Skip if time interval is not configured
        if (policy.timeIntervalHours == 0) {
            return true;
        }

        // Get current usage and check if adding 1 would exceed the limit
        // For signatures, usage is always 1 (count) and destination is not applicable
        uint256 currentUsage = LibOrganizationPolicy.getCurrentUsage(policyId, policy, account, address(0), initiator);

        // Check if adding 1 would exceed the limit
        // Note: This is a read-only check - usage is NOT updated
        return currentUsage + 1 <= policy.timeIntervalLimit;
    }

    /**
     * @notice Verifies the guardian signature
     * @param account The account address on behalf of which the signature is being validated
     * @param hash The original hash that was signed
     * @param policyId The policy ID being used
     * @param expirationTimestamp The timestamp after which the signature is no longer valid
     * @param guardianSignature The signature from the guardian
     * @return True if the guardian signature is valid, false otherwise
     */
    function _verifyGuardianSignature(
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
        address guardianAddress = LibOrganizationGuardian.guardian();

        // Construct the message that the guardian should have signed
        bytes32 guardianMessageHash = _getInitiatorSignatureHash(account, hash, policyId, expirationTimestamp);

        // Verify the guardian's signature
        return SignatureChecker.isValidSignatureNow(guardianAddress, guardianMessageHash, guardianSignature);
    }

    /**
     * @notice Creates the initiator hash for signature verification using EIP-712 typed data
     * @dev This is the hash that the initiator signs to start the signature flow
     * @param account The account address on behalf of which the signature is being validated
     * @param hash The original hash that was signed
     * @param policyId The policy ID being used
     * @param expirationTimestamp The timestamp after which the signature is no longer valid
     * @return The hash for initiator signature verification
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
        // Create EIP-712 structured data hash
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

        // Return EIP-712 compatible hash for signature verification
        return MessageHashUtils.toTypedDataHash(_getDomainSeparator(), structHash);
    }

    /**
     * @notice Creates the review hash for reviewer signature verification that includes the initiator's signature
     * @dev This hash binds reviewers to a specific initiation by including the initiator's signature
     * @param account The account address on behalf of which the signature is being validated
     * @param hash The original hash that was signed
     * @param policyId The policy ID being used
     * @param expirationTimestamp The timestamp after which the signature is no longer valid
     * @param initiatorSignature The initiator's signature that reviewers are approving
     * @return The hash for reviewer signature verification
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
        // Create EIP-712 structured data hash that includes the initiator signature hash
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
