// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {LibOrganizationGuardian} from "organization/libraries/LibOrganizationGuardian.sol";
import {LibOrganizationGuardianRecovery} from "organization/libraries/LibOrganizationGuardianRecovery.sol";
import {LibOrganizationGuardianStorage} from "organization/libraries/storage/LibOrganizationGuardianStorage.sol";
import {LibOrganizationRecoveryStorage} from "organization/libraries/storage/LibOrganizationRecoveryStorage.sol";
import {OrganizationGuardianStateHarness} from "test/organization/shared/OrganizationGuardianStateHarness.sol";
import {GuardianRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Library-focused test harness for `LibOrganizationGuardian`.
 *      Exposes direct wrappers around guardian and guardian-recovery library entry points.
 */
contract LibOrganizationGuardianHarness is OrganizationGuardianStateHarness {
    /**
     * @dev Wrapper around `LibOrganizationGuardian.initializeGuardian`.
     */
    function initializeGuardianViaLibrary(address guardianAddress) external {
        LibOrganizationGuardian.initializeGuardian(guardianAddress);
    }

    /**
     * @dev Wrapper around `LibOrganizationGuardian.initiateGuardianUpdate`.
     */
    function initiateGuardianUpdateViaLibrary(address newGuardian) external {
        LibOrganizationGuardian.initiateGuardianUpdate(newGuardian);
    }

    /**
     * @dev Wrapper around `LibOrganizationGuardian.finalizeGuardianUpdate`.
     */
    function finalizeGuardianUpdateViaLibrary() external {
        LibOrganizationGuardian.finalizeGuardianUpdate();
    }

    /**
     * @dev Wrapper around `LibOrganizationGuardian.cancelGuardianUpdate`.
     */
    function cancelGuardianUpdateViaLibrary() external {
        LibOrganizationGuardian.cancelGuardianUpdate();
    }

    /**
     * @dev Wrapper around `LibOrganizationGuardian.acceptGuardian`.
     */
    function acceptGuardianViaLibrary() external {
        LibOrganizationGuardian.acceptGuardian();
    }

    /**
     * @dev Wrapper around `LibOrganizationGuardian.enforceOnlyGuardian`.
     */
    function enforceOnlyGuardianViaLibrary() external view {
        LibOrganizationGuardian.enforceOnlyGuardian();
    }

    /**
     * @dev Wrapper around `LibOrganizationGuardian.enforceOnlyPendingGuardian`.
     */
    function enforceOnlyPendingGuardianViaLibrary() external view {
        LibOrganizationGuardian.enforceOnlyPendingGuardian();
    }

    /**
     * @dev Wrapper around `LibOrganizationGuardian.getGuardian`.
     */
    function getGuardianViaLibrary() external view returns (address) {
        return LibOrganizationGuardian.getGuardian();
    }

    /**
     * @dev Wrapper around `LibOrganizationGuardian.getPendingGuardian`.
     */
    function getPendingGuardianViaLibrary() external view returns (address) {
        return LibOrganizationGuardian.getPendingGuardian();
    }

    /**
     * @dev Wrapper around `LibOrganizationGuardian.getPendingGuardianUpdateTimestamp`.
     */
    function getPendingGuardianUpdateTimestampViaLibrary() external view returns (uint256) {
        return LibOrganizationGuardian.getPendingGuardianUpdateTimestamp();
    }

    /**
     * @dev Wrapper around `LibOrganizationGuardian.getIsGuardianUpdateReadyForAcceptance`.
     */
    function getIsGuardianUpdateReadyForAcceptanceViaLibrary() external view returns (bool) {
        return LibOrganizationGuardian.getIsGuardianUpdateReadyForAcceptance();
    }

    /**
     * @dev Wrapper around `LibOrganizationGuardianRecovery.initializeGuardianRecovery`.
     */
    function initializeGuardianRecoveryViaLibrary(address recoveryAddress, uint256 timelockDurationSeconds) external {
        LibOrganizationGuardianRecovery.initializeGuardianRecovery(recoveryAddress, timelockDurationSeconds);
    }

    /**
     * @dev Wrapper around `LibOrganizationGuardianRecovery.initiateRecoveryGuardianUpdate`.
     */
    function initiateRecoveryGuardianUpdateViaLibrary(address newGuardian) external {
        LibOrganizationGuardianRecovery.initiateRecoveryGuardianUpdate(newGuardian);
    }

    /**
     * @dev Wrapper around `LibOrganizationGuardianRecovery.finalizeRecoveryGuardianUpdate`.
     */
    function finalizeRecoveryGuardianUpdateViaLibrary() external {
        LibOrganizationGuardianRecovery.finalizeRecoveryGuardianUpdate();
    }

    /**
     * @dev Wrapper around `LibOrganizationGuardianRecovery.cancelRecoveryGuardianUpdate`.
     */
    function cancelRecoveryGuardianUpdateViaLibrary() external {
        LibOrganizationGuardianRecovery.cancelRecoveryGuardianUpdate();
    }

    /**
     * @dev Wrapper around `LibOrganizationGuardianRecovery.acceptGuardianRecovery`.
     */
    function acceptGuardianRecoveryViaLibrary() external {
        LibOrganizationGuardianRecovery.acceptGuardianRecovery();
    }

    /**
     * @dev Reads full guardian-recovery state from storage.
     */
    function getGuardianRecoveryStateViaStorage() external view returns (GuardianRecoveryState memory) {
        return LibOrganizationRecoveryStorage.layout().guardianRecovery;
    }

    /**
     * @dev Resets guardian storage to an empty baseline.
     */
    function resetGuardianStorage() external {
        LibOrganizationGuardianStorage.Layout storage layout = LibOrganizationGuardianStorage.layout();
        layout.guardian = address(0);
        layout.pendingGuardian = address(0);
        layout.pendingGuardianUpdateTimestamp = 0;
        layout.isGuardianUpdateReadyForAcceptance = false;
    }

    /**
     * @dev Resets guardian-recovery storage to an empty baseline.
     */
    function resetGuardianRecoveryStorage() external {
        GuardianRecoveryState storage guardianRecovery = LibOrganizationRecoveryStorage.layout().guardianRecovery;
        guardianRecovery.recoveryAddress = address(0);
        guardianRecovery.isUpdateReadyForAcceptance = false;
        guardianRecovery.pendingGuardian = address(0);
        guardianRecovery.timelockDurationSeconds = 0;
        guardianRecovery.pendingGuardianTimestamp = 0;
        guardianRecovery.pendingInit.pendingRecoveryAddress = address(0);
        guardianRecovery.pendingInit.pendingTimelockDurationSeconds = 0;
        guardianRecovery.pendingInit.pendingTimestamp = 0;
    }
}
