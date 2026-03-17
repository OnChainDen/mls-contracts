// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

/**
 * @title Organization Upgrade Storage
 * @dev ERC-7201 namespaced storage for Organization UUPS upgrade functionality.
 *      This library provides namespaced storage for:
 *      1. The implementation whitelist address for upgrade validation
 *      2. The one-call authorized target used to secure the UUPS upgrade flow
 *
 *      UPGRADE AUTHORIZATION SECURITY CONTEXT:
 *      OpenZeppelin's UUPSUpgradeable exposes a public `upgradeToAndCall` function that anyone
 *      can call. The `_authorizeUpgrade` hook only receives `newImplementation` - it cannot
 *      receive our signatures/proofs. So we use `authorizedUpgradeImplementation` to:
 *      1. Set `authorizedUpgradeImplementation = newImplementation` in
 *         `upgradeToAndCallWithAuthorization` AFTER validating
 *         guardian access, admin signatures, and implementation whitelist
 *      2. Check `_authorizeUpgrade(newImplementation)` matches that authorized target
 *      3. Reset `authorizedUpgradeImplementation = address(0)` after the upgrade completes
 *
 *      This prevents attackers from bypassing our authorization by calling
 *      `upgradeToAndCall` directly on the proxy.
 *
 * @author Den Technologies Inc
 */
library LibOrganizationUpgradeStorage {
    /**
     * @dev Storage layout for upgrade functionality
     * @custom:storage-location erc7201:den.mls-wallet.organization.upgrade
     * @param whitelistAddress Address of the implementation whitelist contract used to validate
     *        that new implementations are approved before upgrading
     * @param authorizedUpgradeImplementation The specific implementation target currently authorized
     *        for a UUPS upgrade call. This value is:
     *        - Set to `newImplementation` after validating guardian, admin signatures, and whitelist
     *        - Checked in `_authorizeUpgrade` to ensure authorization is target-bound
     *        - Reset to `address(0)` after the upgrade completes
     *        - CRITICAL: Prevents direct calls to `upgradeToAndCall` from bypassing authorization
     */
    struct Layout {
        address whitelistAddress;
        address authorizedUpgradeImplementation;
    }

    /// @dev Storage location for UpgradeStorage, following ERC-7201 namespaced storage pattern.
    /// @dev Formula: keccak256(abi.encode(uint256(keccak256("den.mls-wallet.organization.upgrade")) - 1)) &
    /// ~bytes32(uint256(0xff)) @dev Verify: `cast index-erc7201 "den.mls-wallet.organization.upgrade"`
    bytes32 internal constant STORAGE_LOCATION = 0x3040d5b43dcdbaf37e16e33851653f3198dd40add83f07a3836a4d13c1d85d00;

    /**
     * @dev Returns the storage layout at the namespaced slot
     * @return _layout The storage struct at the namespaced slot
     */
    function layout() internal pure returns (Layout storage _layout) {
        assembly {
            _layout.slot := STORAGE_LOCATION
        }
    }
}
