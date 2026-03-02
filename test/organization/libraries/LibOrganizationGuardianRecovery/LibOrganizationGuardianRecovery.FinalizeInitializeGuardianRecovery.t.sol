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
    function test_LOGR_FIGR_1__LOGR_FIGR_4__LOGR_FIGR_5__LOGR_FIGR_6__LOGR_FIGR_7_finalizeAfterTimelock_configuresAndClearsPendingInit()
        public
    {
        // Setup: reset library recovery state; seed a pending deferred-init timelock tuple.
        _resetRecoveryState();
        _initiateDeferredInit(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);
        uint256 canFinalizeAt = harness.getGuardianRecoveryStateViaStorage().pendingInit.pendingTimestamp;

        // Call: invoke `LibOrganizationGuardianRecovery.finalizeInitializeGuardianRecovery`.
        vm.warp(canFinalizeAt);
        vm.expectEmit(true, true, true, true);
        emit IOrganizationGuardianRecovery.GuardianRecoveryInitializationFinalized(
            GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK
        );
        harness.finalizeInitializeGuardianRecoveryViaLibrary();

        // Verify: confirm the pending deferred-init tuple is fully cleared.
        GuardianRecoveryState memory state = harness.getGuardianRecoveryStateViaStorage();
        assertEq(state.recoveryAddress, GUARDIAN_RECOVERY_ADDRESS, "recovery address should be configured");
        assertEq(state.timelockDurationSeconds, GUARDIAN_RECOVERY_TIMELOCK, "timelock should be configured");
        assertEq(state.pendingInit.pendingRecoveryAddress, address(0), "pending-init address should clear");
        assertEq(state.pendingInit.pendingTimelockDurationSeconds, 0, "pending-init timelock should clear");
        assertEq(state.pendingInit.pendingTimestamp, 0, "pending-init timestamp should clear");
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.finalizeInitializeGuardianRecovery` no-pending and
    /// timelock-not-expired paths revert without mutating pending/config state.
    function test_LOGR_FIGR_2__LOGR_FIGR_3__LOGR_FIGR_12_revertPaths_preservePendingAndConfigState() public {
        // Setup: reset library recovery state.
        _resetRecoveryState();

        // Call: run the multi-step flow (`LibOrganizationGuardianRecovery.finalizeInitializeGuardianRecovery`,
        // `LibOrganizationGuardianRecovery.initiateInitializeGuardianRecovery`) and assert the revert branch.
        vm.expectRevert(IOrganizationGuardianRecovery.NoGuardianRecoveryInitializationPending.selector);
        harness.finalizeInitializeGuardianRecoveryViaLibrary();

        _initiateDeferredInit(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);
        uint256 canFinalizeAt = harness.getGuardianRecoveryStateViaStorage().pendingInit.pendingTimestamp;

        vm.warp(canFinalizeAt - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdminOperationTimelock.TimelockNotExpired.selector, canFinalizeAt, canFinalizeAt - 1
            )
        );
        harness.finalizeInitializeGuardianRecoveryViaLibrary();

        // Verify: confirm the pending deferred-init state remains unchanged.
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
    function test_LOGR_FIGR_8_finalizeDeferredInit_enablesRecoveryFlowUsage() public {
        // Setup: reset library recovery state; seed a pending deferred-init timelock tuple; move time to the required
        // timelock point.
        _resetRecoveryState();
        _initiateDeferredInit(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);
        vm.warp(harness.getGuardianRecoveryStateViaStorage().pendingInit.pendingTimestamp);
        harness.finalizeInitializeGuardianRecoveryViaLibrary();

        // Call: run the multi-step flow (`LibOrganizationGuardianRecovery.initiateRecoveryGuardianUpdate`,
        // `LibOrganizationGuardianRecovery.finalizeRecoveryGuardianUpdate`,
        // `LibOrganizationGuardianRecovery.acceptGuardianRecovery`).
        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        vm.warp(harness.getGuardianRecoveryStateViaStorage().pendingGuardianTimestamp);
        harness.finalizeRecoveryGuardianUpdateViaLibrary();
        harness.acceptGuardianRecoveryViaLibrary();

        // Verify: confirm guardian value in normal guardian storage.
        assertEq(
            harness.getGuardianViaLibrary(), NEW_GUARDIAN_A, "guardian should be updatable via recovery post-finalize"
        );
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.finalizeInitializeGuardianRecovery` malformed pending tuple
    /// revert is atomic and rolls back pending-init clearing.
    function test_LOGR_FIGR_9_malformedPendingTupleRevert_isAtomic() public {
        // Setup: reset library recovery state; seed a pending deferred-init timelock tuple.
        _resetRecoveryState();
        recoveryStateHarness.setGuardianRecoveryPendingInit(address(0), GUARDIAN_RECOVERY_TIMELOCK, block.timestamp);

        // Call: invoke `LibOrganizationGuardianRecovery.finalizeInitializeGuardianRecovery` and assert the expected
        // revert.
        vm.expectRevert(IOrganizationGuardianRecovery.InvalidGuardianRecoveryAddress.selector);
        harness.finalizeInitializeGuardianRecoveryViaLibrary();

        // Verify: confirm pending deferred-init fields, recovery configuration fields.
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
    function test_LOGR_FIGR_10__LOGR_FIGR_11_finalizePreservesRecoveryUpdateFields_andDoubleFinalizeReverts() public {
        // Setup: reset library recovery state; seed a pending deferred-init timelock tuple; seed a pending
        // recovery-guardian update.
        _resetRecoveryState();
        recoveryStateHarness.setGuardianRecoveryPendingUpdate(NEW_GUARDIAN_B, block.timestamp + 10 days, true);
        _initiateDeferredInit(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);
        uint256 canFinalizeAt = harness.getGuardianRecoveryStateViaStorage().pendingInit.pendingTimestamp;

        // Call: invoke `LibOrganizationGuardianRecovery.finalizeInitializeGuardianRecovery` and assert the expected
        // revert.
        vm.warp(canFinalizeAt);
        harness.finalizeInitializeGuardianRecoveryViaLibrary();

        vm.expectRevert(IOrganizationGuardianRecovery.NoGuardianRecoveryInitializationPending.selector);
        harness.finalizeInitializeGuardianRecoveryViaLibrary();

        // Verify: confirm pending recovery-update fields.
        GuardianRecoveryState memory state = harness.getGuardianRecoveryStateViaStorage();
        assertEq(state.pendingGuardian, NEW_GUARDIAN_B, "recovery-update pending guardian should remain untouched");
        assertEq(
            state.pendingGuardianTimestamp,
            block.timestamp + 10 days,
            "recovery-update pending timestamp should remain untouched"
        );
        assertTrue(state.isUpdateReadyForAcceptance, "recovery-update ready flag should remain untouched");
    }
}
