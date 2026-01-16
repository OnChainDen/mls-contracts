// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {LibOrganizationGuardianStorage} from "organization/libraries/storage/LibOrganizationGuardianStorage.sol";
import {LibOrganizationRecoveryStorage} from "organization/libraries/storage/LibOrganizationRecoveryStorage.sol";

/**
 * @title Lib Organization Guardian Recovery
 * @dev Library for guardian recovery operations for Organization contracts.
 *      This library handles guardian-specific recovery functionality:
 *      - Recovery guardian updates (bypassing normal admin flow, with timelock)
 *
 *      The recovery flow uses SEPARATE storage from the normal guardian update flow.
 *      Both flows can run in parallel and are NOT mutually exclusive.
 *
 *      The flow is: initiate (starts timelock) → finalize (after timelock) → accept (new guardian confirms)
 *
 *      Separated from transaction recovery for cleaner code organization and easier auditing.
 * @author Den Technologies Inc
 */
library LibOrganizationGuardianRecovery {
    /**
     * @dev Initializes the guardian recovery configuration during organization initialization.
     *      This should be called from LibOrganizationInitialization.initialize().
     * @param guardianRecoveryAddress The guardian recovery address (must always be non-zero)
     * @param recoveryTimelockDuration The timelock duration in seconds (must be > 0)
     */
    function initializeGuardianRecovery(address guardianRecoveryAddress, uint256 recoveryTimelockDuration) internal {
        // Validate timelock duration
        if (recoveryTimelockDuration == 0) {
            revert IOrganizationGuardianRecovery.InvalidRecoveryTimelockDuration();
        }

        // Validate guardian recovery address (always required)
        if (guardianRecoveryAddress == address(0)) {
            revert IOrganizationGuardianRecovery.InvalidGuardianRecoveryAddress();
        }

        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();

        recoveryLayout.guardianRecoveryAddress = guardianRecoveryAddress;
        recoveryLayout.recoveryTimelockDuration = recoveryTimelockDuration;
    }

    /**
     * @dev Initiates a recovery guardian update (starts timelock).
     *      Uses recovery storage for pending state (separate from normal flow).
     * @param newGuardian The proposed new guardian address
     */
    function initiateRecoveryGuardianUpdate(address newGuardian) internal {
        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();

        // Case: Already a pending recovery guardian update
        if (recoveryLayout.recoveryPendingGuardian != address(0)) {
            revert IOrganizationGuardianRecovery.RecoveryGuardianUpdateAlreadyPending();
        }

        // Validate new guardian is not zero
        if (newGuardian == address(0)) {
            revert IOrganizationGuardianRecovery.InvalidNewGuardianAddress();
        }

        uint256 canFinalizeAt = block.timestamp + recoveryLayout.recoveryTimelockDuration;

        // Set pending state in recovery storage
        recoveryLayout.recoveryPendingGuardian = newGuardian;
        recoveryLayout.recoveryPendingGuardianTimestamp = canFinalizeAt;
        recoveryLayout.isRecoveryGuardianUpdateReadyForAcceptance = false;

        // Get current guardian for event
        address currentGuardian = LibOrganizationGuardianStorage.layout().guardian;

        emit IOrganizationGuardianRecovery.RecoveryGuardianUpdateInitiated(currentGuardian, newGuardian, canFinalizeAt);
    }

    /**
     * @dev Finalizes a recovery guardian update (after timelock, ready for new guardian to accept).
     *      Reverts if no recovery guardian update is pending or timelock has not expired.
     */
    function finalizeRecoveryGuardianUpdate() internal {
        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();

        // Case: No pending recovery guardian update
        if (recoveryLayout.recoveryPendingGuardian == address(0)) {
            revert IOrganizationGuardianRecovery.NoPendingRecoveryGuardianUpdate();
        }

        uint256 canFinalizeAt = recoveryLayout.recoveryPendingGuardianTimestamp;

        // Case: Timelock not expired
        if (block.timestamp < canFinalizeAt) {
            revert IOrganizationGuardianRecovery.GuardianRecoveryTimelockNotExpired(canFinalizeAt, block.timestamp);
        }

        // Mark as ready for acceptance (new guardian must call acceptGuardianRecovery)
        recoveryLayout.isRecoveryGuardianUpdateReadyForAcceptance = true;

        emit IOrganizationGuardianRecovery.RecoveryGuardianUpdateFinalized(recoveryLayout.recoveryPendingGuardian);
    }

    /**
     * @dev Cancels a pending recovery guardian update.
     *      Reverts if no recovery guardian update is pending.
     */
    function cancelRecoveryGuardianUpdate() internal {
        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();

        // Case: No pending recovery guardian update
        if (recoveryLayout.recoveryPendingGuardian == address(0)) {
            revert IOrganizationGuardianRecovery.NoPendingRecoveryGuardianUpdate();
        }

        address cancelledGuardian = recoveryLayout.recoveryPendingGuardian;

        // Clear all pending state
        recoveryLayout.recoveryPendingGuardian = address(0);
        recoveryLayout.recoveryPendingGuardianTimestamp = 0;
        recoveryLayout.isRecoveryGuardianUpdateReadyForAcceptance = false;

        emit IOrganizationGuardianRecovery.RecoveryGuardianUpdateCancelled(cancelledGuardian);
    }

    /**
     * @dev Accepts the guardian role via recovery flow (completes the recovery update).
     *      Can only be called by the recovery pending guardian after the update has been finalized.
     */
    function acceptGuardianRecovery() internal {
        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();

        address pendingGuardianAddr = recoveryLayout.recoveryPendingGuardian;

        // Case: No pending recovery guardian update
        if (pendingGuardianAddr == address(0)) {
            revert IOrganizationGuardianRecovery.NoPendingRecoveryGuardianUpdate();
        }

        // Case: Not ready for acceptance (finalize hasn't been called)
        if (!recoveryLayout.isRecoveryGuardianUpdateReadyForAcceptance) {
            revert IOrganizationGuardianRecovery.RecoveryGuardianUpdateNotReadyForAcceptance();
        }

        // Case: Caller is not the pending guardian
        if (msg.sender != pendingGuardianAddr) {
            // solhint-disable-next-line max-line-length
            revert IOrganizationGuardianRecovery.UnauthorizedRecoveryGuardianAcceptance(msg.sender, pendingGuardianAddr);
        }

        // Get current guardian for event
        LibOrganizationGuardianStorage.Layout storage guardianLayout = LibOrganizationGuardianStorage.layout();
        address previousGuardian = guardianLayout.guardian;

        // Update guardian in guardian storage
        guardianLayout.guardian = pendingGuardianAddr;

        // Clear all recovery pending state
        recoveryLayout.recoveryPendingGuardian = address(0);
        recoveryLayout.recoveryPendingGuardianTimestamp = 0;
        recoveryLayout.isRecoveryGuardianUpdateReadyForAcceptance = false;

        emit IOrganizationGuardianRecovery.RecoveryGuardianUpdateAccepted(previousGuardian, pendingGuardianAddr);
    }

    /**
     * @dev Enforces that the caller is the guardian recovery address.
     *      Reverts if msg.sender is not the guardian recovery address.
     */
    function enforceOnlyGuardianRecoveryAddress() internal view {
        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();
        address expected = recoveryLayout.guardianRecoveryAddress;

        if (msg.sender != expected) {
            revert IOrganizationGuardianRecovery.UnauthorizedGuardianRecoveryAddress(msg.sender, expected);
        }
    }

    /**
     * @dev Returns the guardian recovery address.
     * @return The recovery address
     */
    function getGuardianRecoveryAddress() internal view returns (address) {
        return LibOrganizationRecoveryStorage.layout().guardianRecoveryAddress;
    }

    /**
     * @dev Returns the recovery timelock duration in seconds.
     * @return The duration
     */
    function getRecoveryTimelockDuration() internal view returns (uint256) {
        return LibOrganizationRecoveryStorage.layout().recoveryTimelockDuration;
    }

    /**
     * @dev Returns the recovery pending guardian address.
     * @return The pending guardian address (zero if no pending recovery update)
     */
    function getRecoveryPendingGuardian() internal view returns (address) {
        return LibOrganizationRecoveryStorage.layout().recoveryPendingGuardian;
    }

    /**
     * @dev Returns the recovery pending guardian timestamp.
     * @return The timestamp when the recovery update can be finalized (0 if no pending)
     */
    function getRecoveryPendingGuardianTimestamp() internal view returns (uint256) {
        return LibOrganizationRecoveryStorage.layout().recoveryPendingGuardianTimestamp;
    }

    /**
     * @dev Checks if the recovery guardian update is ready for acceptance.
     * @return True if the recovery update has been finalized and is waiting for the new guardian to accept
     */
    function getIsRecoveryGuardianUpdateReadyForAcceptance() internal view returns (bool) {
        return LibOrganizationRecoveryStorage.layout().isRecoveryGuardianUpdateReadyForAcceptance;
    }
}
