// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationGroups} from "interfaces/organization/IOrganizationGroups.sol";
import {IOrganizationMembers} from "interfaces/organization/IOrganizationMembers.sol";
import {IOrganizationPolicy} from "interfaces/organization/IOrganizationPolicy.sol";
import {SignatureUtils} from "libraries/SignatureUtils.sol";
import {LibOrganizationGroups} from "organization/libraries/LibOrganizationGroups.sol";
import {LibOrganizationMembers} from "organization/libraries/LibOrganizationMembers.sol";
import {ApproverType, Policy} from "types/PolicyTypes.sol";

/**
 * @title Lib Policy Approval
 * @dev Library for policy approval and signature validation.
 *      Handles counting valid approvals from signatures and verifying signer authorization.
 *      Uses direct mapping lookups for membership verification.
 * @author Den Technologies Inc
 */
library LibPolicyApproval {
    /**
     * @dev Checks if there are enough valid approvals from signatures (using mapping lookups).
     *      Signatures must be ordered by signer address (ascending) to prevent duplicates.
     *      Each signature is verified against the message hash and checked for authorization.
     *      Supports both EOA (ECDSA) and ERC-1271 (smart contract) signatures.
     *      Iterates using while(offset < signatures.length) — no proof arrays needed.
     *      Reverts if any signer is not a member, not in the required group, or signers not in order.
     * @param policy The policy to check against
     * @param signatures The concatenated reviewer signatures (variable length, hybrid format)
     * @param messageHash The message hash that was signed
     * @return True if there are enough valid approvals, false otherwise
     */
    function areApprovalsValid(Policy memory policy, bytes memory signatures, bytes32 messageHash)
        internal
        view
        returns (bool)
    {
        // Case: No signatures provided
        if (signatures.length == 0) return false;

        // For Group approver type, verify group existence once before the loop for gas efficiency
        if (policy.config.approval.approverType == ApproverType.Group) {
            uint256 approverGroupId = policy.config.approval.approverGroupId;
            if (!LibOrganizationGroups.isGroup(approverGroupId)) {
                revert IOrganizationGroups.GroupDoesNotExist(approverGroupId);
            }
        }

        uint256 requiredApprovals = getRequiredApprovals(policy);
        uint8 validApprovals = 0;
        address lastSigner = address(0);
        uint256 offset = 0;

        // Iterate over all signatures in the packed bytes
        while (offset < signatures.length) {
            // Recover signer at current offset (handles both EOA and ERC-1271)
            // Reverts if signature is malformed
            (address signer, uint256 nextOffset) =
                SignatureUtils.recoverSignerAtOffsetOrRevert(signatures, offset, messageHash);

            offset = nextOffset;

            // Case: Duplicate or out-of-order signers - signers must be unique and in ascending order
            if (signer <= lastSigner) {
                revert IOrganizationPolicy.DuplicateOrOutOfOrderSigner(signer, lastSigner);
            }
            lastSigner = signer;

            // Check if signer is authorized based on policy (with mapping lookups)
            _validateAndCountApprovalOrRevert({policy: policy, signerAddress: signer});

            ++validApprovals;

            // Case: Early exit if we have enough approvals
            if (validApprovals >= requiredApprovals) {
                return true;
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
     * @dev Validates that a signer is authorized to approve for a policy and reverts if not.
     *      For Member approver type, the signer must be the specified member address.
     *      For Group approver type, the signer must be a member of the specified group.
     *      All signers must be members of the organization.
     *      NOTE: Group existence must be verified by the caller before calling this function.
     * @param policy The policy to check against
     * @param signerAddress The address of the signer
     */
    function _validateAndCountApprovalOrRevert(Policy memory policy, address signerAddress) private view {
        // Case: Signer is not a member of the organization
        if (!LibOrganizationMembers.isMember(signerAddress)) {
            revert IOrganizationMembers.MemberDoesNotExist(signerAddress);
        }

        ApproverType approverType = policy.config.approval.approverType;

        // Case: Policy requires approval from a specific member
        if (approverType == ApproverType.Member) {
            if (signerAddress != policy.config.approval.approverMember) {
                revert IOrganizationMembers.MemberDoesNotExist(signerAddress);
            }
            return;
        }

        // Case: Policy requires approval from any member of a specific group
        if (approverType == ApproverType.Group) {
            uint256 approverGroupId = policy.config.approval.approverGroupId;

            // Verify member is in the group (group existence verified by caller)
            if (!LibOrganizationGroups.isGroupMember(approverGroupId, signerAddress)) {
                revert IOrganizationPolicy.ApproverSignerIsNotGroupMember(signerAddress, approverGroupId);
            }
        }
    }
}
