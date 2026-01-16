// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
import {LibOrganizationGuardianStorage} from "organization/libraries/storage/LibOrganizationGuardianStorage.sol";
import {LibOrganizationRecoveryStorage} from "organization/libraries/storage/LibOrganizationRecoveryStorage.sol";

/**
 * @title Lib Organization Guardian
 * @dev Library for guardian-related operations for Organization contracts.
 *      Guardian updates follow a timelocked 3-step flow: initiate → finalize → accept.
 *      This library should ONLY be used by Organization contracts.
 *
 *      Note: Recovery guardian update functions (initiateRecoveryGuardianUpdate, etc.)
 *      are in LibOrganizationRecovery to keep all recovery logic in one place for auditing.
 * @author Den Technologies Inc
 */
library LibOrganizationGuardian {
    /**
     * @dev Initiates a guardian update (starts timelock).
     *      Sets pendingGuardian, pendingGuardianUpdateTimestamp, and marks as non-recovery.
     * @param newGuardian The proposed new guardian address
     */
    function initiateGuardianUpdate(address newGuardian) internal {
        // Validate new guardian is not zero
        if (newGuardian == address(0)) {
            revert IOrganizationGuardian.InvalidGuardianAddress();
        }

        LibOrganizationGuardianStorage.Layout storage guardianLayout = LibOrganizationGuardianStorage.layout();

        // Case: Already a pending guardian update
        if (guardianLayout.pendingGuardian != address(0)) {
            revert IOrganizationGuardian.GuardianUpdateAlreadyPending();
        }

        // Get timelock duration from recovery storage
        uint256 timelockDuration = LibOrganizationRecoveryStorage.layout().recoveryTimelockDuration;
        uint256 canFinalizeAt = block.timestamp + timelockDuration;

        // Set pending state
        guardianLayout.pendingGuardian = newGuardian;
        guardianLayout.pendingGuardianUpdateTimestamp = canFinalizeAt;
        guardianLayout.isRecoveryGuardianUpdate = false;
        guardianLayout.isGuardianUpdateReadyForAcceptance = false;

        emit IOrganizationGuardian.GuardianUpdateInitiated(guardianLayout.guardian, newGuardian, canFinalizeAt);
    }

    /**
     * @dev Finalizes a guardian update (after timelock, ready for new guardian to accept).
     *      Can only finalize non-recovery guardian updates (recovery uses finalizeRecoveryGuardianUpdate).
     */
    function finalizeGuardianUpdate() internal {
        LibOrganizationGuardianStorage.Layout storage guardianLayout = LibOrganizationGuardianStorage.layout();

        // Case: No pending guardian update
        if (guardianLayout.pendingGuardian == address(0)) {
            revert IOrganizationGuardian.NoPendingGuardianUpdate();
        }

        // Case: This is a recovery guardian update (must use recovery flow)
        if (guardianLayout.isRecoveryGuardianUpdate) {
            revert IOrganizationGuardian.CannotFinalizeRecoveryGuardianUpdate();
        }

        uint256 canFinalizeAt = guardianLayout.pendingGuardianUpdateTimestamp;

        // Case: Timelock not expired
        if (block.timestamp < canFinalizeAt) {
            revert IOrganizationGuardian.GuardianUpdateTimelockNotExpired(canFinalizeAt, block.timestamp);
        }

        // Mark as ready for acceptance (new guardian must call acceptGuardian)
        guardianLayout.isGuardianUpdateReadyForAcceptance = true;

        emit IOrganizationGuardian.GuardianUpdateFinalized(guardianLayout.pendingGuardian);
    }

    /**
     * @dev Cancels a pending guardian update.
     *      Can only cancel non-recovery guardian updates (recovery uses cancelRecoveryGuardianUpdate).
     */
    function cancelGuardianUpdate() internal {
        LibOrganizationGuardianStorage.Layout storage guardianLayout = LibOrganizationGuardianStorage.layout();

        // Case: No pending guardian update
        if (guardianLayout.pendingGuardian == address(0)) {
            revert IOrganizationGuardian.NoPendingGuardianUpdate();
        }

        // Case: This is a recovery guardian update (must use recovery flow)
        if (guardianLayout.isRecoveryGuardianUpdate) {
            revert IOrganizationGuardian.CannotCancelRecoveryGuardianUpdate();
        }

        address cancelledGuardian = guardianLayout.pendingGuardian;
        address currentGuardian = guardianLayout.guardian;

        // Clear all pending state
        guardianLayout.pendingGuardian = address(0);
        guardianLayout.pendingGuardianUpdateTimestamp = 0;
        guardianLayout.isRecoveryGuardianUpdate = false;
        guardianLayout.isGuardianUpdateReadyForAcceptance = false;

        emit IOrganizationGuardian.GuardianUpdateCancelled(currentGuardian, cancelledGuardian);
    }

    /**
     * @dev Accepts the guardian role (completes the update).
     *      Can only be called by the pending guardian after the update has been finalized.
     *      Works for both normal and recovery guardian updates.
     */
    function acceptGuardian() internal {
        LibOrganizationGuardianStorage.Layout storage guardianLayout = LibOrganizationGuardianStorage.layout();

        address pendingGuardianAddr = guardianLayout.pendingGuardian;

        // Case: No pending guardian update
        if (pendingGuardianAddr == address(0)) {
            revert IOrganizationGuardian.NoPendingGuardianUpdate();
        }

        // Case: Not ready for acceptance (finalize hasn't been called)
        if (!guardianLayout.isGuardianUpdateReadyForAcceptance) {
            revert IOrganizationGuardian.GuardianUpdateNotReadyForAcceptance();
        }

        // Case: Caller is not the pending guardian
        if (msg.sender != pendingGuardianAddr) {
            revert IOrganizationGuardian.UnauthorizedGuardianAcceptance(msg.sender, pendingGuardianAddr);
        }

        address previousGuardian = guardianLayout.guardian;

        // Update guardian
        guardianLayout.guardian = pendingGuardianAddr;

        // Clear all pending state
        guardianLayout.pendingGuardian = address(0);
        guardianLayout.pendingGuardianUpdateTimestamp = 0;
        guardianLayout.isRecoveryGuardianUpdate = false;
        guardianLayout.isGuardianUpdateReadyForAcceptance = false;

        emit IOrganizationGuardian.GuardianUpdateAccepted(previousGuardian, pendingGuardianAddr);
    }

    /**
     * @dev Enforces that the caller is the guardian address.
     *      This function will revert if msg.sender is not the guardian.
     */
    function enforceOnlyGuardian() internal view {
        LibOrganizationGuardianStorage.Layout storage guardianLayout = LibOrganizationGuardianStorage.layout();
        if (msg.sender != guardianLayout.guardian) {
            revert IOrganizationGuardian.UnauthorizedGuardian(msg.sender, guardianLayout.guardian);
        }
    }

    /**
     * @dev Gets the current guardian address.
     * @return The current guardian address
     */
    function getGuardian() internal view returns (address) {
        return LibOrganizationGuardianStorage.layout().guardian;
    }

    /**
     * @dev Gets the pending guardian address.
     * @return The pending guardian address (zero if no pending update)
     */
    function getPendingGuardian() internal view returns (address) {
        return LibOrganizationGuardianStorage.layout().pendingGuardian;
    }

    /**
     * @dev Gets the pending guardian update timestamp.
     * @return The timestamp when the update can be finalized (0 if no pending update)
     */
    function getPendingGuardianUpdateTimestamp() internal view returns (uint256) {
        return LibOrganizationGuardianStorage.layout().pendingGuardianUpdateTimestamp;
    }

    /**
     * @dev Checks if the guardian update is ready for acceptance.
     * @return True if the update has been finalized and is waiting for the new guardian to accept
     */
    function getIsGuardianUpdateReadyForAcceptance() internal view returns (bool) {
        return LibOrganizationGuardianStorage.layout().isGuardianUpdateReadyForAcceptance;
    }

    /**
     * @dev Checks if the pending guardian update was initiated via recovery.
     * @return True if initiated via recovery flow
     */
    function getIsRecoveryGuardianUpdate() internal view returns (bool) {
        return LibOrganizationGuardianStorage.layout().isRecoveryGuardianUpdate;
    }
}
