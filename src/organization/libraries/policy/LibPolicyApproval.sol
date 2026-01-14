// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IOrganizationPolicy} from "../../../interfaces/organization/IOrganizationPolicy.sol";
import {Policy, ApproverProofs, GroupData, ApproverType} from "../../../types/PolicyTypes.sol";
import {SignatureUtils} from "../../../libraries/SignatureUtils.sol";
import {LibOrganizationGroups} from "../LibOrganizationGroups.sol";
import {LibOrganizationMembers} from "../LibOrganizationMembers.sol";

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title Lib Policy Approval
 * @dev Library for policy approval and signature validation
 * @dev Handles counting valid approvals from signatures and verifying signer authorization.
 *      Uses Merkle proofs for membership verification.
 * @author Den Technologies Inc
 */
library LibPolicyApproval {

    /**
     * @dev Counts valid approvals from a set of signatures (using Merkle proofs)
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
        Policy memory policy,
        bytes memory signatures,
        bytes32 messageHash,
        ApproverProofs memory approverProofs
    ) internal view returns (uint8) {
        // Case: No signatures provided
        if (signatures.length == 0) return 0;

        uint8 signatureCount = SignatureUtils.getSignatureCount(signatures);

        // Validate approver proofs lengths
        _validateApproverProofsOrRevert(policy, approverProofs, signatureCount);

        // Cache membersRoot to avoid repeated storage reads in the loop
        bytes32 membersRoot = LibOrganizationMembers.getMembersRoot();

        // For Group approver type, verify group existence before the loop
        if (policy.config.approval.approverType == ApproverType.Group) {
            if (!LibOrganizationGroups.isGroupInOrg(approverProofs.group, approverProofs.groupInOrgGroupsTreeProof)) {
                return 0;
            }
        }

        uint8 validApprovals = 0;

        // Track last signer to prevent duplicates
        address lastSigner = address(0);

        // Iterate over signatures to count valid approvals
        for (uint8 i = 0; i < signatureCount; ++i) {
            bytes memory signature = SignatureUtils.extractSignature(signatures, i);

            // Recover signer address from signature (reverts on invalid signature)
            address signer = ECDSA.recover(messageHash, signature);

            // Check for duplicate signers - signers must be unique and in ascending order
            if (signer <= lastSigner) continue;

            // Update last signer for next iteration
            lastSigner = signer;

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
     * @dev Gets the number of required approvals for a policy
     * @dev For Member approver type, always returns 1.
     *      For Group approver type, returns the approval threshold.
     * @param policy The policy to check
     * @return The number of required approvals
     */
    function getRequiredApprovals(Policy memory policy) internal pure returns (uint256) {
        // Case: Policy requires a single approval from a member
        if (policy.config.approval.approverType == ApproverType.Member) {
            return 1;
        }

        // Case: Policy requires a threshold number of approvals from any individual in a group
        return policy.config.approval.approvalThreshold;
    }

    /**
     * @dev Checks if a signer is authorized to approve for a policy (using Merkle proofs)
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
        Policy memory policy,
        address signerAddress,
        bytes32 membersRoot,
        bytes32[] memory memberProof,
        GroupData memory group,
        bytes32[] memory memberInGroupProof
    ) internal pure returns (bool) {
        // First verify the signer is a member of the organization (using cached root)
        if (!LibOrganizationMembers.isMemberInTree(signerAddress, membersRoot, memberProof)) {
            return false;
        }

        ApproverType approverType = policy.config.approval.approverType;

        // Case: Policy requires approval from a specific member
        if (approverType == ApproverType.Member) {
            return signerAddress == policy.config.approval.approverMember;
        }

        // Case: Policy requires approval from any member of a specific group
        if (approverType == ApproverType.Group) {
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
     * @dev Validates that approver proofs have correct lengths
     * @dev Reverts if proof arrays don't match signature count
     * @param policy The policy to check against
     * @param approverProofs The proofs for approver membership verification
     * @param signatureCount The number of signatures provided
     */
    function _validateApproverProofsOrRevert(Policy memory policy, ApproverProofs memory approverProofs, uint8 signatureCount)
        private
        pure
    {
        if (approverProofs.approverInOrgMembersTreeProofs.length != signatureCount) {
            revert IOrganizationPolicy.MemberProofsLengthMismatch(signatureCount, approverProofs.approverInOrgMembersTreeProofs.length);
        }

        if (policy.config.approval.approverType == ApproverType.Group) {
            if (approverProofs.memberInGroupProofs.length != signatureCount) {
                revert IOrganizationPolicy.MemberInGroupProofsLengthMismatch(signatureCount, approverProofs.memberInGroupProofs.length);
            }
        }
    }
}
