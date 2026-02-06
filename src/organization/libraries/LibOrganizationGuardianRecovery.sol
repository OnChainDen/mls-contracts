// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {LibOrganizationGuardianStorage} from "organization/libraries/storage/LibOrganizationGuardianStorage.sol";
import {LibOrganizationRecoveryStorage} from "organization/libraries/storage/LibOrganizationRecoveryStorage.sol";
import {
    LibOrganizationSecureTimelockStorage
} from "organization/libraries/storage/LibOrganizationSecureTimelockStorage.sol";

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
     * @dev Initializes guardian recovery configuration. Used both during org initialization and post-deployment setup.
     *      - If already configured, reverts
     *      - Otherwise, validates address and timelock duration and writes to storage
     *
     *      Note: Event emission is handled by the caller (OrganizationGuardianRecoveryBase)
     *      for post-deployment setup only.
     * @param guardianRecoveryAddress The guardian recovery address
     * @param guardianRecoveryTimelockDurationSeconds The timelock duration in seconds
     */
    function initializeGuardianRecovery(
        address guardianRecoveryAddress,
        uint256 guardianRecoveryTimelockDurationSeconds
    ) internal {
        LibOrganizationRecoveryStorage.GuardianRecoveryState storage
            guardianRecoveryLayout = LibOrganizationRecoveryStorage.layout().guardianRecovery;

        // Case: Guardian recovery is already configured
        if (guardianRecoveryLayout.recoveryAddress != address(0) || guardianRecoveryLayout.timelockDurationSeconds != 0)
        {
            revert IOrganizationGuardianRecovery.GuardianRecoveryAlreadyConfigured();
        }
        // Case: New guardian recovery address is zero
        if (guardianRecoveryAddress == address(0)) {
            revert IOrganizationGuardianRecovery.InvalidGuardianRecoveryAddress();
        }

        // Case: New guardian recovery timelock duration is zero
        if (guardianRecoveryTimelockDurationSeconds == 0) {
            revert IOrganizationGuardianRecovery.InvalidGuardianRecoveryTimelockDurationSeconds();
        }

        // Set storage values
        guardianRecoveryLayout.recoveryAddress = guardianRecoveryAddress;
        guardianRecoveryLayout.timelockDurationSeconds = guardianRecoveryTimelockDurationSeconds;
    }

    /**
     * @dev Initiates a recovery guardian update (starts timelock).
     *      Uses recovery storage for pending state (separate from normal flow).
     * @param newGuardian The proposed new guardian address
     */
    function initiateRecoveryGuardianUpdate(address newGuardian) internal {
        LibOrganizationRecoveryStorage.GuardianRecoveryState storage guardianRecovery =
        LibOrganizationRecoveryStorage.layout().guardianRecovery;

        // Case: Already a pending recovery guardian update
        if (guardianRecovery.pendingGuardian != address(0)) {
            revert IOrganizationGuardianRecovery.RecoveryGuardianUpdateAlreadyPending();
        }

        // Validate new guardian is not zero
        if (newGuardian == address(0)) {
            revert IOrganizationGuardianRecovery.InvalidNewGuardianAddress();
        }

        uint256 canFinalizeAtTimestamp = block.timestamp + guardianRecovery.timelockDurationSeconds;

        // Set pending state in recovery storage
        guardianRecovery.pendingGuardian = newGuardian;
        guardianRecovery.pendingGuardianTimestamp = canFinalizeAtTimestamp;
        guardianRecovery.isUpdateReadyForAcceptance = false;

        // Get current guardian for event
        address currentGuardian = LibOrganizationGuardianStorage.layout().guardian;

        emit IOrganizationGuardianRecovery.RecoveryGuardianUpdateInitiated(
            currentGuardian, newGuardian, canFinalizeAtTimestamp
        );
    }

    /**
     * @dev Finalizes a recovery guardian update (after timelock, ready for new guardian to accept).
     *      Reverts if no recovery guardian update is pending or timelock has not expired.
     */
    function finalizeRecoveryGuardianUpdate() internal {
        LibOrganizationRecoveryStorage.GuardianRecoveryState storage guardianRecovery =
        LibOrganizationRecoveryStorage.layout().guardianRecovery;

        // Case: No pending recovery guardian update
        if (guardianRecovery.pendingGuardian == address(0)) {
            revert IOrganizationGuardianRecovery.NoPendingRecoveryGuardianUpdate();
        }

        uint256 canFinalizeAtTimestamp = guardianRecovery.pendingGuardianTimestamp;

        // Case: Timelock not expired
        if (block.timestamp < canFinalizeAtTimestamp) {
            revert IOrganizationGuardianRecovery.GuardianRecoveryTimelockNotExpired(
                canFinalizeAtTimestamp, block.timestamp
            );
        }

        // Mark as ready for acceptance (new guardian must call acceptGuardianRecovery)
        guardianRecovery.isUpdateReadyForAcceptance = true;

        emit IOrganizationGuardianRecovery.RecoveryGuardianUpdateFinalized(guardianRecovery.pendingGuardian);
    }

    /**
     * @dev Cancels a pending recovery guardian update.
     *      Reverts if no recovery guardian update is pending.
     */
    function cancelRecoveryGuardianUpdate() internal {
        LibOrganizationRecoveryStorage.GuardianRecoveryState storage guardianRecovery =
        LibOrganizationRecoveryStorage.layout().guardianRecovery;

        // Case: No pending recovery guardian update
        if (guardianRecovery.pendingGuardian == address(0)) {
            revert IOrganizationGuardianRecovery.NoPendingRecoveryGuardianUpdate();
        }

        address cancelledGuardian = guardianRecovery.pendingGuardian;

        // Clear all pending state
        guardianRecovery.pendingGuardian = address(0);
        guardianRecovery.pendingGuardianTimestamp = 0;
        guardianRecovery.isUpdateReadyForAcceptance = false;

        emit IOrganizationGuardianRecovery.RecoveryGuardianUpdateCancelled(cancelledGuardian);
    }

    /**
     * @dev Accepts the guardian role via recovery flow (completes the recovery update).
     *      Caller must be the recovery pending guardian (enforced by modifier in OrganizationImplementation).
     */
    function acceptGuardianRecovery() internal {
        LibOrganizationRecoveryStorage.GuardianRecoveryState storage guardianRecovery =
        LibOrganizationRecoveryStorage.layout().guardianRecovery;

        address pendingGuardianAddr = guardianRecovery.pendingGuardian;

        // Case: No pending recovery guardian update
        if (pendingGuardianAddr == address(0)) {
            revert IOrganizationGuardianRecovery.NoPendingRecoveryGuardianUpdate();
        }

        // Case: Not ready for acceptance (finalize hasn't been called)
        if (!guardianRecovery.isUpdateReadyForAcceptance) {
            revert IOrganizationGuardianRecovery.RecoveryGuardianUpdateNotReadyForAcceptance();
        }

        // Get current guardian for event
        LibOrganizationGuardianStorage.Layout storage guardianLayout = LibOrganizationGuardianStorage.layout();
        address previousGuardian = guardianLayout.guardian;

        // Update guardian in guardian storage
        guardianLayout.guardian = pendingGuardianAddr;

        // Clear all recovery pending state
        guardianRecovery.pendingGuardian = address(0);
        guardianRecovery.pendingGuardianTimestamp = 0;
        guardianRecovery.isUpdateReadyForAcceptance = false;

        emit IOrganizationGuardianRecovery.RecoveryGuardianUpdateAccepted(previousGuardian, pendingGuardianAddr);
    }

    /**
     * @dev Initiates deferred initialization of guardian recovery (starts timelock).
     *      Reverts if already configured, already pending, or inputs are invalid.
     *
     *      Note: Event emission is handled by the caller (OrganizationGuardianRecoveryBase).
     * @param guardianRecoveryAddress The proposed guardian recovery address
     * @param guardianRecoveryTimelockDurationSeconds The proposed timelock duration in seconds
     */
    function initiateInitializeGuardianRecovery(
        address guardianRecoveryAddress,
        uint256 guardianRecoveryTimelockDurationSeconds
    ) internal {
        LibOrganizationRecoveryStorage.GuardianRecoveryState storage guardianRecovery =
        LibOrganizationRecoveryStorage.layout().guardianRecovery;

        // Case: Guardian recovery is already configured
        if (guardianRecovery.recoveryAddress != address(0) || guardianRecovery.timelockDurationSeconds != 0) {
            revert IOrganizationGuardianRecovery.GuardianRecoveryAlreadyConfigured();
        }

        // Case: Already a pending initialization
        if (guardianRecovery.pendingInitTimestamp != 0) {
            revert IOrganizationGuardianRecovery.GuardianRecoveryInitializationAlreadyPending();
        }

        // Case: New guardian recovery address is zero
        if (guardianRecoveryAddress == address(0)) {
            revert IOrganizationGuardianRecovery.InvalidGuardianRecoveryAddress();
        }

        // Case: New guardian recovery timelock duration is zero
        if (guardianRecoveryTimelockDurationSeconds == 0) {
            revert IOrganizationGuardianRecovery.InvalidGuardianRecoveryTimelockDurationSeconds();
        }

        // Read the organization-wide secure timelock duration
        uint256 secureTimelock = LibOrganizationSecureTimelockStorage.layout().secureTimelockDurationSeconds;
        uint256 canFinalizeAtTimestamp = block.timestamp + secureTimelock;

        // Store pending initialization values
        guardianRecovery.pendingInitRecoveryAddress = guardianRecoveryAddress;
        guardianRecovery.pendingInitTimelockDurationSeconds = guardianRecoveryTimelockDurationSeconds;
        guardianRecovery.pendingInitTimestamp = canFinalizeAtTimestamp;

        emit IOrganizationGuardianRecovery.GuardianRecoveryInitializationInitiated(
            guardianRecoveryAddress, guardianRecoveryTimelockDurationSeconds, canFinalizeAtTimestamp
        );
    }

    /**
     * @dev Finalizes deferred initialization of guardian recovery (after timelock).
     *      Writes the pending values to the actual recovery configuration fields.
     *
     *      Note: Event emission is handled by the caller (OrganizationGuardianRecoveryBase).
     */
    function finalizeInitializeGuardianRecovery() internal {
        LibOrganizationRecoveryStorage.GuardianRecoveryState storage guardianRecovery =
        LibOrganizationRecoveryStorage.layout().guardianRecovery;

        uint256 canFinalizeAtTimestamp = guardianRecovery.pendingInitTimestamp;

        // Case: No pending initialization
        if (canFinalizeAtTimestamp == 0) {
            revert IOrganizationGuardianRecovery.NoGuardianRecoveryInitializationPending();
        }

        // Case: Timelock not expired
        if (block.timestamp < canFinalizeAtTimestamp) {
            revert IOrganizationGuardianRecovery.GuardianRecoveryInitializationTimelockNotExpired(
                canFinalizeAtTimestamp, block.timestamp
            );
        }

        // Read pending values
        address pendingAddress = guardianRecovery.pendingInitRecoveryAddress;
        uint256 pendingTimelock = guardianRecovery.pendingInitTimelockDurationSeconds;

        // Write actual configuration (same as initializeGuardianRecovery logic)
        guardianRecovery.recoveryAddress = pendingAddress;
        guardianRecovery.timelockDurationSeconds = pendingTimelock;

        // Clear pending state
        guardianRecovery.pendingInitRecoveryAddress = address(0);
        guardianRecovery.pendingInitTimelockDurationSeconds = 0;
        guardianRecovery.pendingInitTimestamp = 0;

        emit IOrganizationGuardianRecovery.GuardianRecoveryInitializationFinalized(pendingAddress, pendingTimelock);
    }

    /**
     * @dev Cancels a pending deferred initialization of guardian recovery.
     *      Reverts if no initialization is pending.
     */
    function cancelInitializeGuardianRecovery() internal {
        LibOrganizationRecoveryStorage.GuardianRecoveryState storage guardianRecovery =
        LibOrganizationRecoveryStorage.layout().guardianRecovery;

        // Case: No pending initialization
        if (guardianRecovery.pendingInitTimestamp == 0) {
            revert IOrganizationGuardianRecovery.NoGuardianRecoveryInitializationPending();
        }

        // Clear pending state
        guardianRecovery.pendingInitRecoveryAddress = address(0);
        guardianRecovery.pendingInitTimelockDurationSeconds = 0;
        guardianRecovery.pendingInitTimestamp = 0;

        emit IOrganizationGuardianRecovery.GuardianRecoveryInitializationCancelled();
    }

    /**
     * @dev Enforces that the caller is the guardian recovery address.
     *      Reverts if msg.sender is not the guardian recovery address.
     */
    function enforceOnlyGuardianRecoveryAddress() internal view {
        address expected = LibOrganizationRecoveryStorage.layout().guardianRecovery.recoveryAddress;

        if (msg.sender != expected) {
            revert IOrganizationGuardianRecovery.UnauthorizedGuardianRecoveryAddress(msg.sender, expected);
        }
    }

    /**
     * @dev Enforces that the caller is the recovery pending guardian address.
     *      Reverts if msg.sender is not the recovery pending guardian.
     */
    function enforceOnlyRecoveryPendingGuardian() internal view {
        address pendingGuardianAddr = LibOrganizationRecoveryStorage.layout().guardianRecovery.pendingGuardian;
        if (msg.sender != pendingGuardianAddr) {
            // solhint-disable-next-line max-line-length
            revert IOrganizationGuardianRecovery.UnauthorizedRecoveryGuardianAcceptance(msg.sender, pendingGuardianAddr);
        }
    }

    /**
     * @dev Returns the guardian recovery address.
     * @return The recovery address
     */
    function getGuardianRecoveryAddress() internal view returns (address) {
        return LibOrganizationRecoveryStorage.layout().guardianRecovery.recoveryAddress;
    }

    /**
     * @dev Returns the guardian recovery timelock duration in seconds.
     * @return The duration
     */
    function getGuardianRecoveryTimelockDurationSeconds() internal view returns (uint256) {
        return LibOrganizationRecoveryStorage.layout().guardianRecovery.timelockDurationSeconds;
    }

    /**
     * @dev Returns the recovery pending guardian address.
     * @return The pending guardian address (zero if no pending recovery update)
     */
    function getRecoveryPendingGuardian() internal view returns (address) {
        return LibOrganizationRecoveryStorage.layout().guardianRecovery.pendingGuardian;
    }

    /**
     * @dev Returns the recovery pending guardian timestamp.
     * @return The timestamp when the recovery update can be finalized (0 if no pending)
     */
    function getRecoveryPendingGuardianTimestamp() internal view returns (uint256) {
        return LibOrganizationRecoveryStorage.layout().guardianRecovery.pendingGuardianTimestamp;
    }

    /**
     * @dev Checks if the recovery guardian update is ready for acceptance.
     * @return True if the recovery update has been finalized and is waiting for the new guardian to accept
     */
    function getIsRecoveryGuardianUpdateReadyForAcceptance() internal view returns (bool) {
        return LibOrganizationRecoveryStorage.layout().guardianRecovery.isUpdateReadyForAcceptance;
    }

    /**
     * @dev Returns the pending initialization recovery address.
     * @return The pending address (zero if no pending initialization)
     */
    function getPendingInitGuardianRecoveryAddress() internal view returns (address) {
        return LibOrganizationRecoveryStorage.layout().guardianRecovery.pendingInitRecoveryAddress;
    }

    /**
     * @dev Returns the pending initialization timelock duration in seconds.
     * @return The pending duration (zero if no pending initialization)
     */
    function getPendingInitGuardianRecoveryTimelockDurationSeconds() internal view returns (uint256) {
        return LibOrganizationRecoveryStorage.layout().guardianRecovery.pendingInitTimelockDurationSeconds;
    }

    /**
     * @dev Returns the pending initialization timestamp.
     * @return The timestamp when initialization can be finalized (zero if no pending)
     */
    function getPendingInitGuardianRecoveryTimestamp() internal view returns (uint256) {
        return LibOrganizationRecoveryStorage.layout().guardianRecovery.pendingInitTimestamp;
    }
}
