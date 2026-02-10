// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {AdminAuthParams} from "types/AdminTypes.sol";

/**
 * @title IOrganizationMembers
 * @notice Interface for member-related operations in Organization contracts
 * @dev Maps to LibOrganizationMembers library functionality.
 *      Members are stored in a mapping for O(1) membership checks.
 * @author Den Technologies Inc
 */
interface IOrganizationMembers {
    // ═══════════════════════════════════════════════════════════════════════════
    // Events
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Emitted when a member is added to the organization
     * @param member The address of the added member
     */
    event MemberAdded(address indexed member);

    /**
     * @notice Emitted when a member is removed from the organization
     * @param member The address of the removed member
     */
    event MemberRemoved(address indexed member);

    // ═══════════════════════════════════════════════════════════════════════════
    // Errors
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Thrown when trying to remove a member who is currently an admin
     * @dev Admin status must be removed via modifyAdmins before removing the member
     * @param member The address of the member who is an admin
     */
    error MemberIsAdmin(address member);

    /**
     * @notice Thrown when trying to remove a member who does not exist
     * @param member The address that is not a member
     */
    error MemberDoesNotExist(address member);

    /**
     * @notice Thrown when the member address is the zero address
     * @param member The invalid zero address
     */
    error InvalidMemberAddress(address member);

    // ═══════════════════════════════════════════════════════════════════════════
    // Functions
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Adds and/or removes members from the organization
     * @dev Adding a duplicate member is a no-op. Removing a non-existent member reverts.
     *      Removing a member who is an admin reverts with MemberIsAdmin.
     * @param membersToAdd Addresses to add as members
     * @param membersToRemove Addresses to remove from members
     * @param authParams The authorization parameters (salt, expiration, signatures)
     */
    function modifyMembers(
        address[] calldata membersToAdd,
        address[] calldata membersToRemove,
        AdminAuthParams calldata authParams
    ) external;

    /**
     * @notice Checks if an address is a member of the organization
     * @param memberAddress The address to check
     * @return True if the address is a member, false otherwise
     */
    function isMember(address memberAddress) external view returns (bool);
}
