// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title IOrganizationRecovery
 * @notice Interface for disaster recovery operations in Organization contracts
 * @dev Maps to LibOrganizationRecovery library functionality.
 *      Recovery allows users to withdraw funds and update guardians when the primary guardian is unavailable.
 * @author Den Technologies Inc
 */
interface IOrganizationRecovery {
    /**
     * @notice Emitted when transaction and ERC1271 recovery enable is initiated (timelock started)
     * @param canFinalizeAt The timestamp when the enable can be finalized
     */
    event TransactionAndERC1271RecoveryEnableInitiated(uint256 canFinalizeAt);

    /**
     * @notice Emitted when transaction and ERC1271 recovery is enabled (timelock completed)
     */
    event TransactionAndERC1271RecoveryEnableFinalized();

    /**
     * @notice Emitted when a pending transaction and ERC1271 recovery enable is cancelled
     */
    event TransactionAndERC1271RecoveryEnableCancelled();

    /**
     * @notice Emitted when transaction and ERC1271 recovery is disabled
     */
    event TransactionAndERC1271RecoveryDisabled();

    /**
     * @notice Emitted when guardian recovery enable is initiated (timelock started)
     * @param canFinalizeAt The timestamp when the enable can be finalized
     */
    event GuardianRecoveryEnableInitiated(uint256 canFinalizeAt);

    /**
     * @notice Emitted when guardian recovery is enabled (timelock completed)
     */
    event GuardianRecoveryEnableFinalized();

    /**
     * @notice Emitted when a pending guardian recovery enable is cancelled
     */
    event GuardianRecoveryEnableCancelled();

    /**
     * @notice Emitted when guardian recovery is disabled
     */
    event GuardianRecoveryDisabled();

    /**
     * @notice Emitted when a recovery account transaction is executed
     * @param account The account that executed the transaction
     * @param to The destination address
     * @param value The ETH value sent
     * @param data The transaction calldata
     */
    event RecoveryAccountTransactionExecuted(address indexed account, address indexed to, uint256 value, bytes data);

    /**
     * @notice Emitted when a recovery guardian update is initiated (timelock started)
     * @param currentGuardian The current guardian address
     * @param proposedGuardian The proposed new guardian address
     * @param canFinalizeAt The timestamp when the update can be finalized
     */
    event RecoveryGuardianUpdateInitiated(
        address indexed currentGuardian, address indexed proposedGuardian, uint256 canFinalizeAt
    );

    /**
     * @notice Emitted when a recovery guardian update timelock is completed (ready for acceptance)
     * @param proposedGuardian The proposed new guardian address
     */
    event RecoveryGuardianUpdateFinalized(address indexed proposedGuardian);

    /**
     * @notice Emitted when a pending recovery guardian update is cancelled
     * @param cancelledProposedGuardian The guardian address that was proposed but cancelled
     */
    event RecoveryGuardianUpdateCancelled(address indexed cancelledProposedGuardian);

    /**
     * @notice Thrown when recovery is not supported for transactions and ERC1271 signatures
     */
    error RecoveryNotSupportedForTransactionsAndERC1271();

    /**
     * @notice Thrown when recovery is not enabled for transactions and ERC1271 signatures
     */
    error RecoveryNotEnabledForTransactionsAndERC1271();

    /**
     * @notice Thrown when recovery is not enabled for guardian updates
     */
    error RecoveryNotEnabledForGuardianUpdate();

    /**
     * @notice Thrown when caller is not the authorized transaction recovery address
     * @param caller The address that attempted to call the function
     * @param expected The expected transaction recovery address
     */
    error UnauthorizedTxRecoveryAddress(address caller, address expected);

    /**
     * @notice Thrown when caller is not the authorized guardian recovery address
     * @param caller The address that attempted to call the function
     * @param expected The expected guardian recovery address
     */
    error UnauthorizedGuardianRecoveryAddress(address caller, address expected);

    /**
     * @notice Thrown when trying to finalize or cancel a recovery enable but none is pending
     */
    error NoRecoveryEnablePending();

    /**
     * @notice Thrown when trying to finalize a recovery enable before the timelock expires
     * @param canFinalizeAt The timestamp when finalization becomes possible
     * @param currentTime The current block timestamp
     */
    error RecoveryEnableTimelockNotExpired(uint256 canFinalizeAt, uint256 currentTime);

    /**
     * @notice Thrown when trying to initiate a recovery enable while one is already pending
     */
    error RecoveryEnableAlreadyPending();

    /**
     * @notice Thrown when the recovery timelock duration is invalid (zero)
     */
    error InvalidRecoveryTimelockDuration();

    /**
     * @notice Thrown when the transaction and ERC1271 recovery address is invalid
     */
    error InvalidTransactionAndERC1271RecoveryAddress();

    /**
     * @notice Thrown when the guardian recovery address is invalid (zero)
     */
    error InvalidGuardianRecoveryAddress();

    /**
     * @notice Thrown when trying to finalize a non-recovery guardian update via recovery flow
     */
    error NotARecoveryGuardianUpdate();

    /**
     * @notice Thrown when trying to cancel a non-recovery guardian update via recovery flow
     */
    error CannotCancelNonRecoveryGuardianUpdate();

    /**
     * @notice Initiates enabling transaction and ERC1271 recovery (starts timelock)
     * @dev Can only be called by the transaction recovery address.
     *      Recovery must be supported for this to work.
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
     */
    function disableTransactionAndERC1271Recovery() external;

    /**
     * @notice Initiates enabling guardian recovery (starts timelock)
     * @dev Can only be called by the guardian recovery address.
     */
    function initiateEnableGuardianRecovery() external;

    /**
     * @notice Finalizes enabling guardian recovery (after timelock)
     * @dev Can only be called by the guardian recovery address after timelock expires.
     */
    function finalizeEnableGuardianRecovery() external;

    /**
     * @notice Cancels a pending guardian recovery enable
     * @dev Can only be called by the guardian recovery address.
     */
    function cancelEnableGuardianRecovery() external;

    /**
     * @notice Immediately disables guardian recovery
     * @dev Can only be called by the guardian recovery address. No timelock required.
     */
    function disableGuardianRecovery() external;

    /**
     * @notice Executes an account transaction via recovery (bypassing guardian and policy checks)
     * @dev Can only be called by the transaction recovery address.
     *      Recovery must be both supported AND enabled.
     * @param account The account to execute the transaction from
     * @param to The destination address
     * @param value The ETH value to send
     * @param data The transaction calldata
     */
    // solhint-disable-next-line max-line-length
    function executeRecoveryAccountTransaction(address account, address to, uint256 value, bytes calldata data) external;

    /**
     * @notice Initiates a recovery guardian update (starts timelock)
     * @dev Can only be called by the guardian recovery address.
     *      Guardian recovery must be enabled.
     * @param newGuardian The proposed new guardian address
     */
    function initiateRecoveryGuardianUpdate(address newGuardian) external;

    /**
     * @notice Finalizes a recovery guardian update (after timelock, ready for new guardian to accept)
     * @dev Can only be called by the guardian recovery address after timelock expires.
     */
    function finalizeRecoveryGuardianUpdate() external;

    /**
     * @notice Cancels a pending recovery guardian update
     * @dev Can only be called by the guardian recovery address.
     */
    function cancelRecoveryGuardianUpdate() external;

    /**
     * @notice Returns whether recovery is supported for transactions and ERC1271 signatures
     * @return True if recovery is supported, false otherwise
     */
    function isRecoverySupportedForTransactionsAndERC1271() external view returns (bool);

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
     * @notice Returns whether recovery is enabled for guardian updates
     * @return True if recovery is enabled, false otherwise
     */
    function isRecoveryEnabledForGuardianUpdate() external view returns (bool);

    /**
     * @notice Returns the guardian recovery address
     * @return The recovery address
     */
    function guardianRecoveryAddress() external view returns (address);

    /**
     * @notice Returns the recovery timelock duration in seconds
     * @return The timelock duration
     */
    function recoveryTimelockDuration() external view returns (uint256);

    /**
     * @notice Returns the timestamp when pending tx recovery enable can be finalized
     * @return The timestamp (0 if no pending request)
     */
    function pendingTxRecoveryEnableTimestamp() external view returns (uint256);

    /**
     * @notice Returns the timestamp when pending guardian recovery enable can be finalized
     * @return The timestamp (0 if no pending request)
     */
    function pendingGuardianRecoveryEnableTimestamp() external view returns (uint256);
}
