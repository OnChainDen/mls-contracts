// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

/**
 * @title ISafeExecutorModule
 * @notice Interface for the SafeExecutorModule contract
 * @dev A minimal Safe module that allows a single authorized address (the "Authorized Executor")
 *      to execute contract calls on behalf of a Safe multisig. The Authorized Executor
 *      (`AUTHORIZED_EXECUTOR`) may be either an EOA or a contract.
 *
 *      This module enforces the following restrictions:
 *      - Only CALL operations, except delegatecall is allowed ONLY to BatchedTransaction
 *      - No ETH value transfers (value must be zero)
 *      - No calls to the Safe itself (prevents ownership/module changes)
 *
 *      The Authorized Executor is immutable - to rotate, deploy a new module instance
 *      and have Safe owners swap modules via multisig transaction.
 *
 *      The module also implements ERC-1271 signature validation, allowing the
 *      AUTHORIZED_EXECUTOR to sign messages on behalf of the Guardian Safe.
 *      This enables ERC-1271 Account Signature validation without requiring
 *      Safe owner signatures. Because validation uses `SignatureUtils.tryRecoverSigner`,
 *      a contract Authorized Executor can sign via ERC-1271 just as an EOA Authorized
 *      Executor signs via ECDSA.
 *
 * @author Den Technologies Inc
 */
interface ISafeExecutorModule is IERC1271 {
    // Note: isValidSignature(bytes32,bytes) is inherited from IERC1271
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
    // solhint-disable-next-line func-name-mixedcase
    function SAFE() external view returns (address);

    /**
     * @notice Returns the address authorized to execute transactions via this module
     * @dev May be an EOA or a contract.
     * @return The authorized executor address
     */
    // solhint-disable-next-line func-name-mixedcase
    function AUTHORIZED_EXECUTOR() external view returns (address);

    /**
     * @notice Returns the BatchedTransaction contract address
     * @dev This is the only address that can be called via delegatecall
     * @return The BatchedTransaction address
     */
    // solhint-disable-next-line func-name-mixedcase
    function BATCHED_TRANSACTION() external view returns (address);
}
