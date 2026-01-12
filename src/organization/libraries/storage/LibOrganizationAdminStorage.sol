// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Organization Admin Storage
 * @notice Storage layout for organization admin functionality
 * @dev Admin is a list of members represented as a Merkle tree
 * @author Den Technologies Inc
 */
library LibOrganizationAdminStorage {
    /**
     * @notice Structure to define admin permissions
     * @dev Admins are stored as a Merkle tree of member addresses
     * @param adminsRoot Merkle root of admin member addresses
     * @param adminCount Number of admins in the tree (for completeness validation)
     * @param votingThreshold Number of signatures required for admin operations
     */
    struct AdminPermission {
        bytes32 adminsRoot;
        uint256 adminCount;
        uint256 votingThreshold;
    }

    /**
     * @notice Storage layout for admin permissions
     * @param adminPermission The admin permission configuration
     */
    struct Layout {
        AdminPermission adminPermission;
    }

    /// @dev Storage slot for the admin storage layout, computed as
    /// keccak256("onchain.custody.organization.admin.storage")
    bytes32 internal constant STORAGE_SLOT = keccak256("onchain.custody.organization.admin.storage");

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
