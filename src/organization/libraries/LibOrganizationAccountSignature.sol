// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { LibOrganizationPolicy } from "./LibOrganizationPolicy.sol";
import { LibOrganizationGuardian } from "./LibOrganizationGuardian.sol";
import { LibOrganizationPolicyStorage } from "./storage/LibOrganizationPolicyStorage.sol";
import { Policies } from "../../libraries/Policies.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

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
     *      (uint256 policyId, bytes approverSignatures, bytes guardianSignature)
     * @param account The account address on behalf of which the signature is being validated
     * @param hash The original hash that was signed
     * @param signature The encoded signature data containing policyId, approver signatures, and guardian signature
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
        (uint256 policyId, bytes memory approverSignatures, bytes memory guardianSignature) =
            abi.decode(signature, (uint256, bytes, bytes));

        // 1. Verify guardian signature
        if (!_verifyGuardianSignature(account, hash, policyId, guardianSignature)) {
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

        // 3. Construct replay-safe hash
        bytes32 safeHash = _getSignatureHash(account, hash, policyId);

        // 4. Handle based on policy type
        if (policy.policyType == Policies.PolicyType.AutoApprove) {
            // Auto-approve policies don't require approver signatures
            return ERC1271_MAGIC_VALUE;
        }

        // 5. For manual approval policies, verify approver signatures
        if (policy.policyType == Policies.PolicyType.RequireManualApproval) {
            uint256 requiredApprovals = LibOrganizationPolicy.getRequiredApprovals(policy);
            uint256 validApprovals = LibOrganizationPolicy.getValidApprovals(policy, approverSignatures, safeHash);

            if (validApprovals >= requiredApprovals) {
                return ERC1271_MAGIC_VALUE;
            }
        }

        return ERC1271_INVALID_VALUE;
    }

    /**
     * @notice Verifies the guardian signature
     * @param account The account address on behalf of which the signature is being validated
     * @param hash The original hash that was signed
     * @param policyId The policy ID being used
     * @param guardianSignature The signature from the guardian
     * @return True if the guardian signature is valid, false otherwise
     */
    function _verifyGuardianSignature(
        address account,
        bytes32 hash,
        uint256 policyId,
        bytes memory guardianSignature
    )
        private
        view
        returns (bool)
    {
        address guardianAddress = LibOrganizationGuardian.guardian();

        // Construct the message that the guardian should have signed
        bytes32 guardianMessageHash = _getSignatureHash(account, hash, policyId);

        // Verify the guardian's signature
        return SignatureChecker.isValidSignatureNow(guardianAddress, guardianMessageHash, guardianSignature);
    }

    /**
     * @notice Creates a replay-safe hash for signature verification
     * @dev Includes the account, original hash, policy ID, chain ID, and organization address
     *      to prevent replay attacks across different contexts
     * @param account The account address on behalf of which the signature is being validated
     * @param hash The original hash that was signed
     * @param policyId The policy ID being used
     * @return The replay-safe hash formatted for ERC-1271 signature verification
     */
    function _getSignatureHash(address account, bytes32 hash, uint256 policyId) private view returns (bytes32) {
        // Create EIP-712 structured data hash
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "ValidateSignature(address organization,address account,bytes32 hash,uint256 policyId,uint256 chainId)"
                ),
                address(this),
                account,
                hash,
                policyId,
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
