// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationPolicy} from "interfaces/organization/IOrganizationPolicy.sol";
import {SignatureUtils} from "libraries/SignatureUtils.sol";
import {LibOrganizationGroups} from "organization/libraries/LibOrganizationGroups.sol";
import {LibOrganizationMembers} from "organization/libraries/LibOrganizationMembers.sol";
import {ApproverProofs, ApproverType, GroupData, Policy} from "types/PolicyTypes.sol";

/**
 * @title Lib Policy Approval
 * @dev Library for policy approval and signature validation.
 *      Handles counting valid approvals from signatures and verifying signer authorization.
 *      Uses Merkle proofs for membership verification.
 * @author Den Technologies Inc
 */
library LibPolicyApproval {
    /**
     * @dev Checks if there are enough valid approvals from signatures (using Merkle proofs).
     *      Signatures must be ordered by signer address (ascending) to prevent duplicates.
     *      Each signature is verified against the message hash and checked for authorization.
     *      Supports both EOA (ECDSA) and ERC-1271 (smart contract) signatures.
     * @param policy The policy to check against
     * @param signatures The concatenated signatures (variable length, hybrid format)
     * @param messageHash The message hash that was signed
     * @param approverProofs The proofs for approver membership verification
     * @return True if there are enough valid approvals, false otherwise
     */
    function areApprovalsValid(
        Policy memory policy,
        bytes memory signatures,
        bytes32 messageHash,
        ApproverProofs memory approverProofs
    ) internal view returns (bool) {
        // Case: No signatures provided
        if (signatures.length == 0) return false;

        // Get the number of signatures from the approver proofs array length
        uint256 signatureCount = approverProofs.approverInOrgMembersTreeProofs.length;

        // Case: No approver proofs provided
        if (signatureCount == 0) return false;

        // Validate approver proofs lengths
        _validateApproverProofsOrRevert(policy, approverProofs, signatureCount);

        // Cache membersRoot to avoid repeated storage reads in the loop
        bytes32 membersRoot = LibOrganizationMembers.getMembersRoot();

        // For Group approver type, verify group existence before the loop
        if (policy.config.approval.approverType == ApproverType.Group) {
            if (!LibOrganizationGroups.isGroupInOrg(approverProofs.group, approverProofs.groupInOrgGroupsTreeProof)) {
                return false;
            }
        }

        uint256 requiredApprovals = getRequiredApprovals(policy);
        uint8 validApprovals = 0;
        address lastSigner = address(0);
        uint256 offset = 0;

        // Iterate over signatures to count valid approvals
        for (uint256 i = 0; i < signatureCount; ++i) {
            // Parse signature at current offset (handles both EOA and ERC-1271)
            SignatureUtils.ParsedSignature memory parsed =
                SignatureUtils.parseSignatureAtOffset(signatures, offset, messageHash);

            // Case: Signature parsing/validation failed or end of signatures
            if (!parsed.isValid) continue;

            address signer = parsed.signer;
            offset = parsed.nextOffset;

            // Case: Duplicate signers - signers must be unique and in ascending order
            if (signer <= lastSigner) continue;
            lastSigner = signer;

            // Get the proofs for this signer
            bytes32[] memory memberProof = approverProofs.approverInOrgMembersTreeProofs[i];
            bytes32[] memory memberInGroupProof = approverProofs.memberInGroupProofs[i];

            // Check if signer is authorized based on policy (with Merkle proofs)
            if (_isSignerAuthorizedForPolicy({
                    policy: policy,
                    signerAddress: signer,
                    membersRoot: membersRoot,
                    memberProof: memberProof,
                    group: approverProofs.group,
                    memberInGroupProof: memberInGroupProof
                })) {
                ++validApprovals;

                // Case: Early exit if we have enough approvals
                if (validApprovals >= requiredApprovals) {
                    return true;
                }
            }
        }

        return validApprovals >= requiredApprovals;
    }

    /**
     * @dev Gets the number of required approvals for a policy.
     *      For Member approver type, always returns 1.
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
     * @dev Checks if a signer is authorized to approve for a policy (using Merkle proofs).
     *      For Member approver type, the signer must be the specified member address.
     *      For Group approver type, the signer must be in the specified group.
     *      NOTE: Group existence must be verified by the caller before calling this function.
     * @param policy The policy to check against
     * @param signerAddress The address of the signer
     * @param membersRoot The organization's members merkle root (cached by caller)
     * @param memberProof Proof that the signer is a member of the organization
     * @param group The approver group data (if applicable)
     * @param memberInGroupProof Proof that the signer is in the approver group (if applicable)
     * @return True if the signer is authorized, false otherwise
     */
    function _isSignerAuthorizedForPolicy(
        Policy memory policy,
        address signerAddress,
        bytes32 membersRoot,
        bytes32[] memory memberProof,
        GroupData memory group,
        bytes32[] memory memberInGroupProof
    ) private pure returns (bool) {
        // Case: Signer is not a member of the organization
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
            // Case: Group ID doesn't match policy's approver group
            if (group.groupId != policy.config.approval.approverGroupId) {
                return false;
            }

            // Verify member is in the group (group existence verified by caller)
            return LibOrganizationGroups.isMemberInGroup(signerAddress, group.groupMembersRoot, memberInGroupProof);
        }

        return false;
    }

    /**
     * @dev Validates that approver proofs have correct lengths.
     *      Reverts if proof arrays don't match signature count.
     * @param policy The policy to check against
     * @param approverProofs The proofs for approver membership verification
     * @param signatureCount The number of signatures provided
     */
    function _validateApproverProofsOrRevert(
        Policy memory policy,
        ApproverProofs memory approverProofs,
        uint256 signatureCount
    ) private pure {
        if (approverProofs.approverInOrgMembersTreeProofs.length != signatureCount) {
            revert IOrganizationPolicy.MemberProofsLengthMismatch(
                signatureCount, approverProofs.approverInOrgMembersTreeProofs.length
            );
        }

        if (policy.config.approval.approverType == ApproverType.Group) {
            if (approverProofs.memberInGroupProofs.length != signatureCount) {
                revert IOrganizationPolicy.MemberInGroupProofsLengthMismatch(
                    signatureCount, approverProofs.memberInGroupProofs.length
                );
            }
        }
    }
}
