// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

/**
 * @title Organization Deployer Address Storage
 * @dev ERC-7201 namespaced storage for the deployer address used in organization initialization
 * @author Den Technologies Inc
 */
library LibOrganizationDeployerAddressStorage {
    /**
     * @dev Storage layout for deployer address
     * @custom:storage-location erc7201:den.mls-wallet.organization.deployer
     * @param deployerAddress Address authorized for post-deployment initialization
     */
    struct Layout {
        address deployerAddress;
    }

    /// @dev Storage location for DeployerAddressStorage, following ERC-7201 namespaced storage pattern.
    /// @dev Formula: keccak256(abi.encode(uint256(keccak256("den.mls-wallet.organization.deployer")) - 1)) &
    /// ~bytes32(uint256(0xff)) @dev Verify: `cast index-erc7201 "den.mls-wallet.organization.deployer"`
    bytes32 internal constant STORAGE_LOCATION = 0x56adc8ceae2dbb943ac8b82714e40a1aac36fca8b6dbb11dfc9941c4d04f2400;

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
