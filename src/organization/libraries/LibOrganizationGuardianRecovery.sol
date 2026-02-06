// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {TimelockUtils} from "libraries/TimelockUtils.sol";
import {LibOrganizationSecureTimelock} from "organization/libraries/LibOrganizationSecureTimelock.sol";
import {LibOrganizationGuardianStorage} from "organization/libraries/storage/LibOrganizationGuardianStorage.sol";
import {LibOrganizationRecoveryStorage} from "organization/libraries/storage/LibOrganizationRecoveryStorage.sol";
import {GuardianRecoveryState} from "types/RecoveryTypes.sol";

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
     * @dev Initializes guardian recovery configuration. Used during org initialization
     *      and called by finalizeInitializeGuardianRecovery for post-deployment setup.
     *      - If already configured, reverts
     *      - Otherwise, validates address and timelock duration and writes to storage
     * @param guardianRecoveryAddress The guardian recovery address
     * @param guardianRecoveryTimelockDurationSeconds The timelock duration in seconds
     */
    function initializeGuardianRecovery(
        address guardianRecoveryAddress,
        uint256 guardianRecoveryTimelockDurationSeconds
    ) internal {
        GuardianRecoveryState storage guardianRecoveryLayout = LibOrganizationRecoveryStorage.layout().guardianRecovery;

        _validateGuardianRecoveryNotConfiguredOrRevert(guardianRecoveryLayout);
        _validateGuardianRecoveryParamsOrRevert(guardianRecoveryAddress, guardianRecoveryTimelockDurationSeconds);

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
        GuardianRecoveryState storage guardianRecovery = LibOrganizationRecoveryStorage.layout().guardianRecovery;

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
        GuardianRecoveryState storage guardianRecovery = LibOrganizationRecoveryStorage.layout().guardianRecovery;

        // Case: No pending recovery guardian update
        if (guardianRecovery.pendingGuardian == address(0)) {
            revert IOrganizationGuardianRecovery.NoPendingRecoveryGuardianUpdate();
        }

        uint256 canFinalizeAtTimestamp = guardianRecovery.pendingGuardianTimestamp;

        // Case: Timelock not expired
        LibOrganizationSecureTimelock.validateTimelockExpiredOrRevert(canFinalizeAtTimestamp);

        // Mark as ready for acceptance (new guardian must call acceptGuardianRecovery)
        guardianRecovery.isUpdateReadyForAcceptance = true;

        emit IOrganizationGuardianRecovery.RecoveryGuardianUpdateFinalized(guardianRecovery.pendingGuardian);
    }

    /**
     * @dev Cancels a pending recovery guardian update.
     *      Reverts if no recovery guardian update is pending.
     */
    function cancelRecoveryGuardianUpdate() internal {
        GuardianRecoveryState storage guardianRecovery = LibOrganizationRecoveryStorage.layout().guardianRecovery;

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
        GuardianRecoveryState storage guardianRecovery = LibOrganizationRecoveryStorage.layout().guardianRecovery;

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
     * @param guardianRecoveryAddress The proposed guardian recovery address
     * @param guardianRecoveryTimelockDurationSeconds The proposed timelock duration in seconds
     */
    function initiateInitializeGuardianRecovery(
        address guardianRecoveryAddress,
        uint256 guardianRecoveryTimelockDurationSeconds
    ) internal {
        GuardianRecoveryState storage guardianRecovery = LibOrganizationRecoveryStorage.layout().guardianRecovery;

        _validateGuardianRecoveryNotConfiguredOrRevert(guardianRecovery);

        // Case: Already a pending initialization
        if (guardianRecovery.pendingInit.pendingTimestamp != 0) {
            revert IOrganizationGuardianRecovery.GuardianRecoveryInitializationAlreadyPending();
        }

        _validateGuardianRecoveryParamsOrRevert(guardianRecoveryAddress, guardianRecoveryTimelockDurationSeconds);

        uint256 canFinalizeAtTimestamp = LibOrganizationSecureTimelock.computeCanFinalizeAtTimestamp();

        // Store pending initialization values
        guardianRecovery.pendingInit.pendingRecoveryAddress = guardianRecoveryAddress;
        guardianRecovery.pendingInit.pendingTimelockDurationSeconds = guardianRecoveryTimelockDurationSeconds;
        guardianRecovery.pendingInit.pendingTimestamp = canFinalizeAtTimestamp;

        emit IOrganizationGuardianRecovery.GuardianRecoveryInitializationInitiated(
            guardianRecoveryAddress, guardianRecoveryTimelockDurationSeconds, canFinalizeAtTimestamp
        );
    }

    /**
     * @dev Finalizes deferred initialization of guardian recovery (after timelock).
     *      Reads pending values, clears pending state, then delegates to initializeGuardianRecovery
     *      to reuse validation and config-writing logic.
     */
    function finalizeInitializeGuardianRecovery() internal {
        GuardianRecoveryState storage guardianRecovery = LibOrganizationRecoveryStorage.layout().guardianRecovery;

        uint256 canFinalizeAtTimestamp = guardianRecovery.pendingInit.pendingTimestamp;

        // Case: No pending initialization
        if (canFinalizeAtTimestamp == 0) {
            revert IOrganizationGuardianRecovery.NoGuardianRecoveryInitializationPending();
        }

        // Case: Timelock not expired
        LibOrganizationSecureTimelock.validateTimelockExpiredOrRevert(canFinalizeAtTimestamp);

        // Read pending values before clearing
        address pendingAddress = guardianRecovery.pendingInit.pendingRecoveryAddress;
        uint256 pendingTimelock = guardianRecovery.pendingInit.pendingTimelockDurationSeconds;

        // Clear pending state
        _clearPendingGuardianRecoveryInitTimelock(guardianRecovery);

        // Reuse initializeGuardianRecovery for validation + config writes
        initializeGuardianRecovery(pendingAddress, pendingTimelock);

        emit IOrganizationGuardianRecovery.GuardianRecoveryInitializationFinalized(pendingAddress, pendingTimelock);
    }

    /**
     * @dev Cancels a pending deferred initialization of guardian recovery.
     *      Reverts if no initialization is pending.
     */
    function cancelInitializeGuardianRecovery() internal {
        GuardianRecoveryState storage guardianRecovery = LibOrganizationRecoveryStorage.layout().guardianRecovery;

        // Case: No pending initialization
        if (guardianRecovery.pendingInit.pendingTimestamp == 0) {
            revert IOrganizationGuardianRecovery.NoGuardianRecoveryInitializationPending();
        }

        _clearPendingGuardianRecoveryInitTimelock(guardianRecovery);

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
     * @dev Clears all pending initialization state fields.
     * @param guardianRecovery The guardian recovery storage state
     */
    function _clearPendingGuardianRecoveryInitTimelock(GuardianRecoveryState storage guardianRecovery) private {
        guardianRecovery.pendingInit.pendingRecoveryAddress = address(0);
        guardianRecovery.pendingInit.pendingTimelockDurationSeconds = 0;
        guardianRecovery.pendingInit.pendingTimestamp = 0;
    }

    /**
     * @dev Validates that guardian recovery is not already configured.
     *      Reverts if recoveryAddress or timelockDurationSeconds is non-zero.
     * @param guardianRecovery The guardian recovery storage state
     */
    function _validateGuardianRecoveryNotConfiguredOrRevert(GuardianRecoveryState storage guardianRecovery)
        private
        view
    {
        if (guardianRecovery.recoveryAddress != address(0) || guardianRecovery.timelockDurationSeconds != 0) {
            revert IOrganizationGuardianRecovery.GuardianRecoveryAlreadyConfigured();
        }
    }

    /**
     * @dev Validates guardian recovery initialization parameters.
     *      Reverts if recovery address is zero or timelock duration is zero.
     * @param recoveryAddress The recovery address to validate
     * @param timelockDurationSeconds The timelock duration to validate
     */
    function _validateGuardianRecoveryParamsOrRevert(address recoveryAddress, uint256 timelockDurationSeconds)
        private
        pure
    {
        // Case: Recovery address is zero
        if (recoveryAddress == address(0)) {
            revert IOrganizationGuardianRecovery.InvalidGuardianRecoveryAddress();
        }

        // Case: Timelock duration outside allowed range
        TimelockUtils.validateTimelockDurationOrRevert(timelockDurationSeconds);
    }
}
