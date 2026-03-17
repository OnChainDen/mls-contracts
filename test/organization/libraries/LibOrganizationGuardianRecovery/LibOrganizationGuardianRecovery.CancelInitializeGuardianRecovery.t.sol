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
    /// Plan rows: LOGR-AOTCIGR-3.
    function test_LOGR_CIGR_1__LOGR_AOTCIGR_3_noPendingInitialization_revertsNoGuardianRecoveryInitializationPending()
        public
    {
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
    /// Plan rows: LOGR-AOTCIGR-1.
    function test_LOGR_CIGR_2__LOGR_CIGR_3__LOGR_CIGR_4__LOGR_CIGR_5__LOGR_CIGR_6__LOGR_CIGR_9__LOGR_AOTCIGR_1_cancelClearsPendingInitAndPreservesOtherState()
        public
    {
        // Setup: start from clean recovery state, seed pending deferred-init tuple, and seed pending recovery-guardian
        // update.
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

        // Call: cancel deferred recovery initialization then initiate deferred recovery initialization, expecting
        // `NoGuardianRecoveryInitializationPending` revert.
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

    /// @dev Verifies `LibOrganizationGuardianRecovery.cancelInitializeGuardianRecovery` succeeds after the admin-op
    /// timelock has expired as long as finalization has not occurred yet.
    function test_LOGR_AOTCIGR_2_cancelInitializeGuardianRecovery_afterPendingTimestampStillSucceeds() public {
        // Setup: stage a deferred initialization and advance one second past its pending timestamp without finalizing.
        harness.resetGuardianRecoveryStorageViaHarness();
        harness.initiateInitializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);
        vm.warp(harness.getGuardianRecoveryStateViaStorage().pendingInit.pendingTimestamp + 1);

        // Call: cancel the deferred initialization after expiry but before finalization.
        harness.cancelInitializeGuardianRecoveryViaLibrary();

        // Verify: cancellation after expiry still clears the staged deferred-init tuple.
        GuardianRecoveryState memory state = harness.getGuardianRecoveryStateViaStorage();
        assertEq(state.pendingInit.pendingRecoveryAddress, address(0), "post-expiry cancel should clear address");
        assertEq(state.pendingInit.pendingTimelockDurationSeconds, 0, "post-expiry cancel should clear timelock");
        assertEq(state.pendingInit.pendingTimestamp, 0, "post-expiry cancel should clear timestamp");
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.cancelInitializeGuardianRecovery` allows a later re-initiation
    /// to compute a fresh admin-operation timelock timestamp from the new start time.
    function test_LOGR_AOTCIGR_4_cancelInitializeGuardianRecovery_reinitiationComputesFreshPendingTimestamp() public {
        // Setup: stage and cancel one deferred initialization, then move time forward before re-initiating.
        harness.resetGuardianRecoveryStorageViaHarness();
        harness.initiateInitializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);
        harness.cancelInitializeGuardianRecoveryViaLibrary();
        vm.warp(block.timestamp + 4 days);
        uint256 expectedFreshPendingTimestamp = block.timestamp + ADMIN_OPERATION_TIMELOCK;

        // Call: initiate the deferred initialization again after the prior pending tuple was cancelled.
        harness.initiateInitializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS_B, 4 days);

        // Verify: the new pending timestamp is recomputed from the new start time rather than reusing stale state.
        GuardianRecoveryState memory state = harness.getGuardianRecoveryStateViaStorage();
        assertEq(
            state.pendingInit.pendingTimestamp,
            expectedFreshPendingTimestamp,
            "re-initiation should compute a fresh pending timestamp"
        );
        assertEq(
            state.pendingInit.pendingRecoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS_B,
            "re-initiation should store the new pending recovery address"
        );
    }
}
