// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {AdminAuthParams} from "types/AdminTypes.sol";

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
     * @notice Emitted when transaction recovery is configured for the first time after deployment
     * @param recoveryAddress The configured recovery address
     * @param timelockDurationSeconds The timelock duration in seconds
     */
    // solhint-disable-next-line gas-indexed-events
    event TransactionRecoveryConfigured(address indexed recoveryAddress, uint256 timelockDurationSeconds);

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
     * @notice Thrown when trying to finalize a tx recovery enable before the timelock expires
     * @param canFinalizeAtTimestamp The timestamp when finalization becomes possible
     * @param currentTime The current block timestamp
     */
    error TxRecoveryTimelockNotExpired(uint256 canFinalizeAtTimestamp, uint256 currentTime);

    /**
     * @notice Thrown when trying to initiate a tx recovery enable while one is already pending
     */
    error TxRecoveryEnableAlreadyPending();

    /**
     * @notice Thrown when trying to initiate a tx recovery enable while recovery is already enabled
     */
    error TxRecoveryAlreadyEnabled();

    /**
     * @notice Thrown when the tx recovery timelock duration is invalid (zero)
     */
    error InvalidTxRecoveryTimelockDurationSeconds();

    /**
     * @notice Thrown when trying to setup transaction recovery but it has already been configured
     */
    error TransactionRecoveryAlreadyConfigured();

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
     * @notice Initializes transaction and ERC1271 recovery for the first time after organization deployment
     * @dev Can only be called by the guardian with admin authorization.
     *      Can only be called once - reverts if transaction recovery is already configured.
     * @param recoveryAddress The address that will be authorized to perform recovery
     * @param timelockDurationSeconds The timelock duration in seconds for enabling recovery
     * @param authParams The admin authorization parameters (signatures, proofs, etc.)
     */
    function initializeTransactionAndERC1271Recovery(
        address recoveryAddress,
        uint256 timelockDurationSeconds,
        AdminAuthParams calldata authParams
    ) external;

    /**
     * @notice Returns whether recovery is enabled for transactions and ERC1271 signatures
     * @return True if recovery is enabled, false otherwise
     */
    function isRecoveryEnabledForTransactionsAndERC1271() external view returns (bool);

    /**
     * @notice Returns the transaction and ERC1271 recovery address
     * @return The recovery address
     */
    function transactionAndERC1271RecoveryAddress() external view returns (address);

    /**
     * @notice Returns the timestamp when pending tx recovery enable can be finalized
     * @return The timestamp (0 if no pending request)
     */
    function pendingTxRecoveryEnableTimestamp() external view returns (uint256);

    /**
     * @notice Returns the tx recovery timelock duration in seconds
     * @return The timelock duration
     */
    function txRecoveryTimelockDurationSeconds() external view returns (uint256);
}
