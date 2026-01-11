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

    struct Layout {
        AdminPermission adminPermission;
    }

    bytes32 internal constant STORAGE_SLOT = keccak256("onchain.custody.organization.admin.storage");

    function layout() internal pure returns (Layout storage _layout) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            _layout.slot := slot
        }
    }
}
