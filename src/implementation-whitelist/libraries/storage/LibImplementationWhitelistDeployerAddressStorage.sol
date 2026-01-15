// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title Implementation Whitelist Deployer Address Storage
 * @dev ERC-7201 namespaced storage for the deployer address used in implementation whitelist initialization
 * @author Den Technologies Inc
 */
library LibImplementationWhitelistDeployerAddressStorage {
    /**
     * @dev Storage layout for deployer address
     * @custom:storage-location erc7201:den.mls-wallet.implementation-whitelist.deployer
     * @param deployerAddress Address authorized for post-deployment initialization
     */
    struct Layout {
        address deployerAddress;
    }

    /// @dev Storage location for DeployerAddressStorage, following ERC-7201 namespaced storage pattern.
    /// @dev Formula: keccak256(abi.encode(uint256(keccak256("den.mls-wallet.implementation-whitelist.deployer")) - 1))
    /// & ~bytes32(uint256(0xff)) @dev Verify: `cast index-erc7201 "den.mls-wallet.implementation-whitelist.deployer"`
    bytes32 internal constant STORAGE_LOCATION = 0xea8b8b71bfe3dd2c569373ac558f1077dde0b706e5c8860bfaf2a9479b790900;

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
