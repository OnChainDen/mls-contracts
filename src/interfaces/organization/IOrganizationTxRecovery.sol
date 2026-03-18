// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {AdminAuthParams} from "types/AdminTypes.sol";
import {TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @title IOrganizationTxRecovery
 * @notice Interface for transaction and ERC1271 recovery operations in Organization contracts
 * @dev Maps to LibOrganizationTxRecovery library functionality.
 *      Transaction recovery allows users to execute account transactions and validate
 *      ERC1271 signatures when the primary guardian is unavailable.
 * @author Den Technologies Inc
 */
interface IOrganizationTxRecovery {
    /**
     * @notice Emitted when transaction recovery enable is initiated (timelock started)
     * @param canFinalizeAtTimestamp The timestamp when the enable can be finalized
     */
    // solhint-disable-next-line gas-indexed-events
    event TxRecoveryEnableInitiated(uint256 canFinalizeAtTimestamp);

    /**
     * @notice Emitted when transaction recovery is enabled (timelock completed)
     */
    event TxRecoveryEnableFinalized();

    /**
     * @notice Emitted when a pending transaction recovery enable is cancelled
     */
    event TxRecoveryEnableCancelled();

    /**
     * @notice Emitted when transaction recovery is disabled
     */
    event TxRecoveryDisabled();

    /**
     * @notice Emitted when a recovery account transaction is executed
     * @param account The account that executed the transaction
     * @param to The destination address
     * @param value The ETH value sent
     * @param data The transaction calldata
     */
    // solhint-disable-next-line gas-indexed-events
    event RecoveryAccountTransactionExecuted(address indexed account, address indexed to, uint256 value, bytes data);

    /**
     * @notice Emitted when deferred transaction recovery initialization is initiated (timelock started)
     * @param recoveryAddress The proposed recovery address
     * @param timelockDurationSeconds The proposed timelock duration in seconds
     * @param canFinalizeAtTimestamp The timestamp when the initialization can be finalized
     */
    // solhint-disable-next-line gas-indexed-events
    event TxRecoveryInitializationInitiated(
        address indexed recoveryAddress, uint256 timelockDurationSeconds, uint256 canFinalizeAtTimestamp
    );

    /**
     * @notice Emitted when deferred transaction recovery initialization is finalized
     * @param recoveryAddress The configured recovery address
     * @param timelockDurationSeconds The configured timelock duration in seconds
     */
    // solhint-disable-next-line gas-indexed-events
    event TxRecoveryInitializationFinalized(address indexed recoveryAddress, uint256 timelockDurationSeconds);

    /**
     * @notice Emitted when a pending deferred transaction recovery initialization is cancelled
     */
    event TxRecoveryInitializationCancelled();

    /**
     * @notice Thrown when transaction recovery is not configured (no recovery address set)
     */
    error TxRecoveryNotConfigured();

    /**
     * @notice Thrown when transaction recovery is not enabled
     */
    error TxRecoveryNotEnabled();

    /**
     * @notice Thrown when the transaction recovery address is invalid
     */
    error InvalidTxRecoveryAddress();

    /**
     * @notice Thrown when caller is not the authorized transaction recovery address
     * @param caller The address that attempted to call the function
     * @param expected The expected transaction recovery address
     */
    error UnauthorizedTxRecoveryAddress(address caller, address expected);

    /**
     * @notice Thrown when trying to finalize or cancel a tx recovery enable but none is pending
     */
    error NoTxRecoveryEnablePending();

    /**
     * @notice Thrown when trying to initiate a tx recovery enable while one is already pending
     */
    error TxRecoveryEnableAlreadyPending();

    /**
     * @notice Thrown when trying to initiate a tx recovery enable while recovery is already enabled
     */
    error TxRecoveryAlreadyEnabled();

    /**
     * @notice Thrown when trying to setup transaction recovery but it has already been configured
     */
    error TransactionRecoveryAlreadyConfigured();

    /**
     * @notice Thrown when trying to initiate deferred initialization while one is already pending
     */
    error TxRecoveryInitializationAlreadyPending();

    /**
     * @notice Thrown when trying to finalize or cancel deferred initialization but none is pending
     */
    error NoTxRecoveryInitializationPending();

    /**
     * @notice Initiates enabling transaction and ERC1271 recovery (starts timelock)
     * @dev Can only be called by the transaction recovery address.
     *      Recovery must be configured for this to work.
     */
    function initiateEnableTransactionAndERC1271Recovery() external;

    /**
     * @notice Finalizes enabling transaction and ERC1271 recovery (after timelock)
     * @dev Can only be called by the transaction recovery address after timelock expires.
     */
    function finalizeEnableTransactionAndERC1271Recovery() external;

    /**
     * @notice Cancels a pending transaction and ERC1271 recovery enable
     * @dev Can only be called by the transaction recovery address.
     */
    function cancelEnableTransactionAndERC1271Recovery() external;

    /**
     * @notice Immediately disables transaction and ERC1271 recovery
     * @dev Can only be called by the transaction recovery address. No timelock required.
     *      Also cancels any pending enable request, even if the timelock has already expired.
     *      This ensures recovery is fully disabled.
     */
    function disableTransactionAndERC1271Recovery() external;

    /**
     * @notice Executes an account transaction via recovery (bypassing guardian and policy checks)
     * @dev Can only be called by the transaction recovery address.
     *      Recovery must be configured and enabled.
     * @param account The account to execute the transaction from
     * @param to The destination address
     * @param value The ETH value to send
     * @param data The transaction calldata
     */
    // forgefmt: disable-next-item
    function executeRecoveryAccountTransaction(
        address account, 
        address to, 
        uint256 value, 
        bytes calldata data
    ) external;

    /**
     * @notice Initiates deferred initialization of transaction and ERC1271 recovery (starts timelock)
     * @dev Can only be called by the guardian with admin authorization.
     *      Reverts if transaction recovery is already configured or if an initialization is already pending.
     * @param recoveryAddress The proposed recovery address
     * @param timelockDurationSeconds The proposed timelock duration in seconds for enabling recovery
     * @param authParams The admin authorization parameters (signatures, proofs, etc.)
     */
    function initiateInitializeTransactionAndERC1271Recovery(
        address recoveryAddress,
        uint256 timelockDurationSeconds,
        AdminAuthParams calldata authParams
    ) external;

    /**
     * @notice Finalizes deferred initialization of transaction and ERC1271 recovery (after timelock)
     * @dev Can only be called by the guardian with admin authorization after timelock expires.
     * @param authParams The admin authorization parameters (signatures, proofs, etc.)
     */
    function finalizeInitializeTransactionAndERC1271Recovery(AdminAuthParams calldata authParams) external;

    /**
     * @notice Cancels a pending deferred initialization of transaction and ERC1271 recovery
     * @dev Can only be called by the guardian with admin authorization.
     * @param authParams The admin authorization parameters (signatures, proofs, etc.)
     */
    function cancelInitializeTransactionAndERC1271Recovery(AdminAuthParams calldata authParams) external;

    /**
     * @notice Self-call execution step for initiateInitializeTransactionAndERC1271Recovery
     * @dev Restricted to self-calls only (onlySelf modifier). Called via low-level `address(this).call()`
     *      from `initiateInitializeTransactionAndERC1271Recovery` to isolate execution reverts from the
     *      outer call frame, ensuring the nonce remains consumed even if the state change fails.
     * @param recoveryAddress The proposed recovery address
     * @param timelockDurationSeconds The proposed timelock duration in seconds for enabling recovery
     */
    function executeInitiateInitializeTxRecovery(address recoveryAddress, uint256 timelockDurationSeconds) external;

    /**
     * @notice Self-call execution step for finalizeInitializeTransactionAndERC1271Recovery
     * @dev Restricted to self-calls only (onlySelf modifier). Called via low-level `address(this).call()`
     *      from `finalizeInitializeTransactionAndERC1271Recovery` to isolate execution reverts from the
     *      outer call frame, ensuring the nonce remains consumed even if the state change fails.
     */
    function executeFinalizeInitializeTxRecovery() external;

    /**
     * @notice Self-call execution step for cancelInitializeTransactionAndERC1271Recovery
     * @dev Restricted to self-calls only (onlySelf modifier). Called via low-level `address(this).call()`
     *      from `cancelInitializeTransactionAndERC1271Recovery` to isolate execution reverts from the
     *      outer call frame, ensuring the nonce remains consumed even if the state change fails.
     */
    function executeCancelInitializeTxRecovery() external;

    /**
     * @notice Returns the full transaction recovery state
     * @return The TxRecoveryState struct containing all recovery configuration and pending state
     */
    function getTxRecoveryState() external view returns (TxRecoveryState memory);
}
