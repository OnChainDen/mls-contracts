// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationGroups} from "interfaces/organization/IOrganizationGroups.sol";
import {LibOrganizationGroupsStorage} from "organization/libraries/storage/LibOrganizationGroupsStorage.sol";
import {GroupModification} from "types/CommonTypes.sol";

/**
 * @title Lib Organization Groups
 * @dev Library for mapping-based group operations for Organization contracts.
 *      Group existence and group membership are stored in mappings for O(1) lookups.
 *      Group IDs are not reusable after deletion -- isGroupMember entries persist as ghost data.
 *      The wasGroupDeleted mapping tracks deleted group IDs to prevent recreation.
 * @author Den Technologies Inc
 */
library LibOrganizationGroups {
    /**
     * @dev Creates, modifies, or deletes groups in the organization.
     *      When deleteGroup is true, the group is deleted and membersToAdd/membersToRemove must be empty.
     *      When deleteGroup is false and the groupId doesn't exist yet, the group is implicitly created.
     *      Adding a duplicate group member is a no-op. Removing a non-existent group member reverts.
     *      Group IDs are not reusable after deletion.
     * @param modifications Array of group modifications to apply
     */
    function modifyGroups(GroupModification[] calldata modifications) public {
        LibOrganizationGroupsStorage.Layout storage groupsLayout = LibOrganizationGroupsStorage.layout();

        for (uint256 i = 0; i < modifications.length; ++i) {
            GroupModification calldata mod = modifications[i];
            uint256 groupId = mod.groupId;

            if (mod.deleteGroup) {
                _deleteGroup(groupsLayout, groupId, mod);
            } else {
                _createOrModifyGroup(groupsLayout, groupId, mod);
            }
        }
    }

    /**
     * @dev Checks if a group exists in the organization
     * @param groupId The group ID to check
     * @return True if the group exists, false otherwise
     */
    function isGroup(uint256 groupId) internal view returns (bool) {
        return LibOrganizationGroupsStorage.layout().isGroup[groupId];
    }

    /**
     * @dev Checks if an address is a member of a group
     * @param groupId The group ID to check
     * @param memberAddress The address to check
     * @return True if the address is a member of the group, false otherwise
     */
    function isGroupMember(uint256 groupId, address memberAddress) internal view returns (bool) {
        return LibOrganizationGroupsStorage.layout().isGroupMember[groupId][memberAddress];
    }

    /**
     * @dev Deletes a group. Reverts if group does not exist or if members are provided.
     * @param groupsLayout The groups storage layout
     * @param groupId The group ID to delete
     * @param mod The group modification containing the delete request
     */
    function _deleteGroup(
        LibOrganizationGroupsStorage.Layout storage groupsLayout,
        uint256 groupId,
        GroupModification calldata mod
    ) private {
        // Case: Group does not exist
        if (!groupsLayout.isGroup[groupId]) revert IOrganizationGroups.GroupDoesNotExist(groupId);

        // Case: Deletion with non-empty member arrays
        if (mod.membersToAdd.length > 0 || mod.membersToRemove.length > 0) {
            revert IOrganizationGroups.InvalidGroupDeletionOperation(groupId);
        }

        groupsLayout.isGroup[groupId] = false;
        groupsLayout.wasGroupDeleted[groupId] = true;
        emit IOrganizationGroups.GroupDeleted(groupId);
    }

    /**
     * @dev Creates a new group or modifies an existing one.
     *      If the group doesn't exist and hasn't been deleted, it is implicitly created.
     * @param groupsLayout The groups storage layout
     * @param groupId The group ID to create or modify
     * @param mod The group modification containing members to add/remove
     */
    function _createOrModifyGroup(
        LibOrganizationGroupsStorage.Layout storage groupsLayout,
        uint256 groupId,
        GroupModification calldata mod
    ) private {
        // Case: Group ID was previously deleted — cannot be reused
        if (groupsLayout.wasGroupDeleted[groupId]) revert IOrganizationGroups.GroupAlreadyDeleted(groupId);

        // Implicit group creation if it doesn't exist yet
        if (!groupsLayout.isGroup[groupId]) {
            groupsLayout.isGroup[groupId] = true;
            emit IOrganizationGroups.GroupCreated(groupId);
        }

        // Process member additions
        for (uint256 j = 0; j < mod.membersToAdd.length; ++j) {
            address member = mod.membersToAdd[j];
            if (member == address(0)) revert IOrganizationGroups.InvalidGroupMemberAddress(groupId, member);

            // No-op if already in group
            if (groupsLayout.isGroupMember[groupId][member]) continue;

            groupsLayout.isGroupMember[groupId][member] = true;
            emit IOrganizationGroups.GroupMemberAdded(groupId, member);
        }

        // Process member removals
        for (uint256 j = 0; j < mod.membersToRemove.length; ++j) {
            address member = mod.membersToRemove[j];

            // Case: Member is not in the group
            if (!groupsLayout.isGroupMember[groupId][member]) {
                revert IOrganizationGroups.MemberNotInGroup(groupId, member);
            }

            groupsLayout.isGroupMember[groupId][member] = false;
            emit IOrganizationGroups.GroupMemberRemoved(groupId, member);
        }
    }
}
