// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Organization Deployer Address Storage
 * @notice Storage layout for the deployer address used in organization initialization
 * @author Den Technologies Inc
 */
library LibOrganizationDeployerAddressStorage {
    /**
     * @notice Storage layout for deployer address
     * @param deployerAddress Address authorized for post-deployment initialization
     */
    struct Layout {
        address deployerAddress;
    }

    /// @dev Storage slot for the deployer storage layout, computed as
    /// keccak256("onchain.custody.organization.deployer.storage")
    bytes32 internal constant STORAGE_SLOT = keccak256("onchain.custody.organization.deployer.storage");

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
