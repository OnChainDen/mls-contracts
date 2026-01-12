// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Organization Account Factory Storage
 * @notice Storage layout for organization account factory functionality
 * @author Den Technologies Inc
 */
library LibOrganizationAccountFactoryStorage {
    /**
     * @notice Storage layout for account factory functionality
     * @param deployedAccounts Mapping of account addresses deployed by this organization
     * @param accountImplementation The current implementation address for all Account beacon proxies
     */
    struct Layout {
        mapping(address => bool) deployedAccounts;
        address accountImplementation;
    }

    /// @dev Storage slot for the account factory storage layout, computed as
    /// keccak256("onchain.custody.organization.account.factory.storage")
    bytes32 internal constant STORAGE_SLOT = keccak256("onchain.custody.organization.account.factory.storage");

    /**
     * @notice Returns the storage layout at the namespaced slot
     * @dev Uses assembly to access storage at the precomputed slot
     * @return _layout The storage layout struct
     */
    function layout() internal pure returns (Layout storage _layout) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            _layout.slot := slot
        }
    }
}
