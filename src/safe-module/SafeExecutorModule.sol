// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {ISafeExecutorModule} from "../interfaces/ISafeExecutorModule.sol";

/// @notice Minimal interface for Safe module execution
interface ISafe {
    /// @notice Executes a transaction from a module
    /// @param to Target address
    /// @param value ETH value to send
    /// @param data Calldata
    /// @param operation 0 = Call, 1 = DelegateCall
    /// @return success Whether the execution succeeded
    function execTransactionFromModule(address to, uint256 value, bytes memory data, uint8 operation)
        external
        returns (bool success);
}

/**
 * @title SafeExecutorModule
 * @notice A minimal Safe module that allows a single authorized EOA (the "Safe Executor EOA")
 *         to execute contract calls on behalf of a Safe multisig.
 * @dev This module enforces the following restrictions:
 *      - Only CALL operations, except delegatecall is allowed ONLY to MultiSendCallOnly
 *      - No ETH value transfers (value must be zero)
 *      - No calls to the Safe itself (prevents ownership/module changes)
 *      - No calls to the module itself
 *
 *      The Safe Executor EOA is immutable - to rotate, deploy a new module instance
 *      and have Safe owners swap modules via multisig transaction.
 *
 *      Safe v1.3.0 emits ExecutionFromModuleSuccess/ExecutionFromModuleFailure
 *      events when transactions are executed via modules, so this contract does
 *      not emit additional events.
 *
 * @author Den Technologies Inc
 */
contract SafeExecutorModule is ISafeExecutorModule {
    /// @inheritdoc ISafeExecutorModule
    address public immutable SAFE;

    /// @inheritdoc ISafeExecutorModule
    address public immutable AUTHORIZED_EXECUTOR;

    /// @inheritdoc ISafeExecutorModule
    address public immutable MULTI_SEND_CALL_ONLY;

    /**
     * @notice Initializes the module with the Safe address, authorized executor, and MultiSendCallOnly
     * @param safe The Safe multisig this module will execute transactions for
     * @param authorizedExecutor The EOA authorized to call executeOnBehalf
     * @param multiSendCallOnly The MultiSendCallOnly contract address (only target allowed for delegatecall)
     */
    constructor(address safe, address authorizedExecutor, address multiSendCallOnly) {
        if (safe == address(0)) {
            revert SafeAddressCannotBeZero();
        }
        if (authorizedExecutor == address(0)) {
            revert ExecutorAddressCannotBeZero();
        }
        if (multiSendCallOnly == address(0)) {
            revert MultiSendCallOnlyAddressCannotBeZero();
        }

        SAFE = safe;
        AUTHORIZED_EXECUTOR = authorizedExecutor;
        MULTI_SEND_CALL_ONLY = multiSendCallOnly;
    }

    /// @inheritdoc ISafeExecutorModule
    function executeOnBehalf(address to, bytes calldata data) external returns (bool success) {
        // Case: Caller is not the authorized executor
        if (msg.sender != AUTHORIZED_EXECUTOR) {
            revert UnauthorizedCaller(msg.sender, AUTHORIZED_EXECUTOR);
        }

        // Case: Target is the Safe itself (prevents ownership/module modifications)
        if (to == SAFE) {
            revert CannotCallSafe(to);
        }

        // Case: Target is this module (prevents self-modification attempts)
        if (to == address(this)) {
            revert CannotCallModule(to);
        }

        // Determine operation type:
        // - DelegateCall (1) is ONLY allowed when target is MultiSendCallOnly
        // - Call (0) is used for all other targets
        uint8 operation = (to == MULTI_SEND_CALL_ONLY) ? 1 : 0;

        // Execute via Safe's execTransactionFromModule
        // Parameters: to, value (0), data, operation
        success = ISafe(SAFE)
            .execTransactionFromModule(
                to,
                0, // value - always zero (no ETH transfers)
                data,
                operation
            );

        // Case: Safe execution failed
        if (!success) {
            revert ExecutionFailed();
        }

        return success;
    }
}
