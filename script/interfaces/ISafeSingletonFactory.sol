// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

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
     * @return deployedAddress The address of the deployed contract
     */
    function deploy(bytes memory initCode, bytes32 salt) external returns (address payable deployedAddress);
}
