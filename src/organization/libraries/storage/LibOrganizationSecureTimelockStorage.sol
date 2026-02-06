// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

/**
 * @title Organization Secure Timelock Storage
 * @dev ERC-7201 namespaced storage for organization-wide secure timelock configuration.
 *      The secure timelock duration is used across multiple timelocked operations:
 *      - Guardian updates (initiate → finalize → accept)
 *      - Deferred recovery initialization (initiate → finalize)
 *      - Any future timelocked operations
 * @author Den Technologies Inc
 */
library LibOrganizationSecureTimelockStorage {
    /**
     * @dev Storage layout for secure timelock configuration.
     * @custom:storage-location erc7201:den.mls-wallet.organization.secure-timelock
     * @param secureTimelockDurationSeconds The organization-wide timelock duration in seconds for sensitive operations
     */
    struct Layout {
        uint256 secureTimelockDurationSeconds;
    }

    /// @dev Storage location for SecureTimelockStorage, following ERC-7201 namespaced storage pattern.
    /// @dev Formula: keccak256(abi.encode(uint256(keccak256("den.mls-wallet.organization.secure-timelock")) - 1)) &
    /// ~bytes32(uint256(0xff))
    /// @dev Verify: `cast index-erc7201 "den.mls-wallet.organization.secure-timelock"`
    bytes32 internal constant STORAGE_LOCATION = 0x3b36922b7d70cab8b0b8cd0c1102d4d7da23febe14e2e255bd9f74472cbd2d00;

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
