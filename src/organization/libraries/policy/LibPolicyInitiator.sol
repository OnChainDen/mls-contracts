// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {LibOrganizationGroups} from "organization/libraries/LibOrganizationGroups.sol";
import {LibOrganizationMembers} from "organization/libraries/LibOrganizationMembers.sol";
import {ApproverType, InitiatorProofs, Policy} from "types/PolicyTypes.sol";

/**
 * @title Lib Policy Initiator
 * @dev Library for validating transaction initiator authorization.
 *      Handles checking if an initiator is authorized by a policy.
 *      Uses Merkle proofs for membership verification.
 * @author Den Technologies Inc
 */
library LibPolicyInitiator {
    /**
     * @dev Checks if the initiator is authorized by the policy.
     *      If anyInitiator is true, always returns true.
     *      Otherwise, verifies the initiator is a member and matches policy requirements.
     *      Uses Merkle proofs for membership verification.
     * @param policy The policy to check against
     * @param initiatorAddress The address of the transaction initiator
     * @param initiatorProofs The proofs for initiator membership verification
     * @return True if the initiator is authorized, false otherwise
     */
    function isInitiatorAuthorized(
        Policy memory policy,
        address initiatorAddress,
        InitiatorProofs memory initiatorProofs
    ) internal view returns (bool) {
        // Case: The policy matches transactions with any initiator
        if (policy.config.initiator.anyInitiator) return true;

        // First, verify the initiator is a member of the organization
        if (!LibOrganizationMembers.isMemberInOrg(initiatorAddress, initiatorProofs.initiatorInOrgMembersTreeProof)) {
            return false;
        }

        ApproverType initType = policy.config.initiator.initiatorType;

        // Case: The policy matches transactions made by a specific individual
        if (initType == ApproverType.Member) {
            // Check if the initiator is the specified member address
            return initiatorAddress == policy.config.initiator.initiatorMember;
        }

        // Case: The policy matches transactions made by any individual from a specific group
        if (initType == ApproverType.Group) {
            // Check the group ID matches the policy's initiator group ID
            if (initiatorProofs.group.groupId != policy.config.initiator.initiatorGroupId) {
                return false;
            }

            // Verify the group exists and the initiator is in that group
            return LibOrganizationGroups.isMemberInGroupAndGroupInOrg(
                initiatorAddress,
                initiatorProofs.group,
                initiatorProofs.groupInOrgGroupsTreeProof,
                initiatorProofs.memberInGroupProof
            );
        }

        // Case: The policy does not match this transaction
        return false;
    }
}
