// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Organization Signatures Storage
 * @dev Storage layout for organization signature and nonce functionality
 * @dev Used for all operation types (admin operations and account transactions)
 * @author Den Technologies Inc
 */
library LibOrganizationSignaturesStorage {
    /**
     * @dev Storage layout for signature nonce tracking
     * @param usedNonces Mapping of nonces that have been consumed (nonce => used)
     */
    struct Layout {
        mapping(uint256 => bool) usedNonces;
    }

    /// @dev Storage slot for the signatures storage layout, computed as
    /// keccak256("onchain.custody.organization.signatures.storage")
    bytes32 internal constant STORAGE_SLOT = keccak256("onchain.custody.organization.signatures.storage");

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
