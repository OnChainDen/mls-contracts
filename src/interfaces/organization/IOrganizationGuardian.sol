// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {AdminAuthParams} from "types/AdminTypes.sol";

/**
 * @title IOrganizationGuardian
 * @notice Interface for guardian-related operations in Organization contracts (normal flow)
 * @dev Maps to LibOrganizationGuardian library functionality.
 *      Guardian updates follow a timelocked 3-step flow: initiate → finalize → accept.
 *      This interface handles the NORMAL guardian update flow only.
 *      Recovery guardian updates use IOrganizationGuardianRecovery with separate state.
 * @author Den Technologies Inc
 */
interface IOrganizationGuardian {
    /**
     * @notice Emitted when a guardian update is initiated (timelock started)
     * @param currentGuardian The current guardian address
     * @param proposedGuardian The proposed new guardian address
     * @param canFinalizeAtTimestamp The timestamp when the update can be finalized
     */
    // solhint-disable-next-line gas-indexed-events
    event GuardianUpdateInitiated(
        address indexed currentGuardian, address indexed proposedGuardian, uint256 canFinalizeAtTimestamp
    );

    /**
     * @notice Emitted when a guardian update timelock is completed (ready for acceptance)
     * @param proposedGuardian The proposed new guardian address
     */
    event GuardianUpdateFinalized(address indexed proposedGuardian);

    /**
     * @notice Emitted when a new guardian accepts and the update is completed
     * @param previousGuardian The previous guardian address
     * @param newGuardian The new guardian address
     */
    event GuardianUpdateAccepted(address indexed previousGuardian, address indexed newGuardian);

    /**
     * @notice Emitted when a pending guardian update is cancelled
     * @param currentGuardian The current guardian address
     * @param cancelledProposedGuardian The guardian address that was proposed but cancelled
     */
    event GuardianUpdateCancelled(address indexed currentGuardian, address indexed cancelledProposedGuardian);

    /**
     * @notice Thrown when attempting to set the guardian to the zero address
     */
    error InvalidGuardianAddress();

    /**
     * @notice Thrown when the guardian timelock duration is invalid (zero)
     */
    error InvalidGuardianTimelockDuration();

    /**
     * @notice Thrown when a function is called by an unauthorized address (not the guardian)
     * @param caller The address that attempted to call the function
     * @param guardian The current guardian address
     */
    error UnauthorizedGuardian(address caller, address guardian);

    /**
     * @notice Thrown when trying to finalize, cancel, or accept but no guardian update is pending
     */
    error NoPendingGuardianUpdate();

    /**
     * @notice Thrown when trying to accept but the guardian update is not ready for acceptance
     */
    error GuardianUpdateNotReadyForAcceptance();

    /**
     * @notice Thrown when a non-pending-guardian tries to accept the guardian role
     * @param caller The address that attempted to accept
     * @param pendingGuardian The address that should accept
     */
    error UnauthorizedGuardianAcceptance(address caller, address pendingGuardian);

    /**
     * @notice Thrown when trying to finalize a guardian update before the timelock expires
     * @param canFinalizeAtTimestamp The timestamp when finalization becomes possible
     * @param currentTime The current block timestamp
     */
    error GuardianUpdateTimelockNotExpired(uint256 canFinalizeAtTimestamp, uint256 currentTime);

    /**
     * @notice Thrown when trying to initiate a guardian update while one is already pending
     */
    error GuardianUpdateAlreadyPending();

    /**
     * @notice Initiates a guardian update (starts timelock)
     * @dev Can only be called by the current guardian with admin authorization.
     * @param newGuardian The proposed new guardian address
     * @param authParams The authorization parameters (salt, expiration, signatures, and admin proofs)
     */
    function initiateGuardianUpdate(address newGuardian, AdminAuthParams calldata authParams) external;

    /**
     * @notice Finalizes a guardian update (after timelock, ready for new guardian to accept)
     * @dev Can only be called by the current guardian with admin authorization after timelock expires.
     * @param authParams The authorization parameters (salt, expiration, signatures, and admin proofs)
     */
    function finalizeGuardianUpdate(AdminAuthParams calldata authParams) external;

    /**
     * @notice Cancels a pending guardian update
     * @dev Can only be called by the current guardian with admin authorization.
     * @param authParams The authorization parameters (salt, expiration, signatures, and admin proofs)
     */
    function cancelGuardianUpdate(AdminAuthParams calldata authParams) external;

    /**
     * @notice Accepts the guardian role (completes the normal flow update)
     * @dev Can only be called by the pending guardian after the update has been finalized.
     */
    function acceptGuardian() external;

    /**
     * @notice Returns the current guardian address
     * @return The address of the guardian
     */
    function guardian() external view returns (address);

    /**
     * @notice Returns the pending guardian address (normal flow)
     * @return The address of the pending guardian (zero if no pending update)
     */
    function pendingGuardian() external view returns (address);

    /**
     * @notice Returns the timestamp when the pending guardian update can be finalized (normal flow)
     * @return The timestamp (0 if no pending update)
     */
    function pendingGuardianUpdateTimestamp() external view returns (uint256);

    /**
     * @notice Returns whether the guardian update is ready for acceptance (normal flow)
     * @return True if the update has been finalized and is waiting for the new guardian to accept
     */
    function isGuardianUpdateReadyForAcceptance() external view returns (bool);

    /**
     * @notice Returns the guardian timelock duration in seconds
     * @return The timelock duration
     */
    function guardianTimelockDuration() external view returns (uint256);
}
