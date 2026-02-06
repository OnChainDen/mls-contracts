// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

/**
 * @title Organization Admin Operation Timelock Storage
 * @dev ERC-7201 namespaced storage for organization-wide admin operation timelock configuration.
 *      The admin operation timelock duration is used across multiple timelocked operations:
 *      - Guardian updates (initiate → finalize → accept)
 *      - Deferred recovery initialization (initiate → finalize)
 *      - Any future timelocked operations
 * @author Den Technologies Inc
 */
library LibOrganizationAdminOperationTimelockStorage {
    /**
     * @dev Storage layout for admin operation timelock configuration.
     * @custom:storage-location erc7201:den.mls-wallet.organization.admin-operation-timelock
     * @param adminOperationTimelockDurationSeconds The organization-wide timelock duration in seconds for sensitive
     * operations
     */
    struct Layout {
        uint256 adminOperationTimelockDurationSeconds;
    }

    /// @dev Storage location for AdminOperationTimelockStorage, following ERC-7201 namespaced storage pattern.
    /// @dev Formula:
    /// keccak256(abi.encode(uint256(keccak256("den.mls-wallet.organization.admin-operation-timelock")) - 1)) &
    /// ~bytes32(uint256(0xff))
    /// @dev Verify: `cast index-erc7201 "den.mls-wallet.organization.admin-operation-timelock"`
    bytes32 internal constant STORAGE_LOCATION = 0x2dedee983475e9a745b3191742e285714c09f11646fd11e031e1c58ff9eeda00;

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
