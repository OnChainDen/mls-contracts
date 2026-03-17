// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdminOperationTimelock} from "interfaces/organization/IOrganizationAdminOperationTimelock.sol";
import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {
    LibOrganizationGuardianRecoverySuiteBase
} from "test/organization/libraries/LibOrganizationGuardianRecovery/LibOrganizationGuardianRecoverySuiteBase.sol";
import {GuardianRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Unit tests for `LibOrganizationGuardianRecovery.finalizeInitializeGuardianRecovery`.
 */
contract LibOrganizationGuardianRecoveryFinalizeInitializeGuardianRecoveryTest is
    LibOrganizationGuardianRecoverySuiteBase
{
    /// @dev Verifies `LibOrganizationGuardianRecovery.finalizeInitializeGuardianRecovery` finalize after timelock
    /// configures state, clears pending-init, and emits event.
    function test_finalizeAfterTimelock_configuresAndClearsPendingInit() public {
        // Setup: start from clean recovery state and seed pending deferred-init tuple.
        harness.resetGuardianRecoveryStorageViaHarness();
        harness.initiateInitializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);
        uint256 canFinalizeAt = harness.getGuardianRecoveryStateViaStorage().pendingInit.pendingTimestamp;

        // Call: finalize deferred recovery initialization.
        vm.warp(canFinalizeAt);
        vm.expectEmit(true, true, true, true);
        emit IOrganizationGuardianRecovery.GuardianRecoveryInitializationFinalized(
            GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK
        );
        harness.finalizeInitializeGuardianRecoveryViaLibrary();

        // Verify: recovery address is configured; timelock is configured.
        GuardianRecoveryState memory state = harness.getGuardianRecoveryStateViaStorage();
        assertEq(state.recoveryAddress, GUARDIAN_RECOVERY_ADDRESS, "recovery address should be configured");
        assertEq(state.timelockDurationSeconds, GUARDIAN_RECOVERY_TIMELOCK, "timelock should be configured");
        assertEq(state.pendingInit.pendingRecoveryAddress, address(0), "pending-init address should clear");
        assertEq(state.pendingInit.pendingTimelockDurationSeconds, 0, "pending-init timelock should clear");
        assertEq(state.pendingInit.pendingTimestamp, 0, "pending-init timestamp should clear");
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.finalizeInitializeGuardianRecovery` no-pending and
    /// timelock-not-expired paths revert without mutating pending/config state.
    function test_revertPaths_preservePendingAndConfigState() public {
        // Setup: start from clean recovery state.
        harness.resetGuardianRecoveryStorageViaHarness();

        // Call: finalize deferred recovery initialization then initiate deferred recovery initialization, expecting
        // `NoGuardianRecoveryInitializationPending` revert.
        vm.expectRevert(IOrganizationGuardianRecovery.NoGuardianRecoveryInitializationPending.selector);
        harness.finalizeInitializeGuardianRecoveryViaLibrary();

        harness.initiateInitializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);
        uint256 canFinalizeAt = harness.getGuardianRecoveryStateViaStorage().pendingInit.pendingTimestamp;

        vm.warp(canFinalizeAt - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdminOperationTimelock.TimelockNotExpired.selector, canFinalizeAt, canFinalizeAt - 1
            )
        );
        harness.finalizeInitializeGuardianRecoveryViaLibrary();

        // Verify: config recovery address remains zero on revert paths; config timelock remains zero on revert paths.
        GuardianRecoveryState memory state = harness.getGuardianRecoveryStateViaStorage();
        assertEq(state.recoveryAddress, address(0), "config recovery address should remain zero on revert paths");
        assertEq(state.timelockDurationSeconds, 0, "config timelock should remain zero on revert paths");
        assertEq(
            state.pendingInit.pendingRecoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS,
            "pending init tuple should remain unchanged on timelock revert"
        );
        assertEq(
            state.pendingInit.pendingTimelockDurationSeconds,
            GUARDIAN_RECOVERY_TIMELOCK,
            "pending timelock should remain"
        );
        assertEq(state.pendingInit.pendingTimestamp, canFinalizeAt, "pending timestamp should remain");
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.finalizeInitializeGuardianRecovery` finalized deferred-init
    /// enables the full recovery update flow.
    function test_finalizeDeferredInit_enablesRecoveryFlowUsage() public {
        // Setup: start from clean recovery state, seed pending deferred-init tuple, and position timestamp at timelock
        // boundary.
        harness.resetGuardianRecoveryStorageViaHarness();
        harness.initiateInitializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);
        vm.warp(harness.getGuardianRecoveryStateViaStorage().pendingInit.pendingTimestamp);
        harness.finalizeInitializeGuardianRecoveryViaLibrary();

        // Call: initiate recovery guardian update, finalize recovery guardian update, then accept recovery guardian
        // update.
        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        vm.warp(harness.getGuardianRecoveryStateViaStorage().pendingGuardianTimestamp);
        harness.finalizeRecoveryGuardianUpdateViaLibrary();
        harness.acceptGuardianRecoveryViaLibrary();

        // Verify: guardian is updatable via recovery post-finalize.
        assertEq(
            harness.getGuardianViaLibrary(), NEW_GUARDIAN_A, "guardian should be updatable via recovery post-finalize"
        );
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.finalizeInitializeGuardianRecovery` malformed pending tuple
    /// revert is atomic and rolls back pending-init clearing.
    function test_malformedPendingTupleRevert_isAtomic() public {
        // Setup: start from clean recovery state and seed pending deferred-init tuple.
        harness.resetGuardianRecoveryStorageViaHarness();
        recoveryStateHarness.setGuardianRecoveryPendingInit(address(0), GUARDIAN_RECOVERY_TIMELOCK, block.timestamp);

        // Call: finalize deferred recovery initialization, expecting `InvalidGuardianRecoveryAddress` revert.
        vm.expectRevert(IOrganizationGuardianRecovery.InvalidGuardianRecoveryAddress.selector);
        harness.finalizeInitializeGuardianRecoveryViaLibrary();

        // Verify: config recovery address remains zero; config timelock remains zero.
        GuardianRecoveryState memory state = harness.getGuardianRecoveryStateViaStorage();
        assertEq(state.recoveryAddress, address(0), "config recovery address should remain zero");
        assertEq(state.timelockDurationSeconds, 0, "config timelock should remain zero");
        assertEq(
            state.pendingInit.pendingRecoveryAddress,
            address(0),
            "pending-init address should rollback to malformed original"
        );
        assertEq(
            state.pendingInit.pendingTimelockDurationSeconds,
            GUARDIAN_RECOVERY_TIMELOCK,
            "pending-init timelock should rollback"
        );
        assertEq(state.pendingInit.pendingTimestamp, block.timestamp, "pending-init timestamp should rollback");
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.finalizeInitializeGuardianRecovery` finalize leaves
    /// recovery-update pending fields untouched and double-finalize reverts.
    function test_finalizePreservesRecoveryUpdateFields_andDoubleFinalizeReverts() public {
        // Setup: start from clean recovery state, seed pending deferred-init tuple, and seed pending recovery-guardian
        // update.
        harness.resetGuardianRecoveryStorageViaHarness();
        uint256 expectedPendingGuardianTimestamp = block.timestamp + 10 days;
        recoveryStateHarness.setGuardianRecoveryPendingUpdate(NEW_GUARDIAN_B, expectedPendingGuardianTimestamp, true);
        harness.initiateInitializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);
        uint256 canFinalizeAt = harness.getGuardianRecoveryStateViaStorage().pendingInit.pendingTimestamp;

        // Call: finalize deferred recovery initialization, expecting `NoGuardianRecoveryInitializationPending` revert.
        vm.warp(canFinalizeAt);
        harness.finalizeInitializeGuardianRecoveryViaLibrary();

        vm.expectRevert(IOrganizationGuardianRecovery.NoGuardianRecoveryInitializationPending.selector);
        harness.finalizeInitializeGuardianRecoveryViaLibrary();

        // Verify: recovery-update pending guardian remains untouched; recovery-update ready flag remains untouched.
        GuardianRecoveryState memory state = harness.getGuardianRecoveryStateViaStorage();
        assertEq(state.pendingGuardian, NEW_GUARDIAN_B, "recovery-update pending guardian should remain untouched");
        assertEq(
            state.pendingGuardianTimestamp,
            expectedPendingGuardianTimestamp,
            "recovery-update pending timestamp should remain untouched"
        );
        assertTrue(state.isUpdateReadyForAcceptance, "recovery-update ready flag should remain untouched");
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.finalizeInitializeGuardianRecovery` succeeds when
    /// `block.timestamp` is strictly greater than the pending initialization timestamp.
    function test_finalizeInitializeGuardianRecovery_afterPendingTimestampSucceeds() public {
        // Setup: stage a deferred guardian-recovery initialization and advance one second past its pending timestamp.
        harness.resetGuardianRecoveryStorageViaHarness();
        harness.initiateInitializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);
        vm.warp(harness.getGuardianRecoveryStateViaStorage().pendingInit.pendingTimestamp + 1);

        // Call: finalize the deferred initialization after the admin-operation timelock has already expired.
        harness.finalizeInitializeGuardianRecoveryViaLibrary();

        // Verify: finalization succeeds and writes the pending recovery configuration into active storage.
        GuardianRecoveryState memory state = harness.getGuardianRecoveryStateViaStorage();
        assertEq(state.recoveryAddress, GUARDIAN_RECOVERY_ADDRESS, "post-expiry finalize should configure recovery");
        assertEq(
            state.timelockDurationSeconds,
            GUARDIAN_RECOVERY_TIMELOCK,
            "post-expiry finalize should configure the pending timelock"
        );
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.finalizeInitializeGuardianRecovery` reverts with
    /// `NoGuardianRecoveryInitializationPending` after cancellation even once the cancelled timestamp has passed.
    function test_finalizeInitializeGuardianRecovery_afterCancellationAndExpiryRevertsNoPending() public {
        // Setup: stage and cancel a deferred initialization, then advance past the cancelled pending timestamp.
        harness.resetGuardianRecoveryStorageViaHarness();
        harness.initiateInitializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);
        uint256 cancelledPendingTimestamp = harness.getGuardianRecoveryStateViaStorage().pendingInit.pendingTimestamp;
        harness.cancelInitializeGuardianRecoveryViaLibrary();
        vm.warp(cancelledPendingTimestamp + 1);

        // Call: attempt to finalize after the cancelled timestamp has elapsed.
        vm.expectRevert(IOrganizationGuardianRecovery.NoGuardianRecoveryInitializationPending.selector);
        harness.finalizeInitializeGuardianRecoveryViaLibrary();

        // Verify: cancellation remains authoritative and leaves the pending-init tuple cleared.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().pendingInit.pendingTimestamp,
            0,
            "cancelled deferred initialization should remain cleared"
        );
    }
}
