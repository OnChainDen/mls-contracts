// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IAccountUpgradeable
 * @notice Interface for upgrading Account contracts from the Organization
 * @author Den Technologies Inc
 */
interface IAccountUpgradeable {
    /**
     * @notice Upgrade the implementation to a new address, callable only by the Organization
     * @param newImplementation The new implementation address
     * @param data The calldata to call on the new implementation (can be empty)
     */
    function upgradeToFromOrganization(address newImplementation, bytes memory data) external;
}
