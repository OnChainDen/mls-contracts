// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Organization Admin Storage
 * @dev ERC-7201 namespaced storage for organization admin functionality.
 *      Admin is a list of members represented as a Merkle tree.
 * @author Den Technologies Inc
 */
library LibOrganizationAdminStorage {
    /**
     * @dev Structure to define admin permissions.
     *      Admins are stored as a Merkle tree of member addresses.
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
     * @dev Storage layout for admin permissions
     * @custom:storage-location erc7201:den.mls-wallet.organization.admin
     * @param adminPermission The admin permission configuration
     */
    struct Layout {
        AdminPermission adminPermission;
    }

    /// @dev Storage location for AdminStorage, following ERC-7201 namespaced storage pattern.
    /// @dev Formula: keccak256(abi.encode(uint256(keccak256("den.mls-wallet.organization.admin")) - 1)) &
    /// ~bytes32(uint256(0xff)) @dev Verify: `cast index-erc7201 "den.mls-wallet.organization.admin"`
    bytes32 internal constant STORAGE_LOCATION = 0xdf7b9968ae7e869596f5c33210e34de0a875d3a941d5059f354cd7000f80df00;

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
