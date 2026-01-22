// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title ISafeSingletonFactory
 * @notice Interface for Safe Singleton Factory
 * @dev Safe Singleton Factory: deploy(bytes initCode, bytes32 salt) -> address payable deployedAddress
 * @author Den Technologies Inc
 */
interface ISafeSingletonFactory {
    /**
     * @notice Deploys a contract using CREATE2
     * @param initCode The contract creation (init) bytecode
     * @param salt The salt for deterministic address derivation
     * @return deployedAddress The address of the deployed contract
     */
    function deploy(bytes memory initCode, bytes32 salt) external returns (address payable deployedAddress);
}
