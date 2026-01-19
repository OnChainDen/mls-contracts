// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title ICreate2Factory
 * @notice Common interface for CREATE2 deterministic deployment factories
 * @dev Both Arachnid and Safe Singleton Factory implement this interface.
 *      Note: Arachnid uses deploy(bytes32, bytes) while Safe uses deploy(bytes, bytes32).
 *      This interface follows the Arachnid convention; adapters handle the difference.
 * @author Den Technologies Inc
 */
interface ICreate2Factory {
    /**
     * @notice Deploys a contract using CREATE2
     * @param salt The salt for deterministic address derivation
     * @param initCode The contract creation (init) bytecode
     * @return deployed The address of the deployed contract
     */
    function deploy(bytes32 salt, bytes memory initCode) external returns (address deployed);
}

/**
 * @title ISafeSingletonFactory
 * @notice Interface for Safe Singleton Factory which has different parameter ordering
 * @dev Safe Singleton Factory: deploy(bytes initCode, bytes32 salt)
 *      Deployed at: 0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7
 * @author Den Technologies Inc
 */
interface ISafeSingletonFactory {
    /**
     * @notice Deploys a contract using CREATE2
     * @param initCode The contract creation (init) bytecode
     * @param salt The salt for deterministic address derivation
     * @return deployed The address of the deployed contract
     */
    function deploy(bytes memory initCode, bytes32 salt) external returns (address payable deployed);
}
