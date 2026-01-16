// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title IOrganizationGuardianRecovery
 * @notice Interface for guardian recovery operations in Organization contracts
 * @dev Maps to LibOrganizationGuardianRecovery library functionality.
 *      Guardian recovery allows users to update the guardian address when the
 *      primary guardian is unavailable.
 *
 *      The recovery flow uses SEPARATE storage from the normal guardian update flow.
 *      Both flows can run in parallel and are NOT mutually exclusive.
 * @author Den Technologies Inc
 */
interface IOrganizationGuardianRecovery {
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
     * @notice Emitted when a new guardian accepts and the recovery update is completed
     * @param previousGuardian The previous guardian address
     * @param newGuardian The new guardian address
     */
    event RecoveryGuardianUpdateAccepted(address indexed previousGuardian, address indexed newGuardian);

    /**
     * @notice Thrown when the recovery timelock duration is invalid (zero)
     */
    error InvalidRecoveryTimelockDuration();

    /**
     * @notice Thrown when the guardian recovery address is invalid (zero)
     */
    error InvalidGuardianRecoveryAddress();

    /**
     * @notice Thrown when the new guardian address is invalid (zero)
     */
    error InvalidNewGuardianAddress();

    /**
     * @notice Thrown when caller is not the authorized guardian recovery address
     * @param caller The address that attempted to call the function
     * @param expected The expected guardian recovery address
     */
    error UnauthorizedGuardianRecoveryAddress(address caller, address expected);

    /**
     * @notice Thrown when trying to finalize or cancel a guardian recovery enable but none is pending
     */
    error NoGuardianRecoveryEnablePending();

    /**
     * @notice Thrown when trying to finalize a guardian recovery enable before the timelock expires
     * @param canFinalizeAt The timestamp when finalization becomes possible
     * @param currentTime The current block timestamp
     */
    error GuardianRecoveryTimelockNotExpired(uint256 canFinalizeAt, uint256 currentTime);

    /**
     * @notice Thrown when trying to initiate a guardian recovery enable while one is already pending
     */
    error GuardianRecoveryEnableAlreadyPending();

    /**
     * @notice Thrown when guardian recovery is not enabled
     */
    error GuardianRecoveryNotEnabled();

    /**
     * @notice Thrown when there's no pending recovery guardian update
     */
    error NoPendingRecoveryGuardianUpdate();

    /**
     * @notice Thrown when trying to initiate a recovery guardian update while one is already pending
     */
    error RecoveryGuardianUpdateAlreadyPending();

    /**
     * @notice Thrown when trying to accept a recovery guardian update but it's not ready for acceptance
     */
    error RecoveryGuardianUpdateNotReadyForAcceptance();

    /**
     * @notice Thrown when a non-pending-guardian tries to accept the guardian role via recovery
     * @param caller The address that attempted to accept
     * @param pendingGuardian The address that should accept
     */
    error UnauthorizedRecoveryGuardianAcceptance(address caller, address pendingGuardian);

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
     * @notice Accepts the guardian role via recovery (completes the recovery update)
     * @dev Can only be called by the recovery pending guardian after the update has been finalized.
     */
    function acceptGuardianRecovery() external;

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
     * @notice Returns the timestamp when pending guardian recovery enable can be finalized
     * @return The timestamp (0 if no pending request)
     */
    function pendingGuardianRecoveryEnableTimestamp() external view returns (uint256);

    /**
     * @notice Returns the recovery pending guardian address
     * @return The pending guardian address (zero if no pending recovery update)
     */
    function recoveryPendingGuardian() external view returns (address);

    /**
     * @notice Returns the recovery pending guardian timestamp
     * @return The timestamp when the recovery update can be finalized (0 if no pending)
     */
    function recoveryPendingGuardianTimestamp() external view returns (uint256);

    /**
     * @notice Returns whether the recovery guardian update is ready for acceptance
     * @return True if the recovery update has been finalized and is waiting for the new guardian to accept
     */
    function isRecoveryGuardianUpdateReadyForAcceptance() external view returns (bool);
}
