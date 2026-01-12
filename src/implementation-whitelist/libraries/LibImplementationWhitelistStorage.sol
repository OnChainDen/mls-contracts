// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IImplementationWhitelist} from "../interfaces/IImplementationWhitelist.sol";

/**
 * @title Implementation Whitelist Storage
 * @notice Storage layout for implementation whitelist functionality
 * @author Den Technologies Inc
 */
library LibImplementationWhitelistStorage {
    /**
     * @notice Storage layout for implementation whitelist
     * @param whitelisted Nested mapping of contract type to implementation address to whitelist status
     */
    struct Layout {
        mapping(IImplementationWhitelist.ContractType => mapping(address => bool)) whitelisted;
    }

    /// @dev Storage slot for the whitelist storage layout, computed as
    /// keccak256("onchain.custody.implementation.whitelist.storage")
    bytes32 internal constant STORAGE_SLOT = keccak256("onchain.custody.implementation.whitelist.storage");

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
