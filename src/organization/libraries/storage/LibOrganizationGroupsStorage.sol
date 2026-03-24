// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

/**
 * @title Organization Groups Storage
 * @dev ERC-7201 namespaced storage for mapping-based groups functionality.
 *      Group existence and group membership are stored in mappings for O(1) lookups.
 *      Group IDs are not reusable after deletion -- isGroupMember entries persist as ghost data.
 *      The wasGroupDeleted mapping tracks deleted group IDs to prevent recreation.
 * @author Den Technologies Inc
 */
library LibOrganizationGroupsStorage {
    /**
     * @dev Storage layout for groups functionality
     * @custom:storage-location erc7201:den.mls-wallet.organization.groups
     * @param isGroup Mapping from group ID to existence status
     * @param isGroupMember Mapping from group ID to member address to membership status
     * @param wasGroupDeleted Mapping from group ID to deletion status (prevents ID reuse)
     */
    struct Layout {
        mapping(uint256 groupId => bool) isGroup;
        mapping(uint256 groupId => mapping(address => bool)) isGroupMember;
        mapping(uint256 groupId => bool) wasGroupDeleted;
    }

    /// @dev Storage location for GroupsStorage, following ERC-7201 namespaced storage pattern.
    /// @dev Formula: keccak256(abi.encode(uint256(keccak256("den.mls-wallet.organization.groups")) - 1)) &
    /// ~bytes32(uint256(0xff)) @dev Verify: `cast index-erc7201 "den.mls-wallet.organization.groups"`
    bytes32 internal constant STORAGE_LOCATION = 0xf9619a082569050ac05ceff986096b3369f62becb728f8c488e07241ae3e2300;

    /**
     * @dev Returns the storage layout at the namespaced slot
     * @return _layout The storage layout struct
     */
    function layout() internal pure returns (Layout storage _layout) {
        assembly {
            _layout.slot := STORAGE_LOCATION
        }
    }
}
