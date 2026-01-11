// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Organization Upgrade Storage
 * @notice Storage layout for UUPS upgrade authorization functionality
 * @dev This library provides namespaced storage for the upgrade authorization flag used to
 *      secure the UUPS upgrade flow. The flag ensures that upgrades can only occur through
 *      the authorized `upgradeToAndCallWithAuthorization` function.
 *
 *      SECURITY CONTEXT:
 *      OpenZeppelin's UUPSUpgradeable exposes a public `upgradeToAndCall` function that anyone
 *      can call. The `_authorizeUpgrade` hook only receives `newImplementation` - it cannot
 *      receive our signatures/proofs. So we use this storage flag to:
 *      1. Set `authorized = true` in `upgradeToAndCallWithAuthorization` AFTER validating
 *         guardian access, admin signatures, and implementation whitelist
 *      2. Check the flag in `_authorizeUpgrade` and revert if not set
 *      3. Reset the flag after the upgrade completes
 *
 *      This prevents attackers from bypassing our authorization by calling
 *      `upgradeToAndCall` directly on the proxy.
 *
 * @author Den Technologies Inc
 */
library LibOrganizationUpgradeStorage {
    /**
     * @notice Storage layout for upgrade authorization
     * @param authorized Flag indicating if an upgrade has been authorized through
     *        the proper flow (upgradeToAndCallWithAuthorization)
     */
    struct Layout {
        bool authorized;
    }

    /**
     * @notice Storage slot for the upgrade authorization data
     * @dev Uses a deterministic slot computed from a unique namespace string.
     *      This prevents storage collisions when upgrading contracts and ensures
     *      the slot won't shift if new state variables are added to the contract.
     */
    bytes32 internal constant STORAGE_SLOT = keccak256("onchain.custody.organization.upgrade.storage");

    /**
     * @notice Returns the storage layout at the namespaced slot
     * @dev Uses assembly to access storage at the precomputed slot
     * @return _layout The storage struct at the namespaced slot
     */
    function layout() internal pure returns (Layout storage _layout) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            _layout.slot := slot
        }
    }
}
