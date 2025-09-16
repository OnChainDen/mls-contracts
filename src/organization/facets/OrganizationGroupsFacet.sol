// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { OrganizationGroupsFacetStorage } from "./OrganizationGroupsFacetStorage.sol";
import { OrganizationMembersFacetStorage } from "./OrganizationMembersFacetStorage.sol";
import { OrganizationAdminFacetStorage } from "./OrganizationAdminFacetStorage.sol";
import { IAdminFacet, AdminOperationType } from "../../interfaces/IAdminFacet.sol";
import { IGuardianFacet } from "../../interfaces/IGuardianFacet.sol";

/**
 * @title Organization Groups Facet
 * @notice Handles group-related operations for the OnchainCustodyOrganization diamond
 * @author Den Technologies Inc
 */
contract OrganizationGroupsFacet {
    using OrganizationGroupsFacetStorage for OrganizationGroupsFacetStorage.Layout;
    using OrganizationMembersFacetStorage for OrganizationMembersFacetStorage.Layout;

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
    function isMemberInGroup(uint8 memberId, uint8 groupId) public view returns (bool) {
        OrganizationGroupsFacetStorage.Layout storage groupsLayout = OrganizationGroupsFacetStorage.layout();
        OrganizationMembersFacetStorage.Layout storage membersLayout = OrganizationMembersFacetStorage.layout();

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
    function isMemberInGroup(address memberAddress, uint8 groupId) public view returns (bool) {
        OrganizationGroupsFacetStorage.Layout storage groupsLayout = OrganizationGroupsFacetStorage.layout();
        OrganizationMembersFacetStorage.Layout storage membersLayout = OrganizationMembersFacetStorage.layout();
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
    function groupExists(uint8 groupId) external view returns (bool) {
        return OrganizationGroupsFacetStorage.layout().groupIdToExists[groupId];
    }

    /**
     * @notice Checks if a group ID is valid and has at least one member
     * @param groupId The group ID to validate
     * @return True if the group exists and has members, false otherwise
     */
    function isValidGroupWithMembers(uint8 groupId) external view returns (bool) {
        OrganizationGroupsFacetStorage.Layout storage groupsLayout = OrganizationGroupsFacetStorage.layout();
        return groupsLayout.groupIdToExists[groupId] && groupsLayout.groupIdToMemberCount[groupId] > 0;
    }

    /**
     * @notice Creates a new group with the specified member IDs
     * @dev This function can only be called by the current admin (individual or group with sufficient signatures)
     * @param memberIds The array of member IDs to include in the group
     * @param salt A user-provided salt for nonce computation
     * @param chainId The chain ID for cross-chain replay protection - must match current chain ID
     * @param signatures The signatures from the current admin authorizing this operation
     * @return groupId The auto-generated ID of the created group
     */
    function createGroup(
        uint8[] memory memberIds,
        uint256 salt,
        uint256 chainId,
        bytes memory signatures
    )
        public
        returns (uint8 groupId)
    {
        IGuardianFacet(address(this)).enforceOnlyGuardian();

        // Validate input parameters
        if (memberIds.length == 0) {
            revert GroupOperationRejected("Group must have at least one member");
        }

        OrganizationGroupsFacetStorage.Layout storage groupsLayout = OrganizationGroupsFacetStorage.layout();
        OrganizationMembersFacetStorage.Layout storage membersLayout = OrganizationMembersFacetStorage.layout();

        // Auto-increment group ID
        groupId = groupsLayout.nextGroupId;
        ++groupsLayout.nextGroupId;

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(groupId, memberIds);

        // Validate that the current admin has authorized this operation
        IAdminFacet(address(this)).validateAdminAuthorization(
            AdminOperationType.CreateGroup, operationData, salt, chainId, signatures
        );

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
     * @dev This function can only be called by the current admin (individual or group with sufficient signatures)
     * @param groupId The ID of the group to modify
     * @param membersToAdd Array of member IDs to add to the group
     * @param membersToRemove Array of member IDs to remove from the group
     * @param salt A user-provided salt for nonce computation
     * @param chainId The chain ID for cross-chain replay protection - must match current chain ID
     * @param signatures The signatures from the current admin authorizing this operation
     */
    function modifyGroup(
        uint8 groupId,
        uint8[] memory membersToAdd,
        uint8[] memory membersToRemove,
        uint256 salt,
        uint256 chainId,
        bytes memory signatures
    )
        public
    {
        IGuardianFacet(address(this)).enforceOnlyGuardian();

        OrganizationGroupsFacetStorage.Layout storage groupsLayout = OrganizationGroupsFacetStorage.layout();
        OrganizationMembersFacetStorage.Layout storage membersLayout = OrganizationMembersFacetStorage.layout();

        // Check if group exists
        if (!groupsLayout.groupIdToExists[groupId]) {
            revert GroupOperationRejected("Group does not exist");
        }

        // Validate that we're actually making changes
        if (membersToAdd.length == 0 && membersToRemove.length == 0) {
            revert GroupOperationRejected("Must specify members to add or remove");
        }

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(groupId, membersToAdd, membersToRemove);

        // Validate that the current admin has authorized this operation
        IAdminFacet(address(this)).validateAdminAuthorization(
            AdminOperationType.ModifyGroup, operationData, salt, chainId, signatures
        );

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
     * @dev This function can only be called by the current admin (individual or group with sufficient signatures)
     * @param groupId The ID of the group to remove
     * @param salt A user-provided salt for nonce computation
     * @param chainId The chain ID for cross-chain replay protection - must match current chain ID
     * @param signatures The signatures from the current admin authorizing this operation
     */
    function removeGroup(uint8 groupId, uint256 salt, uint256 chainId, bytes memory signatures) public {
        IGuardianFacet(address(this)).enforceOnlyGuardian();

        OrganizationGroupsFacetStorage.Layout storage groupsLayout = OrganizationGroupsFacetStorage.layout();

        // Check if group exists
        if (!groupsLayout.groupIdToExists[groupId]) {
            revert GroupOperationRejected("Group does not exist");
        }

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(groupId);

        // Validate that the current admin has authorized this operation
        IAdminFacet(address(this)).validateAdminAuthorization(
            AdminOperationType.RemoveGroup, operationData, salt, chainId, signatures
        );

        // Mark group as not existing and reset member count
        groupsLayout.groupIdToExists[groupId] = false;
        groupsLayout.groupIdToMemberCount[groupId] = 0;

        // Emit event
        emit GroupRemoved(groupId);
    }
}
