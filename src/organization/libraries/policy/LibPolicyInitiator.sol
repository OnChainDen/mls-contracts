// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationPolicy} from "interfaces/organization/IOrganizationPolicy.sol";
import {LibOrganizationGroups} from "organization/libraries/LibOrganizationGroups.sol";
import {LibOrganizationMembers} from "organization/libraries/LibOrganizationMembers.sol";
import {ApproverType, Policy} from "types/PolicyTypes.sol";

/**
 * @title Lib Policy Initiator
 * @dev Library for validating transaction initiator authorization.
 *      Handles checking if an initiator is authorized by a policy.
 *      Uses direct mapping lookups for membership verification.
 * @author Den Technologies Inc
 */
library LibPolicyInitiator {
    /**
     * @dev Checks if the initiator is authorized by the policy.
     *      If anyInitiator is true, always returns true.
     *      Otherwise, verifies the initiator is a member and matches policy requirements.
     *      Uses direct mapping lookups for membership and group membership.
     * @param policy The policy to check against
     * @param initiatorAddress The address of the transaction initiator
     * @param initiatorGroupId The group ID for group-based initiator verification
     * @return True if the initiator is authorized, false otherwise
     */
    function isInitiatorAuthorized(Policy memory policy, address initiatorAddress, uint256 initiatorGroupId)
        internal
        view
        returns (bool)
    {
        // Case: The policy matches transactions with any initiator
        if (policy.config.initiator.anyInitiator) return true;

        // First, verify the initiator is a member of the organization
        if (!LibOrganizationMembers.isMember(initiatorAddress)) {
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
            if (initiatorGroupId != policy.config.initiator.initiatorGroupId) {
                return false;
            }

            // Verify the group exists
            if (!LibOrganizationGroups.isGroup(initiatorGroupId)) {
                revert IOrganizationPolicy.InitiatorGroupDoesNotExist(initiatorGroupId);
            }

            // Verify the initiator is a member of the group
            return LibOrganizationGroups.isGroupMember(initiatorGroupId, initiatorAddress);
        }

        // Case: The policy does not match this transaction
        return false;
    }
}
