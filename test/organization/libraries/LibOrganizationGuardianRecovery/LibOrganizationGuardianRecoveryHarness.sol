// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {LibOrganizationGuardian} from "organization/libraries/LibOrganizationGuardian.sol";
import {LibOrganizationGuardianRecovery} from "organization/libraries/LibOrganizationGuardianRecovery.sol";
import {LibOrganizationGuardianStorage} from "organization/libraries/storage/LibOrganizationGuardianStorage.sol";
import {LibOrganizationRecoveryStorage} from "organization/libraries/storage/LibOrganizationRecoveryStorage.sol";
import {
    OrganizationGuardianRecoveryStateHarness
} from "test/organization/shared/OrganizationGuardianRecoveryStateHarness.sol";
import {GuardianRecoveryState, TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Library-focused test harness for `LibOrganizationGuardianRecovery`.
 *      Exposes wrappers around public and internal library entry points.
 */
contract LibOrganizationGuardianRecoveryHarness is OrganizationGuardianRecoveryStateHarness {
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
     * @dev Wrapper around `LibOrganizationGuardianRecovery.initiateInitializeGuardianRecovery`.
     */
    function initiateInitializeGuardianRecoveryViaLibrary(address recoveryAddress, uint256 timelockDurationSeconds)
        external
    {
        LibOrganizationGuardianRecovery.initiateInitializeGuardianRecovery(recoveryAddress, timelockDurationSeconds);
    }

    /**
     * @dev Wrapper around `LibOrganizationGuardianRecovery.finalizeInitializeGuardianRecovery`.
     */
    function finalizeInitializeGuardianRecoveryViaLibrary() external {
        LibOrganizationGuardianRecovery.finalizeInitializeGuardianRecovery();
    }

    /**
     * @dev Wrapper around `LibOrganizationGuardianRecovery.cancelInitializeGuardianRecovery`.
     */
    function cancelInitializeGuardianRecoveryViaLibrary() external {
        LibOrganizationGuardianRecovery.cancelInitializeGuardianRecovery();
    }

    /**
     * @dev Wrapper around `LibOrganizationGuardianRecovery.clearGuardianRecovery`.
     */
    function clearGuardianRecoveryViaLibrary() external {
        LibOrganizationGuardianRecovery.clearGuardianRecovery();
    }

    /**
     * @dev Wrapper around `LibOrganizationGuardianRecovery.enforceOnlyGuardianRecoveryAddress`.
     */
    function enforceOnlyGuardianRecoveryAddressViaLibrary() external view {
        LibOrganizationGuardianRecovery.enforceOnlyGuardianRecoveryAddress();
    }

    /**
     * @dev Wrapper around `LibOrganizationGuardianRecovery.enforceOnlyRecoveryPendingGuardian`.
     */
    function enforceOnlyRecoveryPendingGuardianViaLibrary() external view {
        LibOrganizationGuardianRecovery.enforceOnlyRecoveryPendingGuardian();
    }

    /**
     * @dev Wrapper around internal `_clearPendingGuardianRecoveryInitTimelock`.
     */
    function clearPendingGuardianRecoveryInitTimelockViaLibrary() external {
        LibOrganizationGuardianRecovery._clearPendingGuardianRecoveryInitTimelock(
            LibOrganizationRecoveryStorage.layout().guardianRecovery
        );
    }

    /**
     * @dev Wrapper around internal `_validateGuardianRecoveryNotConfiguredOrRevert`.
     */
    function validateGuardianRecoveryNotConfiguredOrRevertViaLibrary() external view {
        LibOrganizationGuardianRecovery._validateGuardianRecoveryNotConfiguredOrRevert(
            LibOrganizationRecoveryStorage.layout().guardianRecovery
        );
    }

    /**
     * @dev Wrapper around internal `_validateGuardianRecoveryParamsOrRevert`.
     */
    function validateGuardianRecoveryParamsOrRevertViaLibrary(address recoveryAddress, uint256 timelockDurationSeconds)
        external
        pure
    {
        LibOrganizationGuardianRecovery._validateGuardianRecoveryParamsOrRevert(
            recoveryAddress, timelockDurationSeconds
        );
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
     * @dev Reads guardian from normal guardian storage.
     */
    function getGuardianViaLibrary() external view returns (address) {
        return LibOrganizationGuardian.getGuardian();
    }

    /**
     * @dev Reads pending guardian from normal guardian storage.
     */
    function getPendingGuardianViaLibrary() external view returns (address) {
        return LibOrganizationGuardian.getPendingGuardian();
    }

    /**
     * @dev Reads pending guardian timestamp from normal guardian storage.
     */
    function getPendingGuardianUpdateTimestampViaLibrary() external view returns (uint256) {
        return LibOrganizationGuardian.getPendingGuardianUpdateTimestamp();
    }

    /**
     * @dev Reads normal-flow ready-for-acceptance flag.
     */
    function getIsGuardianUpdateReadyForAcceptanceViaLibrary() external view returns (bool) {
        return LibOrganizationGuardian.getIsGuardianUpdateReadyForAcceptance();
    }

    /**
     * @dev Reads full guardian-recovery state from storage.
     */
    function getGuardianRecoveryStateViaStorage() external view returns (GuardianRecoveryState memory) {
        return LibOrganizationRecoveryStorage.layout().guardianRecovery;
    }

    /**
     * @dev Reads full tx-recovery state from storage.
     */
    function getTxRecoveryStateViaStorage() external view returns (TxRecoveryState memory) {
        return LibOrganizationRecoveryStorage.layout().txRecovery;
    }

    /**
     * @dev Resets guardian storage to zero baseline.
     */
    function resetGuardianStorageViaHarness() external {
        LibOrganizationGuardianStorage.Layout storage layout = LibOrganizationGuardianStorage.layout();
        layout.guardian = address(0);
        layout.pendingGuardian = address(0);
        layout.pendingGuardianUpdateTimestamp = 0;
        layout.isGuardianUpdateReadyForAcceptance = false;
    }

    /**
     * @dev Resets guardian-recovery storage to zero baseline.
     */
    function resetGuardianRecoveryStorageViaHarness() external {
        GuardianRecoveryState storage state = LibOrganizationRecoveryStorage.layout().guardianRecovery;
        state.recoveryAddress = address(0);
        state.isUpdateReadyForAcceptance = false;
        state.pendingGuardian = address(0);
        state.timelockDurationSeconds = 0;
        state.pendingGuardianTimestamp = 0;
        state.pendingInit.pendingRecoveryAddress = address(0);
        state.pendingInit.pendingTimelockDurationSeconds = 0;
        state.pendingInit.pendingTimestamp = 0;
    }

    /**
     * @dev Resets tx-recovery storage to zero baseline.
     */
    function resetTxRecoveryStorageViaHarness() external {
        TxRecoveryState storage txState = LibOrganizationRecoveryStorage.layout().txRecovery;
        txState.recoveryAddress = address(0);
        txState.isEnabled = false;
        txState.timelockDurationSeconds = 0;
        txState.pendingEnableTimestamp = 0;
        txState.pendingInit.pendingRecoveryAddress = address(0);
        txState.pendingInit.pendingTimelockDurationSeconds = 0;
        txState.pendingInit.pendingTimestamp = 0;
    }
}
