// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

/**
 * @title ISafeExecutorModule
 * @notice Interface for the SafeExecutorModule contract
 * @dev A minimal Safe module that allows a single authorized EOA (the "Safe Executor EOA")
 *      to execute contract calls on behalf of a Safe multisig.
 *
 *      This module enforces the following restrictions:
 *      - Only CALL operations, except delegatecall is allowed ONLY to BatchedTransaction
 *      - No ETH value transfers (value must be zero)
 *      - No calls to the Safe itself (prevents ownership/module changes)
 *
 *      The Safe Executor EOA is immutable - to rotate, deploy a new module instance
 *      and have Safe owners swap modules via multisig transaction.
 *
 * @author Den Technologies Inc
 */
interface ISafeExecutorModule {
    /// @notice Error thrown when caller is not the authorized executor
    /// @param caller The address that attempted to call the function
    /// @param expected The authorized executor address
    error UnauthorizedCaller(address caller, address expected);

    /// @notice Error thrown when attempting to call the Safe itself
    /// @param target The target address that was blocked
    error CannotCallSafe(address target);

    /// @notice Error thrown when the Safe execution fails
    error ExecutionFailed();

    /// @notice Error thrown when the Safe address is zero
    error SafeAddressCannotBeZero();

    /// @notice Error thrown when the executor address is zero
    error ExecutorAddressCannotBeZero();

    /// @notice Error thrown when the BatchedTransaction address is zero
    error BatchedTransactionAddressCannotBeZero();

    /**
     * @notice Executes a transaction on behalf of the Safe
     * @dev Only callable by the authorized executor. Enforces:
     *      - No calls to the Safe address (prevents ownership/module modifications)
     *      - No ETH value transfers (hardcoded to 0)
     *      - Uses CALL for all targets except BatchedTransaction (which uses DELEGATECALL)
     * @param to The target contract address
     * @param data The calldata to execute
     * @return success Whether the execution succeeded
     */
    function executeOnBehalf(address to, bytes calldata data) external returns (bool success);

    /**
     * @notice Returns the Safe this module is authorized to execute transactions for
     * @return The Safe address
     */
    function SAFE() external view returns (address);

    /**
     * @notice Returns the EOA authorized to execute transactions via this module
     * @return The authorized executor address
     */
    function AUTHORIZED_EXECUTOR() external view returns (address);

    /**
     * @notice Returns the BatchedTransaction contract address
     * @dev This is the only address that can be called via delegatecall
     * @return The BatchedTransaction address
     */
    function BATCHED_TRANSACTION() external view returns (address);
}
