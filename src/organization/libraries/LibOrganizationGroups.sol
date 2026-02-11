// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationGroups} from "interfaces/organization/IOrganizationGroups.sol";
import {IOrganizationMembers} from "interfaces/organization/IOrganizationMembers.sol";
import {LibOrganizationGroupsStorage} from "organization/libraries/storage/LibOrganizationGroupsStorage.sol";
import {GroupModification, GroupModificationType} from "types/CommonTypes.sol";

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
     * @dev Creates, updates, or deletes groups in the organization.
     *      Each modification specifies its type via GroupModificationType:
     *      - Create: creates a new group (reverts if already exists, was deleted, or membersToRemove is non-empty)
     *      - Update: modifies membership of an existing group (reverts if group doesn't exist)
     *      - Delete: deletes a group (membersToAdd/membersToRemove must be empty)
     *      Adding a duplicate group member is a no-op. Removing a non-existent group member reverts.
     *      Group IDs are not reusable after deletion.
     * @param modifications Array of group modifications to apply
     */
    function modifyGroups(GroupModification[] calldata modifications) public {
        for (uint256 i = 0; i < modifications.length; ++i) {
            GroupModification calldata mod = modifications[i];

            if (mod.modificationType == GroupModificationType.Create) {
                _createGroup(mod);
            } else if (mod.modificationType == GroupModificationType.Update) {
                _updateGroup(mod);
            } else if (mod.modificationType == GroupModificationType.Delete) {
                _deleteGroup(mod);
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
     * @param mod The group modification containing the delete request
     */
    function _deleteGroup(GroupModification calldata mod) private {
        LibOrganizationGroupsStorage.Layout storage groupsLayout = LibOrganizationGroupsStorage.layout();
        uint256 groupId = mod.groupId;

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
     * @dev Creates a new group. Reverts if the group already exists, was previously deleted,
     *      or if membersToRemove is non-empty.
     * @param mod The group modification containing initial members to add
     */
    function _createGroup(GroupModification calldata mod) private {
        LibOrganizationGroupsStorage.Layout storage groupsLayout = LibOrganizationGroupsStorage.layout();
        uint256 groupId = mod.groupId;

        // Case: Group ID was previously deleted — cannot be reused
        if (groupsLayout.wasGroupDeleted[groupId]) revert IOrganizationGroups.GroupAlreadyDeleted(groupId);

        // Case: Group already exists
        if (groupsLayout.isGroup[groupId]) revert IOrganizationGroups.GroupAlreadyExists(groupId);

        // Case: Creation with non-empty membersToRemove array
        if (mod.membersToRemove.length > 0) revert IOrganizationGroups.InvalidGroupCreationOperation(groupId);

        groupsLayout.isGroup[groupId] = true;
        emit IOrganizationGroups.GroupCreated(groupId);

        _addGroupMembers(groupsLayout, groupId, mod.membersToAdd);
    }

    /**
     * @dev Updates an existing group's membership. Reverts if the group does not exist.
     * @param mod The group modification containing members to add/remove
     */
    function _updateGroup(GroupModification calldata mod) private {
        LibOrganizationGroupsStorage.Layout storage groupsLayout = LibOrganizationGroupsStorage.layout();
        uint256 groupId = mod.groupId;

        // Case: Group does not exist
        if (!groupsLayout.isGroup[groupId]) revert IOrganizationGroups.GroupDoesNotExist(groupId);

        _addGroupMembers(groupsLayout, groupId, mod.membersToAdd);
        _removeGroupMembers(groupsLayout, groupId, mod.membersToRemove);
    }

    /**
     * @dev Adds members to a group. Adding a duplicate group member is a no-op.
     * @param groupsLayout The groups storage layout
     * @param groupId The group ID to add members to
     * @param members The addresses to add
     */
    function _addGroupMembers(
        LibOrganizationGroupsStorage.Layout storage groupsLayout,
        uint256 groupId,
        address[] calldata members
    ) private {
        for (uint256 i = 0; i < members.length; ++i) {
            address member = members[i];
            if (member == address(0)) revert IOrganizationMembers.InvalidMemberAddress(member);

            // No-op if already in group
            if (groupsLayout.isGroupMember[groupId][member]) continue;

            groupsLayout.isGroupMember[groupId][member] = true;
            emit IOrganizationGroups.GroupMemberAdded(groupId, member);
        }
    }

    /**
     * @dev Removes members from a group. Reverts if any member is not in the group.
     * @param groupsLayout The groups storage layout
     * @param groupId The group ID to remove members from
     * @param members The addresses to remove
     */
    function _removeGroupMembers(
        LibOrganizationGroupsStorage.Layout storage groupsLayout,
        uint256 groupId,
        address[] calldata members
    ) private {
        for (uint256 i = 0; i < members.length; ++i) {
            address member = members[i];

            // Case: Member is not in the group
            if (!groupsLayout.isGroupMember[groupId][member]) {
                revert IOrganizationGroups.MemberNotInGroup(groupId, member);
            }

            groupsLayout.isGroupMember[groupId][member] = false;
            emit IOrganizationGroups.GroupMemberRemoved(groupId, member);
        }
    }
}
