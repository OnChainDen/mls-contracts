// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationTxRecovery} from "interfaces/organization/IOrganizationTxRecovery.sol";
import {LibOrganizationAdminOperationTimelock} from "organization/libraries/LibOrganizationAdminOperationTimelock.sol";
import {LibOrganizationGuardian} from "organization/libraries/LibOrganizationGuardian.sol";
import {LibOrganizationGuardianRecovery} from "organization/libraries/LibOrganizationGuardianRecovery.sol";
import {LibOrganizationTxRecovery} from "organization/libraries/LibOrganizationTxRecovery.sol";
import {LibOrganizationRecoveryStorage} from "organization/libraries/storage/LibOrganizationRecoveryStorage.sol";
import {
    OrganizationGuardianRecoveryStateHarness
} from "test/organization/shared/OrganizationGuardianRecoveryStateHarness.sol";
import {GuardianRecoveryState, PendingRecoveryInitTimelock, TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Shared cross-file harness for admin-operation timelock integration, fuzz, and invariant tests.
 */
contract OrganizationAdminOperationTimelockCrossFileHarness is OrganizationGuardianRecoveryStateHarness {
    /**
     * @dev Executes `LibOrganizationAdminOperationTimelock.initializeAdminOperationTimelock`.
     * @param durationSeconds Admin-operation timelock duration to validate and persist.
     */
    function initializeAdminOperationTimelockViaLibrary(uint256 durationSeconds) external {
        LibOrganizationAdminOperationTimelock.initializeAdminOperationTimelock(durationSeconds);
    }

    /**
     * @dev Executes `LibOrganizationGuardian.initializeGuardian`.
     * @param guardian Initial guardian address.
     */
    function initializeGuardianViaLibrary(address guardian) external {
        LibOrganizationGuardian.initializeGuardian(guardian);
    }

    /**
     * @dev Executes `LibOrganizationGuardian.initiateGuardianUpdate`.
     * @param newGuardian Pending guardian address to stage behind the admin-operation timelock.
     */
    function initiateGuardianUpdateViaLibrary(address newGuardian) external {
        LibOrganizationGuardian.initiateGuardianUpdate(newGuardian);
    }

    /**
     * @dev Executes `LibOrganizationGuardian.finalizeGuardianUpdate`.
     */
    function finalizeGuardianUpdateViaLibrary() external {
        LibOrganizationGuardian.finalizeGuardianUpdate();
    }

    /**
     * @dev Executes `LibOrganizationGuardian.cancelGuardianUpdate`.
     */
    function cancelGuardianUpdateViaLibrary() external {
        LibOrganizationGuardian.cancelGuardianUpdate();
    }

    /**
     * @dev Executes `LibOrganizationGuardian.acceptGuardian`.
     */
    function acceptGuardianViaLibrary() external {
        LibOrganizationGuardian.acceptGuardian();
    }

    /**
     * @dev Reads the pending guardian address from library storage.
     * @return pendingGuardian Pending guardian address.
     */
    function getPendingGuardianViaLibrary() external view returns (address pendingGuardian) {
        return LibOrganizationGuardian.getPendingGuardian();
    }

    /**
     * @dev Reads the pending guardian-update timestamp from library storage.
     * @return pendingTimestamp Pending guardian-update timestamp.
     */
    function getPendingGuardianUpdateTimestampViaLibrary() external view returns (uint256 pendingTimestamp) {
        return LibOrganizationGuardian.getPendingGuardianUpdateTimestamp();
    }

    /**
     * @dev Reads the guardian-update ready flag from library storage.
     * @return isReady Whether the guardian update is ready for acceptance.
     */
    function getIsGuardianUpdateReadyForAcceptanceViaLibrary() external view returns (bool isReady) {
        return LibOrganizationGuardian.getIsGuardianUpdateReadyForAcceptance();
    }

    /**
     * @dev Executes `LibOrganizationGuardianRecovery.initiateInitializeGuardianRecovery`.
     * @param recoveryAddress Recovery address to stage behind the admin-operation timelock.
     * @param timelockDurationSeconds Guardian-recovery timelock to bind to the pending tuple.
     */
    function initiateInitializeGuardianRecoveryViaLibrary(address recoveryAddress, uint256 timelockDurationSeconds)
        external
    {
        LibOrganizationGuardianRecovery.initiateInitializeGuardianRecovery(recoveryAddress, timelockDurationSeconds);
    }

    /**
     * @dev Executes `LibOrganizationGuardianRecovery.finalizeInitializeGuardianRecovery`.
     */
    function finalizeInitializeGuardianRecoveryViaLibrary() external {
        LibOrganizationGuardianRecovery.finalizeInitializeGuardianRecovery();
    }

    /**
     * @dev Executes `LibOrganizationGuardianRecovery.cancelInitializeGuardianRecovery`.
     */
    function cancelInitializeGuardianRecoveryViaLibrary() external {
        LibOrganizationGuardianRecovery.cancelInitializeGuardianRecovery();
    }

    /**
     * @dev Executes the internal guardian-recovery configuration guard through a harness wrapper.
     */
    function validateGuardianRecoveryNotConfiguredOrRevertViaLibrary() external view {
        LibOrganizationGuardianRecovery._validateGuardianRecoveryNotConfiguredOrRevert(
            LibOrganizationRecoveryStorage.layout().guardianRecovery
        );
    }

    /**
     * @dev Reads the full guardian-recovery storage snapshot.
     * @return state Current guardian-recovery state.
     */
    function getGuardianRecoveryStateViaStorage() external view returns (GuardianRecoveryState memory state) {
        return LibOrganizationRecoveryStorage.layout().guardianRecovery;
    }

    /**
     * @dev Executes `LibOrganizationTxRecovery.initiateInitializeTxRecovery`.
     * @param recoveryAddress Recovery address to stage behind the admin-operation timelock.
     * @param timelockDurationSeconds Tx-recovery timelock to bind to the pending tuple.
     */
    function initiateInitializeTxRecoveryViaLibrary(address recoveryAddress, uint256 timelockDurationSeconds) external {
        LibOrganizationTxRecovery.initiateInitializeTxRecovery(recoveryAddress, timelockDurationSeconds);
    }

    /**
     * @dev Executes `LibOrganizationTxRecovery.finalizeInitializeTxRecovery`.
     */
    function finalizeInitializeTxRecoveryViaLibrary() external {
        LibOrganizationTxRecovery.finalizeInitializeTxRecovery();
    }

    /**
     * @dev Executes `LibOrganizationTxRecovery.cancelInitializeTxRecovery`.
     */
    function cancelInitializeTxRecoveryViaLibrary() external {
        LibOrganizationTxRecovery.cancelInitializeTxRecovery();
    }

    /**
     * @dev Executes the internal tx-recovery configuration guard through a harness wrapper.
     */
    function validateTxRecoveryNotConfiguredOrRevertViaLibrary() external view {
        TxRecoveryState storage txRecovery = LibOrganizationRecoveryStorage.layout().txRecovery;
        LibOrganizationTxRecovery._validateTxRecoveryNotConfiguredOrRevert(txRecovery);
    }

    /**
     * @dev Reads the full tx-recovery storage snapshot.
     * @return state Current tx-recovery state.
     */
    function getTxRecoveryStateViaStorage() external view returns (TxRecoveryState memory state) {
        return LibOrganizationRecoveryStorage.layout().txRecovery;
    }

    /**
     * @dev Resets tx-recovery storage to a zero baseline.
     */
    function resetTxRecoveryStorageViaHarness() external {
        LibOrganizationRecoveryStorage.layout().txRecovery = TxRecoveryState({
            recoveryAddress: address(0),
            isEnabled: false,
            timelockDurationSeconds: 0,
            pendingEnableTimestamp: 0,
            pendingInit: PendingRecoveryInitTimelock({
                pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
            })
        });
    }
}
