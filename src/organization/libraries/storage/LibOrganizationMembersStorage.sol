// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

/**
 * @title Organization Members Storage
 * @dev ERC-7201 namespaced storage for mapping-based members functionality.
 *      Members are stored in a mapping for O(1) membership checks.
 * @author Den Technologies Inc
 */
library LibOrganizationMembersStorage {
    /**
     * @dev Storage layout for members functionality
     * @custom:storage-location erc7201:den.mls-wallet.organization.members
     * @param isMember Mapping from address to membership status
     * @param memberCount Total number of members in the organization
     */
    struct Layout {
        mapping(address => bool) isMember;
        uint256 memberCount;
    }

    /// @dev Storage location for MembersStorage, following ERC-7201 namespaced storage pattern.
    /// @dev Formula: keccak256(abi.encode(uint256(keccak256("den.mls-wallet.organization.members")) - 1)) &
    /// ~bytes32(uint256(0xff)) @dev Verify: `cast index-erc7201 "den.mls-wallet.organization.members"`
    bytes32 internal constant STORAGE_LOCATION = 0xb80799cfa22e7d42bb36b2b397b5d0bd56930d54ee4f345397b8ece603c6f300;

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
