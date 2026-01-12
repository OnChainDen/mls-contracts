// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Organization Guardian Storage
 * @dev Storage layout for organization guardian functionality
 * @author Den Technologies Inc
 */
library LibOrganizationGuardianStorage {
    /**
     * @dev Storage layout for guardian address
     * @param guardian The address of the guardian authorized to submit transactions
     */
    struct Layout {
        address guardian;
    }

    /// @dev Storage slot for the guardian storage layout, computed as
    /// keccak256("onchain.custody.organization.guardian.storage")
    bytes32 internal constant STORAGE_SLOT = keccak256("onchain.custody.organization.guardian.storage");

    /**
     * @dev Returns the storage layout at the namespaced slot
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
