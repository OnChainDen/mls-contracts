// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

/**
 * @title Organization Admin Storage
 * @dev ERC-7201 namespaced storage for organization admin functionality.
 *      Admins are stored in a mapping for O(1) admin checks.
 *      adminCount and votingThreshold are stored directly (AdminConfig struct is removed).
 * @author Den Technologies Inc
 */
library LibOrganizationAdminStorage {
    /**
     * @dev Storage layout for admin permissions
     * @custom:storage-location erc7201:den.mls-wallet.organization.admin
     * @param isAdmin Mapping from address to admin status
     * @param adminCount Total number of admins in the organization
     * @param votingThreshold Number of admin signatures required for admin operations
     */
    struct Layout {
        mapping(address => bool) isAdmin;
        uint256 adminCount;
        uint256 votingThreshold;
    }

    /// @dev Storage location for AdminStorage, following ERC-7201 namespaced storage pattern.
    /// @dev Formula: keccak256(abi.encode(uint256(keccak256("den.mls-wallet.organization.admin")) - 1)) &
    /// ~bytes32(uint256(0xff)) @dev Verify: `cast index-erc7201 "den.mls-wallet.organization.admin"`
    bytes32 internal constant STORAGE_LOCATION = 0xdf7b9968ae7e869596f5c33210e34de0a875d3a941d5059f354cd7000f80df00;

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
