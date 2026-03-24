// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {AdminAuthParams} from "types/AdminTypes.sol";
import {GroupModification} from "types/CommonTypes.sol";

/**
 * @title IOrganizationGroups
 * @notice Interface for group-related operations in Organization contracts
 * @dev Maps to LibOrganizationGroups library functionality.
 *      Groups are stored in mappings for O(1) lookups.
 *      Group IDs are not reusable after deletion.
 *      Group membership entries (isGroupMember) persist in storage even after a member is removed
 *      from the organization via modifyMembers. If the member is later re-added, their previous
 *      group memberships become effective again. Use modifyGroups to explicitly remove a member
 *      from groups if this behavior is not desired.
 * @author Den Technologies Inc
 */
interface IOrganizationGroups {
    // ═══════════════════════════════════════════════════════════════════════════
    // Events
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Emitted when a new group is created
     * @param groupId The ID of the created group
     */
    event GroupCreated(uint256 indexed groupId);

    /**
     * @notice Emitted when a group is deleted
     * @param groupId The ID of the deleted group
     */
    event GroupDeleted(uint256 indexed groupId);

    /**
     * @notice Emitted when a member is added to a group
     * @param groupId The ID of the group
     * @param member The address of the added member
     */
    event GroupMemberAdded(uint256 indexed groupId, address indexed member);

    /**
     * @notice Emitted when a member is removed from a group
     * @param groupId The ID of the group
     * @param member The address of the removed member
     */
    event GroupMemberRemoved(uint256 indexed groupId, address indexed member);

    // ═══════════════════════════════════════════════════════════════════════════
    // Errors
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Thrown when trying to update or delete a group that does not exist
     * @param groupId The non-existent group ID
     */
    error GroupDoesNotExist(uint256 groupId);

    /**
     * @notice Thrown when trying to create a group that already exists
     * @param groupId The existing group ID
     */
    error GroupAlreadyExists(uint256 groupId);

    /**
     * @notice Thrown when trying to create or recreate a group ID that was previously deleted
     * @param groupId The deleted group ID
     */
    error GroupAlreadyDeleted(uint256 groupId);

    /**
     * @notice Thrown when trying to create a group while providing members to remove
     * @param groupId The group ID being created
     */
    error InvalidGroupCreationOperation(uint256 groupId);

    /**
     * @notice Thrown when trying to delete a group while providing members to add or remove
     * @param groupId The group ID being deleted
     */
    error InvalidGroupDeletionOperation(uint256 groupId);

    /**
     * @notice Thrown when a group modification has an invalid enum value
     * @param modificationType The invalid modification type value
     */
    error InvalidGroupModificationType(uint8 modificationType);

    // ═══════════════════════════════════════════════════════════════════════════
    // Functions
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Creates, updates, or deletes groups in the organization
     * @dev Each modification specifies its type via GroupModificationType:
     *      - Create: creates a new group (reverts if already exists, was deleted, or membersToRemove is non-empty)
     *      - Update: modifies membership of an existing group (reverts if group doesn't exist)
     *      - Delete: deletes a group (membersToAdd/membersToRemove must be empty)
     *      Adding a duplicate group member is a no-op. Removing a non-existent group member is a no-op.
     *      Group IDs are not reusable after deletion.
     * @param modifications Array of group modifications to apply
     * @param authParams The authorization parameters (salt, expiration, signatures)
     */
    function modifyGroups(GroupModification[] calldata modifications, AdminAuthParams calldata authParams) external;

    /**
     * @notice Checks if a group exists in the organization
     * @param groupId The group ID to check
     * @return True if the group exists, false otherwise
     */
    function isGroup(uint256 groupId) external view returns (bool);

    /**
     * @notice Checks if an address is a member of a group
     * @dev Returns false if the group does not exist or if the address is not currently an
     *      organization member, even if the underlying isGroupMember storage bit is set.
     *      The raw storage bit persists across member removal/re-addition cycles by design.
     * @param groupId The group ID to check
     * @param memberAddress The address to check
     * @return True if the address is a member of the group, false otherwise
     */
    function isGroupMember(uint256 groupId, address memberAddress) external view returns (bool);
}
