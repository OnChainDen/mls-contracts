// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {ISafeExecutorModule} from "../interfaces/ISafeExecutorModule.sol";
import {SignatureUtils} from "../libraries/SignatureUtils.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

/// @notice Minimal interface for Safe module execution and module queries
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

    /// @notice Checks if a module is enabled on the Safe
    /// @param module The module address to check
    /// @return True if the module is enabled, false otherwise
    function isModuleEnabled(address module) external view returns (bool);
}

/**
 * @title SafeExecutorModule
 * @notice A minimal Safe module that allows a single authorized EOA (the "Safe Executor EOA")
 *         to execute contract calls on behalf of a Safe multisig.
 * @dev This module enforces the following restrictions:
 *      - Only CALL operations, except delegatecall is allowed ONLY to BatchedTransaction
 *      - No ETH value transfers (value must be zero)
 *      - No calls to the Safe itself (prevents ownership/module changes)
 *
 *      The Safe Executor EOA is immutable - to rotate, deploy a new module instance
 *      and have Safe owners swap modules via multisig transaction.
 *
 *      Safe v1.4.1 emits ExecutionFromModuleSuccess/ExecutionFromModuleFailure
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
    address public immutable BATCHED_TRANSACTION;

    /**
     * @notice Initializes the module with the Safe address, authorized executor, and BatchedTransaction
     * @param safe The Safe multisig this module will execute transactions for
     * @param authorizedExecutor The EOA authorized to call executeOnBehalf
     * @param batchedTransaction The BatchedTransaction contract address (only target allowed for delegatecall)
     */
    constructor(address safe, address authorizedExecutor, address batchedTransaction) {
        if (safe == address(0)) {
            revert SafeAddressCannotBeZero();
        }
        if (authorizedExecutor == address(0)) {
            revert ExecutorAddressCannotBeZero();
        }
        if (batchedTransaction == address(0)) {
            revert BatchedTransactionAddressCannotBeZero();
        }

        SAFE = safe;
        AUTHORIZED_EXECUTOR = authorizedExecutor;
        BATCHED_TRANSACTION = batchedTransaction;
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

        // Determine operation type:
        // - DelegateCall (1) is ONLY allowed when target is BatchedTransaction
        // - Call (0) is used for all other targets
        uint8 operation = (to == BATCHED_TRANSACTION) ? 1 : 0;

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

    /// @inheritdoc IERC1271
    /// @dev Validates that the signature was created by the AUTHORIZED_EXECUTOR.
    ///      This allows the module to act as an ERC-1271 signer for the Guardian Safe,
    ///      enabling ERC-1271 Account Signature validation without Safe owner signatures.
    ///      Uses the universal signature encoding format from SignatureUtils:
    ///      - EOA signatures: | v (1) | r (32) | s (32) | = 65 bytes
    ///      - ERC-1271 signatures: | 0 (1) | signer (20) | length (2) | signature (N) | = 23 + N bytes
    function isValidSignature(bytes32 hash, bytes calldata signature) external view override returns (bytes4) {
        // Use SignatureUtils to recover the signer (supports both EOA and ERC-1271 formats)
        (bool success, address recovered) = SignatureUtils.tryRecoverSigner(signature, hash);

        // Case: Signature recovery failed
        if (!success) {
            return SignatureUtils.ERC1271_INVALID_VALUE;
        }

        // Case: Signature is from the authorized executor
        if (recovered == AUTHORIZED_EXECUTOR) {
            return SignatureUtils.ERC1271_MAGIC_VALUE;
        }

        // Case: Signature is not from the authorized executor
        return SignatureUtils.ERC1271_INVALID_VALUE;
    }
}
