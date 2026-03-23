// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {SignatureUtils} from "libraries/SignatureUtils.sol";
import {LibOrganizationGroups} from "organization/libraries/LibOrganizationGroups.sol";
import {LibOrganizationMembers} from "organization/libraries/LibOrganizationMembers.sol";
import {LibOrganizationGroupsStorage} from "organization/libraries/storage/LibOrganizationGroupsStorage.sol";
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
     *      Fails closed by returning false for malformed signatures, unauthorized signers,
     *      invalid signer ordering, missing groups, or invalid policy config.
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

        // Case: Group approver policies require an existing group
        if (policy.config.approval.approverType == ApproverType.Group) {
            uint256 approverGroupId = policy.config.approval.approverGroupId;
            if (!LibOrganizationGroups.isGroup(approverGroupId)) {
                return false;
            }
        }

        uint256 requiredApprovals = getRequiredApprovals(policy);

        // Case: Invalid config that resolves to zero required approvals fails closed
        if (requiredApprovals == 0) return false;

        uint8 validApprovals = 0;
        address lastSigner = address(0);
        uint256 offset = 0;

        // Iterate over all signatures in the packed bytes
        while (offset < signatures.length) {
            // Recover signer at current offset (handles both EOA and ERC-1271)
            (bool recovered, address signer, uint256 nextOffset) =
                SignatureUtils.tryRecoverSignerAtOffset(signatures, offset, messageHash);
            if (!recovered) return false;

            offset = nextOffset;

            // Case: Duplicate or out-of-order signers - signers must be unique and in ascending order
            if (signer <= lastSigner) {
                return false;
            }
            lastSigner = signer;

            // Case: Signer is not authorized for this policy
            if (!_isSignerAuthorizedForPolicy({policy: policy, signerAddress: signer})) {
                return false;
            }

            ++validApprovals;

            // Case: Early exit if we have enough approvals
            if (validApprovals >= requiredApprovals) {
                return true;
            }
        }

        return false;
    }

    /**
     * @dev Checks if a signer is authorized to approve for a policy.
     *      For Member approver type, the signer must be the specified member address.
     *      For Group approver type, the signer must be a member of the specified group.
     *      All signers must be members of the organization.
     *      NOTE: Group existence must be verified by the caller before calling this function.
     *      For Group approver type, this function reads the raw isGroupMember storage mapping
     *      directly (after confirming organization membership and group existence in the caller).
     *      Group membership entries persist across member removal/re-addition cycles by design,
     *      so a member who was previously assigned to a group, removed from the organization,
     *      and later re-added will be authorized for group-based policy approval without
     *      requiring explicit group reassignment. This is intentional.
     * @param policy The policy to check against
     * @param signerAddress The address of the signer
     * @return True if the signer is authorized, false otherwise
     */
    function _isSignerAuthorizedForPolicy(Policy memory policy, address signerAddress) internal view returns (bool) {
        // Case: Signer is not a member of the organization
        if (!LibOrganizationMembers.isMember(signerAddress)) return false;

        // Case: Policy requires approval from a specific member
        if (policy.config.approval.approverType == ApproverType.Member) {
            return signerAddress == policy.config.approval.approverMember;
        }

        // Case: Policy requires approval from any member of a specific group
        if (policy.config.approval.approverType == ApproverType.Group) {
            return
                LibOrganizationGroupsStorage.layout()
                .isGroupMember[policy.config.approval.approverGroupId][signerAddress];
        }

        return false;
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
        if (policy.config.approval.approverType == ApproverType.Group) {
            return policy.config.approval.approvalThreshold;
        }

        // Case: Unknown approver-type enum values fail closed.
        return type(uint256).max;
    }
}
