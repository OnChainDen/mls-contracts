// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {AdminConfig} from "types/AdminTypes.sol";

/**
 * @title Organization Admin Storage
 * @dev ERC-7201 namespaced storage for organization admin functionality.
 *      Admin is a list of members represented as a Merkle tree.
 * @author Den Technologies Inc
 */
library LibOrganizationAdminStorage {
    /**
     * @dev Storage layout for admin permissions
     * @custom:storage-location erc7201:den.mls-wallet.organization.admin
     * @param adminConfig The admin permission configuration
     */
    struct Layout {
        AdminConfig adminConfig;
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
