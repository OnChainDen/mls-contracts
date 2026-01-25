// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

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
 *      - Only regular CALL operations (no delegate calls)
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
contract SafeExecutorModule {
    /// @notice The Safe this module is authorized to execute transactions for
    address public immutable SAFE;

    /// @notice The EOA authorized to execute transactions via this module
    address public immutable AUTHORIZED_EXECUTOR;

    /// @notice Error thrown when caller is not the authorized executor
    /// @param caller The address that attempted to call the function
    /// @param expected The authorized executor address
    error UnauthorizedCaller(address caller, address expected);

    /// @notice Error thrown when attempting to call the Safe itself
    /// @param target The target address that was blocked
    error CannotCallSafe(address target);

    /// @notice Error thrown when attempting to call the module itself
    /// @param target The target address that was blocked
    error CannotCallModule(address target);

    /// @notice Error thrown when the Safe execution fails
    error ExecutionFailed();

    /// @notice Error thrown when the Safe address is zero
    error SafeAddressCannotBeZero();

    /// @notice Error thrown when the executor address is zero
    error ExecutorAddressCannotBeZero();

    /**
     * @notice Initializes the module with the Safe address and authorized executor
     * @param safe The Safe multisig this module will execute transactions for
     * @param authorizedExecutor The EOA authorized to call executeOnBehalf
     */
    constructor(address safe, address authorizedExecutor) {
        if (safe == address(0)) {
            revert SafeAddressCannotBeZero();
        }
        if (authorizedExecutor == address(0)) {
            revert ExecutorAddressCannotBeZero();
        }

        SAFE = safe;
        AUTHORIZED_EXECUTOR = authorizedExecutor;
    }

    /**
     * @notice Executes a transaction on behalf of the Safe
     * @dev Only callable by the authorized executor. Enforces:
     *      - No calls to the Safe address (prevents ownership/module modifications)
     *      - No calls to this module (prevents self-modification attempts)
     *      - No ETH value transfers (hardcoded to 0)
     *      - No delegate calls (hardcoded to Call operation)
     * @param to The target contract address
     * @param data The calldata to execute
     * @return success Whether the execution succeeded
     */
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

        // Execute via Safe's execTransactionFromModule
        // Parameters: to, value (0), data, operation (0 = Call)
        success = ISafe(SAFE)
            .execTransactionFromModule(
                to,
                0, // value - always zero (no ETH transfers)
                data,
                0 // operation - always Call (no delegate calls)
            );

        // Case: Safe execution failed
        if (!success) {
            revert ExecutionFailed();
        }

        return success;
    }
}
