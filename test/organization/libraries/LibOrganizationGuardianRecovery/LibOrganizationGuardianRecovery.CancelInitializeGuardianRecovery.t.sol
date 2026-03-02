// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {
    LibOrganizationGuardianRecoverySuiteBase
} from "test/organization/libraries/LibOrganizationGuardianRecovery/LibOrganizationGuardianRecoverySuiteBase.sol";
import {GuardianRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Unit tests for `LibOrganizationGuardianRecovery.cancelInitializeGuardianRecovery`.
 */
contract LibOrganizationGuardianRecoveryCancelInitializeGuardianRecoveryTest is
    LibOrganizationGuardianRecoverySuiteBase
{
    /// @dev Verifies `LibOrganizationGuardianRecovery.cancelInitializeGuardianRecovery` no pending initialization
    /// reverts.
    function test_LOGR_CIGR_1_noPendingInitialization_revertsNoGuardianRecoveryInitializationPending() public {
        // Setup: start from clean recovery state.
        harness.resetGuardianRecoveryStorageViaHarness();

        // Call: cancel deferred recovery initialization, expecting `NoGuardianRecoveryInitializationPending` revert.
        vm.expectRevert(IOrganizationGuardianRecovery.NoGuardianRecoveryInitializationPending.selector);
        harness.cancelInitializeGuardianRecoveryViaLibrary();

        // Verify: pending-init timestamp remains zero.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().pendingInit.pendingTimestamp,
            0,
            "pending-init timestamp should remain zero"
        );
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.cancelInitializeGuardianRecovery` cancel clears pending-init,
    /// emits event, and preserves config/recovery-update fields.
    function test_LOGR_CIGR_2__LOGR_CIGR_3__LOGR_CIGR_4__LOGR_CIGR_5__LOGR_CIGR_6__LOGR_CIGR_9_cancelClearsPendingInitAndPreservesOtherState()
        public
    {
        // Setup: start from clean recovery state, seed pending deferred-init tuple, and seed pending recovery-guardian update.
        harness.resetGuardianRecoveryStorageViaHarness();
        recoveryStateHarness.setGuardianRecoveryPendingUpdate(NEW_GUARDIAN_A, block.timestamp + 6 days, true);
        harness.initiateInitializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);
        GuardianRecoveryState memory beforeState = harness.getGuardianRecoveryStateViaStorage();

        // Call: cancel deferred recovery initialization.
        vm.expectEmit(true, true, true, true);
        emit IOrganizationGuardianRecovery.GuardianRecoveryInitializationCancelled();
        harness.cancelInitializeGuardianRecoveryViaLibrary();

        // Verify: pending-init address clears; pending-init timelock clears.
        GuardianRecoveryState memory afterState = harness.getGuardianRecoveryStateViaStorage();
        assertEq(afterState.pendingInit.pendingRecoveryAddress, address(0), "pending-init address should clear");
        assertEq(afterState.pendingInit.pendingTimelockDurationSeconds, 0, "pending-init timelock should clear");
        assertEq(afterState.pendingInit.pendingTimestamp, 0, "pending-init timestamp should clear");
        assertEq(
            afterState.recoveryAddress, beforeState.recoveryAddress, "config recovery address should remain unchanged"
        );
        assertEq(
            afterState.timelockDurationSeconds,
            beforeState.timelockDurationSeconds,
            "config timelock should remain unchanged"
        );
        assertEq(
            afterState.pendingGuardian, beforeState.pendingGuardian, "recovery-update pending guardian should remain"
        );
        assertEq(
            afterState.pendingGuardianTimestamp,
            beforeState.pendingGuardianTimestamp,
            "recovery-update pending timestamp should remain"
        );
        assertEq(
            afterState.isUpdateReadyForAcceptance,
            beforeState.isUpdateReadyForAcceptance,
            "recovery-update ready flag should remain"
        );
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.cancelInitializeGuardianRecovery` can re-initiate after cancel,
    /// and second cancel after clear reverts.
    function test_LOGR_CIGR_7__LOGR_CIGR_8_reInitiateAfterCancelWorks_andDoubleCancelReverts() public {
        // Setup: start from clean recovery state and seed pending deferred-init tuple.
        harness.resetGuardianRecoveryStorageViaHarness();
        harness.initiateInitializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);

        // Call: cancel deferred recovery initialization then initiate deferred recovery initialization, expecting `NoGuardianRecoveryInitializationPending` revert.
        harness.cancelInitializeGuardianRecoveryViaLibrary();
        harness.initiateInitializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS_B, 4 days);
        harness.cancelInitializeGuardianRecoveryViaLibrary();

        vm.expectRevert(IOrganizationGuardianRecovery.NoGuardianRecoveryInitializationPending.selector);
        harness.cancelInitializeGuardianRecoveryViaLibrary();

        // Verify: pending-init remains cleared after second cancel.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().pendingInit.pendingTimestamp,
            0,
            "pending-init should remain cleared after second cancel"
        );
    }
}
