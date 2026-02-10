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
     * @notice Thrown when trying to modify a group that does not exist
     * @param groupId The non-existent group ID
     */
    error GroupDoesNotExist(uint256 groupId);

    /**
     * @notice Thrown when trying to recreate a group ID that was previously deleted
     * @param groupId The deleted group ID
     */
    error GroupAlreadyDeleted(uint256 groupId);

    /**
     * @notice Thrown when trying to delete a group while providing members to add or remove
     * @param groupId The group ID being deleted
     */
    error GroupDeletionWithMembers(uint256 groupId);

    /**
     * @notice Thrown when trying to remove a member who is not in the group
     * @param groupId The group ID
     * @param member The address that is not in the group
     */
    error MemberNotInGroup(uint256 groupId, address member);

    /**
     * @notice Thrown when a group member address is the zero address
     * @param groupId The group ID
     * @param member The invalid zero address
     */
    error InvalidGroupMemberAddress(uint256 groupId, address member);

    // ═══════════════════════════════════════════════════════════════════════════
    // Functions
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Creates, modifies, or deletes groups in the organization
     * @dev When deleteGroup is true, the group is deleted and membersToAdd/membersToRemove must be empty.
     *      When deleteGroup is false and the groupId doesn't exist yet, the group is implicitly created.
     *      Adding a duplicate group member is a no-op. Removing a non-existent group member reverts.
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
     * @param groupId The group ID to check
     * @param memberAddress The address to check
     * @return True if the address is a member of the group, false otherwise
     */
    function isGroupMember(uint256 groupId, address memberAddress) external view returns (bool);
}
