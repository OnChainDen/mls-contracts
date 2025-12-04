// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IUpgradeable
 * @notice Interface for upgradeable contracts with authorization
 * @author Den Technologies Inc
 */
interface IUpgradeable {
    /**
     * @notice Upgrade the implementation to a new address with authorization
     * @param newImplementation The new implementation address
     * @param salt A user-provided salt for nonce computation
     * @param signatures The signatures from admin(s) authorizing this upgrade
     */
    function upgradeToWithAuthorization(address newImplementation, uint256 salt, bytes calldata signatures) external;

    /**
     * @notice Upgrade the implementation to a new address and call a function with authorization
     * @param newImplementation The new implementation address
     * @param data The calldata to call on the new implementation
     * @param salt A user-provided salt for nonce computation
     * @param signatures The signatures from admin(s) authorizing this upgrade
     */
    function upgradeToAndCallWithAuthorization(
        address newImplementation,
        bytes memory data,
        uint256 salt,
        bytes calldata signatures
    )
        external;
}
