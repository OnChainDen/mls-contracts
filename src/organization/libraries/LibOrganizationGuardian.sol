// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
import {LibOrganizationGuardianStorage} from "organization/libraries/storage/LibOrganizationGuardianStorage.sol";
import {LibOrganizationRecoveryStorage} from "organization/libraries/storage/LibOrganizationRecoveryStorage.sol";

/**
 * @title Lib Organization Guardian
 * @dev Library for guardian-related operations for Organization contracts.
 *      Guardian updates follow a timelocked 3-step flow: initiate → finalize → accept.
 *      This library handles the NORMAL guardian update flow only.
 *
 *      Recovery guardian update functions are in LibOrganizationGuardianRecovery with
 *      completely separate state. The two flows are NOT mutually exclusive.
 * @author Den Technologies Inc
 */
library LibOrganizationGuardian {
    /**
     * @dev Initiates a guardian update (starts timelock).
     *      Sets pendingGuardian and pendingGuardianUpdateTimestamp.
     * @param newGuardian The proposed new guardian address
     */
    function initiateGuardianUpdate(address newGuardian) internal {
        // Validate new guardian is not zero
        if (newGuardian == address(0)) {
            revert IOrganizationGuardian.InvalidGuardianAddress();
        }

        LibOrganizationGuardianStorage.Layout storage guardianLayout = LibOrganizationGuardianStorage.layout();

        // Case: Already a pending guardian update in normal flow
        if (guardianLayout.pendingGuardian != address(0)) {
            revert IOrganizationGuardian.GuardianUpdateAlreadyPending();
        }

        // Get timelock duration from recovery storage (shared config)
        uint256 timelockDuration = LibOrganizationRecoveryStorage.layout().recoveryTimelockDuration;
        uint256 canFinalizeAt = block.timestamp + timelockDuration;

        // Set pending state
        guardianLayout.pendingGuardian = newGuardian;
        guardianLayout.pendingGuardianUpdateTimestamp = canFinalizeAt;
        guardianLayout.isGuardianUpdateReadyForAcceptance = false;

        emit IOrganizationGuardian.GuardianUpdateInitiated(guardianLayout.guardian, newGuardian, canFinalizeAt);
    }

    /**
     * @dev Finalizes a guardian update (after timelock, ready for new guardian to accept).
     */
    function finalizeGuardianUpdate() internal {
        LibOrganizationGuardianStorage.Layout storage guardianLayout = LibOrganizationGuardianStorage.layout();

        // Case: No pending guardian update
        if (guardianLayout.pendingGuardian == address(0)) {
            revert IOrganizationGuardian.NoPendingGuardianUpdate();
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
     * @dev Cancels a pending guardian update (normal flow).
     */
    function cancelGuardianUpdate() internal {
        LibOrganizationGuardianStorage.Layout storage guardianLayout = LibOrganizationGuardianStorage.layout();

        // Case: No pending guardian update
        if (guardianLayout.pendingGuardian == address(0)) {
            revert IOrganizationGuardian.NoPendingGuardianUpdate();
        }

        address cancelledGuardian = guardianLayout.pendingGuardian;
        address currentGuardian = guardianLayout.guardian;

        // Clear all pending state
        guardianLayout.pendingGuardian = address(0);
        guardianLayout.pendingGuardianUpdateTimestamp = 0;
        guardianLayout.isGuardianUpdateReadyForAcceptance = false;

        emit IOrganizationGuardian.GuardianUpdateCancelled(currentGuardian, cancelledGuardian);
    }

    /**
     * @dev Accepts the guardian role (completes the normal flow update).
     *      Can only be called by the pending guardian after the update has been finalized.
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
     * @dev Gets the pending guardian address (normal flow).
     * @return The pending guardian address (zero if no pending update)
     */
    function getPendingGuardian() internal view returns (address) {
        return LibOrganizationGuardianStorage.layout().pendingGuardian;
    }

    /**
     * @dev Gets the pending guardian update timestamp (normal flow).
     * @return The timestamp when the update can be finalized (0 if no pending update)
     */
    function getPendingGuardianUpdateTimestamp() internal view returns (uint256) {
        return LibOrganizationGuardianStorage.layout().pendingGuardianUpdateTimestamp;
    }

    /**
     * @dev Checks if the guardian update is ready for acceptance (normal flow).
     * @return True if the update has been finalized and is waiting for the new guardian to accept
     */
    function getIsGuardianUpdateReadyForAcceptance() internal view returns (bool) {
        return LibOrganizationGuardianStorage.layout().isGuardianUpdateReadyForAcceptance;
    }
}
