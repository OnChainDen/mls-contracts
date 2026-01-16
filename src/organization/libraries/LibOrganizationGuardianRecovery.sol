// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {LibOrganizationGuardianStorage} from "organization/libraries/storage/LibOrganizationGuardianStorage.sol";
import {LibOrganizationRecoveryStorage} from "organization/libraries/storage/LibOrganizationRecoveryStorage.sol";

/**
 * @title Lib Organization Guardian Recovery
 * @dev Library for guardian recovery operations for Organization contracts.
 *      This library handles guardian-specific recovery functionality including:
 *      - Enabling/disabling guardian recovery (with timelocks)
 *      - Recovery guardian updates (bypassing normal admin flow)
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
     * @dev Initiates enabling guardian recovery (starts timelock).
     *      Reverts if a request is already pending.
     */
    function initiateEnableGuardianRecovery() internal {
        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();

        // Case: Already pending
        if (recoveryLayout.pendingGuardianRecoveryEnableTimestamp != 0) {
            revert IOrganizationGuardianRecovery.GuardianRecoveryEnableAlreadyPending();
        }

        uint256 canFinalizeAt = block.timestamp + recoveryLayout.recoveryTimelockDuration;
        recoveryLayout.pendingGuardianRecoveryEnableTimestamp = canFinalizeAt;

        emit IOrganizationGuardianRecovery.GuardianRecoveryEnableInitiated(canFinalizeAt);
    }

    /**
     * @dev Finalizes enabling guardian recovery (after timelock).
     *      Reverts if no request is pending or timelock has not expired.
     */
    function finalizeEnableGuardianRecovery() internal {
        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();

        uint256 canFinalizeAt = recoveryLayout.pendingGuardianRecoveryEnableTimestamp;

        // Case: No pending request
        if (canFinalizeAt == 0) {
            revert IOrganizationGuardianRecovery.NoGuardianRecoveryEnablePending();
        }

        // Case: Timelock not expired
        if (block.timestamp < canFinalizeAt) {
            revert IOrganizationGuardianRecovery.GuardianRecoveryTimelockNotExpired(canFinalizeAt, block.timestamp);
        }

        // Enable recovery and clear pending state
        recoveryLayout.isRecoveryEnabledForGuardianUpdate = true;
        recoveryLayout.pendingGuardianRecoveryEnableTimestamp = 0;

        emit IOrganizationGuardianRecovery.GuardianRecoveryEnableFinalized();
    }

    /**
     * @dev Cancels a pending guardian recovery enable request.
     *      Reverts if no request is pending.
     */
    function cancelEnableGuardianRecovery() internal {
        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();

        // Case: No pending request
        if (recoveryLayout.pendingGuardianRecoveryEnableTimestamp == 0) {
            revert IOrganizationGuardianRecovery.NoGuardianRecoveryEnablePending();
        }

        recoveryLayout.pendingGuardianRecoveryEnableTimestamp = 0;

        emit IOrganizationGuardianRecovery.GuardianRecoveryEnableCancelled();
    }

    /**
     * @dev Immediately disables guardian recovery (no timelock).
     *      Also clears any pending enable request.
     */
    function disableGuardianRecovery() internal {
        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();

        recoveryLayout.isRecoveryEnabledForGuardianUpdate = false;
        recoveryLayout.pendingGuardianRecoveryEnableTimestamp = 0;

        emit IOrganizationGuardianRecovery.GuardianRecoveryDisabled();
    }

    /**
     * @dev Initiates a recovery guardian update (starts timelock).
     *      Sets the pending guardian in the guardian storage and marks it as a recovery update.
     *      Reverts if guardian recovery is not enabled.
     * @param newGuardian The proposed new guardian address
     */
    function initiateRecoveryGuardianUpdate(address newGuardian) internal {
        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();
        LibOrganizationGuardianStorage.Layout storage guardianLayout = LibOrganizationGuardianStorage.layout();

        // Case: Guardian recovery not enabled
        if (!recoveryLayout.isRecoveryEnabledForGuardianUpdate) {
            revert IOrganizationGuardianRecovery.GuardianRecoveryNotEnabled();
        }

        // Case: Already a pending guardian update
        if (guardianLayout.pendingGuardian != address(0)) {
            revert IOrganizationGuardian.GuardianUpdateAlreadyPending();
        }

        // Validate new guardian is not zero
        if (newGuardian == address(0)) {
            revert IOrganizationGuardianRecovery.InvalidNewGuardianAddress();
        }

        uint256 canFinalizeAt = block.timestamp + recoveryLayout.recoveryTimelockDuration;

        // Set pending state in guardian storage
        guardianLayout.pendingGuardian = newGuardian;
        guardianLayout.pendingGuardianUpdateTimestamp = canFinalizeAt;
        guardianLayout.isRecoveryGuardianUpdate = true;
        guardianLayout.isGuardianUpdateReadyForAcceptance = false;

        emit IOrganizationGuardianRecovery.RecoveryGuardianUpdateInitiated(
            guardianLayout.guardian, newGuardian, canFinalizeAt
        );
    }

    /**
     * @dev Finalizes a recovery guardian update (after timelock, ready for new guardian to accept).
     *      Reverts if this is not a recovery guardian update or timelock has not expired.
     */
    function finalizeRecoveryGuardianUpdate() internal {
        LibOrganizationGuardianStorage.Layout storage guardianLayout = LibOrganizationGuardianStorage.layout();

        // Case: No pending guardian update
        if (guardianLayout.pendingGuardian == address(0)) {
            revert IOrganizationGuardianRecovery.NoPendingRecoveryGuardianUpdate();
        }

        // Case: Not a recovery guardian update
        if (!guardianLayout.isRecoveryGuardianUpdate) {
            revert IOrganizationGuardianRecovery.NotARecoveryGuardianUpdate();
        }

        uint256 canFinalizeAt = guardianLayout.pendingGuardianUpdateTimestamp;

        // Case: Timelock not expired
        if (block.timestamp < canFinalizeAt) {
            revert IOrganizationGuardianRecovery.GuardianRecoveryTimelockNotExpired(canFinalizeAt, block.timestamp);
        }

        // Mark as ready for acceptance (new guardian must call acceptGuardian)
        guardianLayout.isGuardianUpdateReadyForAcceptance = true;

        emit IOrganizationGuardianRecovery.RecoveryGuardianUpdateFinalized(guardianLayout.pendingGuardian);
    }

    /**
     * @dev Cancels a pending recovery guardian update.
     *      Reverts if this is not a recovery guardian update.
     */
    function cancelRecoveryGuardianUpdate() internal {
        LibOrganizationGuardianStorage.Layout storage guardianLayout = LibOrganizationGuardianStorage.layout();

        // Case: No pending guardian update
        if (guardianLayout.pendingGuardian == address(0)) {
            revert IOrganizationGuardianRecovery.NoPendingRecoveryGuardianUpdate();
        }

        // Case: Not a recovery guardian update
        if (!guardianLayout.isRecoveryGuardianUpdate) {
            revert IOrganizationGuardianRecovery.CannotCancelNonRecoveryGuardianUpdate();
        }

        address cancelledGuardian = guardianLayout.pendingGuardian;

        // Clear all pending state
        guardianLayout.pendingGuardian = address(0);
        guardianLayout.pendingGuardianUpdateTimestamp = 0;
        guardianLayout.isRecoveryGuardianUpdate = false;
        guardianLayout.isGuardianUpdateReadyForAcceptance = false;

        emit IOrganizationGuardianRecovery.RecoveryGuardianUpdateCancelled(cancelledGuardian);
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
     * @dev Returns whether recovery is enabled for guardian updates.
     * @return True if enabled
     */
    function isRecoveryEnabledForGuardianUpdate() internal view returns (bool) {
        return LibOrganizationRecoveryStorage.layout().isRecoveryEnabledForGuardianUpdate;
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
     * @dev Returns the pending guardian recovery enable timestamp.
     * @return The timestamp (0 if no pending request)
     */
    function getPendingGuardianRecoveryEnableTimestamp() internal view returns (uint256) {
        return LibOrganizationRecoveryStorage.layout().pendingGuardianRecoveryEnableTimestamp;
    }
}
