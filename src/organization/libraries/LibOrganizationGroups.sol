// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { LibOrganizationGroupsStorage } from "./storage/LibOrganizationGroupsStorage.sol";
import { LibOrganizationMembersStorage } from "./storage/LibOrganizationMembersStorage.sol";

/**
 * @title Lib Organization Groups
 * @notice Library for group-related operations for Organization contracts
 * @dev This library should ONLY be used by Organization contracts
 * @author Den Technologies Inc
 */
library LibOrganizationGroups {
    /**
     * @notice Emitted when a group is created
     * @param groupId The ID of the created group
     * @param memberIds The initial member IDs in the group
     */
    event GroupCreated(uint8 indexed groupId, uint8[] memberIds);

    /**
     * @notice Emitted when a group is modified (members added or removed)
     * @param groupId The ID of the modified group
     * @param addedMemberIds The member IDs that were added to the group
     * @param removedMemberIds The member IDs that were removed from the group
     */
    event GroupModified(uint8 indexed groupId, uint8[] addedMemberIds, uint8[] removedMemberIds);

    /**
     * @notice Emitted when a group is removed
     * @param groupId The ID of the removed group
     */
    event GroupRemoved(uint8 indexed groupId);

    /**
     * @notice Emitted when a group operation is rejected due to invalid parameters
     * @param reason The reason for the rejection
     */
    error GroupOperationRejected(string reason);

    /**
     * @notice Checks if a member is in a group
     * @param memberId The ID of the member
     * @param groupId The ID of the group
     * @return True if the member is in the group, false otherwise
     */
    function isMemberInGroup(uint8 memberId, uint8 groupId) internal view returns (bool) {
        LibOrganizationGroupsStorage.Layout storage groupsLayout = LibOrganizationGroupsStorage.layout();
        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();

        // Case: Member does not exist
        if (membersLayout.memberIdToAddress[memberId] == address(0)) return false;

        return groupsLayout.groupIdToMemberIdToInGroup[groupId][memberId];
    }

    /**
     * @notice Checks if a member is in a group
     * @param memberAddress The address of the member
     * @param groupId The ID of the group
     * @return True if the member is in the group, false otherwise
     */
    function isMemberInGroup(address memberAddress, uint8 groupId) internal view returns (bool) {
        LibOrganizationGroupsStorage.Layout storage groupsLayout = LibOrganizationGroupsStorage.layout();
        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();
        uint8 memberId = membersLayout.addressToMemberId[memberAddress];

        // Case: Member does not exist
        if (memberId == 0) return false;

        return groupsLayout.groupIdToMemberIdToInGroup[groupId][memberId];
    }

    /**
     * @notice Checks if a group exists
     * @param groupId The ID of the group to check
     * @return True if the group exists, false otherwise
     */
    function groupExists(uint8 groupId) internal view returns (bool) {
        return LibOrganizationGroupsStorage.layout().groupIdToExists[groupId];
    }

    /**
     * @notice Checks if a group ID is valid and has at least one member
     * @param groupId The group ID to validate
     * @return True if the group exists and has members, false otherwise
     */
    function isValidGroupWithMembers(uint8 groupId) internal view returns (bool) {
        LibOrganizationGroupsStorage.Layout storage groupsLayout = LibOrganizationGroupsStorage.layout();
        return groupsLayout.groupIdToExists[groupId] && groupsLayout.groupIdToMemberCount[groupId] > 0;
    }

    /**
     * @notice Creates a new group with the specified member IDs
     * @param memberIds The array of member IDs to include in the group
     * @return groupId The auto-generated ID of the created group
     */
    function createGroup(uint8[] memory memberIds) internal returns (uint8 groupId) {
        // Validate input parameters
        if (memberIds.length == 0) {
            revert GroupOperationRejected("Group must have at least one member");
        }

        LibOrganizationGroupsStorage.Layout storage groupsLayout = LibOrganizationGroupsStorage.layout();
        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();

        // Auto-increment group ID
        groupId = groupsLayout.nextGroupId;
        ++groupsLayout.nextGroupId;

        // Update member-to-group mappings and group membership flags
        for (uint256 i = 0; i < memberIds.length; ++i) {
            uint8 memberId = memberIds[i];
            if (membersLayout.memberIdToAddress[memberId] == address(0)) {
                revert GroupOperationRejected("Invalid member ID provided");
            }

            // Mark member as being in the group
            groupsLayout.groupIdToMemberIdToInGroup[groupId][memberId] = true;
        }

        // Mark group as existing and set initial member count
        groupsLayout.groupIdToExists[groupId] = true;
        groupsLayout.groupIdToMemberCount[groupId] = memberIds.length;

        // Emit event
        emit GroupCreated(groupId, memberIds);
    }

    /**
     * @notice Modifies an existing group by adding or removing members
     * @param groupId The ID of the group to modify
     * @param membersToAdd Array of member IDs to add to the group
     * @param membersToRemove Array of member IDs to remove from the group
     */
    function modifyGroup(uint8 groupId, uint8[] memory membersToAdd, uint8[] memory membersToRemove) internal {
        LibOrganizationGroupsStorage.Layout storage groupsLayout = LibOrganizationGroupsStorage.layout();
        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();

        // Check if group exists
        if (!groupsLayout.groupIdToExists[groupId]) {
            revert GroupOperationRejected("Group does not exist");
        }

        // Validate that we're actually making changes
        if (membersToAdd.length == 0 && membersToRemove.length == 0) {
            revert GroupOperationRejected("Must specify members to add or remove");
        }

        // Add new members
        for (uint256 i = 0; i < membersToAdd.length; ++i) {
            uint8 memberId = membersToAdd[i];
            if (membersLayout.memberIdToAddress[memberId] == address(0)) {
                revert GroupOperationRejected("Invalid member ID provided");
            }

            // Only add if not already in group to avoid double counting
            if (!groupsLayout.groupIdToMemberIdToInGroup[groupId][memberId]) {
                groupsLayout.groupIdToMemberIdToInGroup[groupId][memberId] = true;
                groupsLayout.groupIdToMemberCount[groupId]++;
            }
        }

        // Remove members
        for (uint256 i = 0; i < membersToRemove.length; ++i) {
            // Only remove if currently in group to avoid negative counting
            if (groupsLayout.groupIdToMemberIdToInGroup[groupId][membersToRemove[i]]) {
                groupsLayout.groupIdToMemberIdToInGroup[groupId][membersToRemove[i]] = false;
                groupsLayout.groupIdToMemberCount[groupId]--;
            }
        }

        // Emit event
        emit GroupModified(groupId, membersToAdd, membersToRemove);
    }

    /**
     * @notice Removes an existing group by marking it as not existing
     * @param groupId The ID of the group to remove
     */
    function removeGroup(uint8 groupId) internal {
        LibOrganizationGroupsStorage.Layout storage groupsLayout = LibOrganizationGroupsStorage.layout();

        // Check if group exists
        if (!groupsLayout.groupIdToExists[groupId]) {
            revert GroupOperationRejected("Group does not exist");
        }

        // Mark group as not existing and reset member count
        groupsLayout.groupIdToExists[groupId] = false;
        groupsLayout.groupIdToMemberCount[groupId] = 0;

        // Emit event
        emit GroupRemoved(groupId);
    }
}
