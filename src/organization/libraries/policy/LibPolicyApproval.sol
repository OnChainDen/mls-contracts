// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Policies} from "../../../libraries/Policies.sol";
import {SignatureUtils} from "../../../libraries/SignatureUtils.sol";
import {LibOrganizationGroups} from "../LibOrganizationGroups.sol";
import {LibOrganizationMembers} from "../LibOrganizationMembers.sol";
import {LibOrganizationSignatures} from "../LibOrganizationSignatures.sol";

import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/**
 * @title Lib Policy Approval
 * @notice Library for policy approval and signature validation
 * @dev Handles counting valid approvals from signatures and verifying signer authorization.
 *      Uses Merkle proofs for membership verification.
 * @author Den Technologies Inc
 */
library LibPolicyApproval {
    /**
     * @notice Thrown when member proofs array length doesn't match signature count
     * @param expected The expected number of member proofs (signature count)
     * @param actual The actual number of member proofs provided
     */
    error MemberProofsLengthMismatch(uint256 expected, uint256 actual);

    /**
     * @notice Thrown when member-in-group proofs array length doesn't match signature count
     * @param expected The expected number of member-in-group proofs (signature count)
     * @param actual The actual number of member-in-group proofs provided
     */
    error MemberInGroupProofsLengthMismatch(uint256 expected, uint256 actual);

    /**
     * @notice Counts valid approvals from a set of signatures (using Merkle proofs)
     * @dev Signatures must be ordered by signer address (ascending) to prevent duplicates.
     *      Each signature is verified against the message hash and checked for authorization.
     *      Optimized to cache storage reads and verify group existence once before the loop.
     * @param policy The policy to check against
     * @param signatures The concatenated signatures (65 bytes each)
     * @param messageHash The message hash that was signed
     * @param approverProofs The proofs for approver membership verification
     * @return The number of valid approvals
     */
    function getValidApprovals(
        Policies.Policy memory policy,
        bytes memory signatures,
        bytes32 messageHash,
        Policies.ApproverProofs memory approverProofs
    ) internal view returns (uint8) {
        // Case: No signatures provided
        if (signatures.length == 0) return 0;

        // Each signature is 65 bytes (r: 32, s: 32, v: 1)
        uint8 signatureCount = uint8(signatures.length / SignatureUtils.SIGNATURE_LENGTH);

        // Validate approver proofs lengths
        _validateApproverProofsOrRevert(policy, approverProofs, signatureCount);

        // Cache membersRoot to avoid repeated storage reads in the loop
        bytes32 membersRoot = LibOrganizationMembers.getMembersRoot();

        // For Group approver type, verify group existence before the loop
        if (policy.config.approval.approverType == Policies.ApproverType.Group) {
            if (!LibOrganizationGroups.isGroupInOrg(approverProofs.group, approverProofs.groupInOrgGroupsTreeProof)) {
                return 0;
            }
        }

        uint8 validApprovals = 0;

        // Track last signer to prevent duplicates (similar to Safe contracts)
        address lastSigner = address(0);

        // Iterate over signatures to count valid approvals
        for (uint8 i = 0; i < signatureCount; ++i) {
            bytes memory signature = SignatureUtils.extractSignature(signatures, i);

            // Extract signer address from signature
            address signer = LibOrganizationSignatures.extractSignerAddress(signature);

            // Skip if signer is invalid
            if (signer == address(0)) continue;

            // Check for duplicate signers - signers must be unique and in ascending order
            if (signer <= lastSigner) continue;

            // Update last signer for next iteration
            lastSigner = signer;

            // Verify the signature using ERC-1271
            if (!SignatureChecker.isValidSignatureNow(signer, messageHash, signature)) {
                continue;
            }

            // Get the proofs for this signer
            bytes32[] memory memberProof = approverProofs.approverInOrgMembersTreeProofs[i];
            bytes32[] memory memberInGroupProof = approverProofs.memberInGroupProofs[i];

            // Check if signer is authorized based on policy (with Merkle proofs)
            // Note: Group existence already verified above, membersRoot passed to avoid storage reads
            if (
                isSignerAuthorizedForPolicy({
                    policy: policy,
                    signerAddress: signer,
                    membersRoot: membersRoot,
                    memberProof: memberProof,
                    group: approverProofs.group,
                    memberInGroupProof: memberInGroupProof
                })
            ) {
                ++validApprovals;
            }
        }

        return validApprovals;
    }

    /**
     * @notice Gets the number of required approvals for a policy
     * @dev For Member approver type, always returns 1.
     *      For Group approver type, returns the approval threshold.
     * @param policy The policy to check
     * @return The number of required approvals
     */
    function getRequiredApprovals(Policies.Policy memory policy) internal pure returns (uint256) {
        // Case: Policy requires a single approval from a member
        if (policy.config.approval.approverType == Policies.ApproverType.Member) {
            return 1;
        }

        // Case: Policy requires a threshold number of approvals from any individual in a group
        return policy.config.approval.approvalThreshold;
    }

    /**
     * @notice Checks if a signer is authorized to approve for a policy (using Merkle proofs)
     * @dev For Member approver type, the signer must be the specified member address.
     *      For Group approver type, the signer must be in the specified group.
     *      NOTE: Group existence must be verified by the caller before calling this function.
     *      This function only verifies member-in-org and member-in-group to avoid redundant checks.
     * @param policy The policy to check against
     * @param signerAddress The address of the signer
     * @param membersRoot The organization's members merkle root (cached by caller to avoid repeated storage reads)
     * @param memberProof Proof that the signer is a member of the organization
     * @param group The approver group data (if applicable)
     * @param memberInGroupProof Proof that the signer is in the approver group (if applicable)
     * @return True if the signer is authorized, false otherwise
     */
    function isSignerAuthorizedForPolicy(
        Policies.Policy memory policy,
        address signerAddress,
        bytes32 membersRoot,
        bytes32[] memory memberProof,
        Policies.GroupData memory group,
        bytes32[] memory memberInGroupProof
    ) internal pure returns (bool) {
        // First verify the signer is a member of the organization (using cached root)
        if (!LibOrganizationMembers.isMemberInTree(signerAddress, membersRoot, memberProof)) {
            return false;
        }

        Policies.ApproverType approverType = policy.config.approval.approverType;

        // Case: Policy requires approval from a specific member
        if (approverType == Policies.ApproverType.Member) {
            return signerAddress == policy.config.approval.approverMember;
        }

        // Case: Policy requires approval from any member of a specific group
        if (approverType == Policies.ApproverType.Group) {
            // Check the group ID matches the policy's approver group
            if (group.groupId != policy.config.approval.approverGroupId) {
                return false;
            }

            // Verify member is in the group (group existence and proofs length verified by caller)
            return LibOrganizationGroups.isMemberInGroup(signerAddress, group.groupMembersRoot, memberInGroupProof);
        }

        return false;
    }

    /**
     * @notice Validates that approver proofs have correct lengths
     * @dev Reverts if proof arrays don't match signature count
     * @param policy The policy to check against
     * @param approverProofs The proofs for approver membership verification
     * @param signatureCount The number of signatures provided
     */
    function _validateApproverProofsOrRevert(
        Policies.Policy memory policy,
        Policies.ApproverProofs memory approverProofs,
        uint8 signatureCount
    ) private pure {
        if (approverProofs.approverInOrgMembersTreeProofs.length != signatureCount) {
            revert MemberProofsLengthMismatch(signatureCount, approverProofs.approverInOrgMembersTreeProofs.length);
        }

        if (policy.config.approval.approverType == Policies.ApproverType.Group) {
            if (approverProofs.memberInGroupProofs.length != signatureCount) {
                revert MemberInGroupProofsLengthMismatch(signatureCount, approverProofs.memberInGroupProofs.length);
            }
        }
    }
}
