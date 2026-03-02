// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {
    LibOrganizationGuardianRecoverySuiteBase
} from "test/organization/libraries/LibOrganizationGuardianRecovery/LibOrganizationGuardianRecoverySuiteBase.sol";

/**
 * @dev Full lifecycle integration tests for guardian-recovery flows.
 */
contract LibOrganizationGuardianRecoveryIntegrationTest is LibOrganizationGuardianRecoverySuiteBase {
    /// @dev Verifies that complete recovery flow updates guardian in normal storage.
    function test_OGR_INT_1_completeRecoveryFlow_updatesGuardianInNormalStorage() public {
        // Setup: reconfigure baseline recovery address and timelock.
        _resetAndConfigureRecovery();

        // Call: initiate recovery guardian update, finalize recovery guardian update, then accept recovery guardian update.
        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        vm.warp(harness.getGuardianRecoveryStateViaStorage().pendingGuardianTimestamp);
        harness.finalizeRecoveryGuardianUpdateViaLibrary();
        harness.acceptGuardianRecoveryViaLibrary();

        // Verify: guardian updates after complete recovery flow.
        assertEq(harness.getGuardianViaLibrary(), NEW_GUARDIAN_A, "guardian should update after complete recovery flow");
    }

    /// @dev Verifies that cancel during pending then re-init with different address succeeds.
    function test_OGR_INT_2_cancelDuringPending_thenReInitiateWithDifferentAddress_succeeds() public {
        // Setup: reconfigure baseline recovery address and timelock and seed pending recovery-guardian update.
        _resetAndConfigureRecovery();
        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_A);

        // Call: cancel recovery guardian update then initiate recovery guardian update.
        harness.cancelRecoveryGuardianUpdateViaLibrary();
        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_B);

        // Verify: second pending guardian is set.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().pendingGuardian,
            NEW_GUARDIAN_B,
            "second pending guardian should be set"
        );
    }

    /// @dev Verifies that cancel after finalize clears state and old pending guardian cannot accept later.
    function test_OGR_INT_3__OGR_INT_14_cancelAfterFinalize_clearsStateAndOldPendingCannotAcceptLater() public {
        // Setup: reconfigure baseline recovery address and timelock, seed pending recovery-guardian update, and position timestamp at timelock boundary.
        _resetAndConfigureRecovery();
        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        vm.warp(harness.getGuardianRecoveryStateViaStorage().pendingGuardianTimestamp);
        harness.finalizeRecoveryGuardianUpdateViaLibrary();
        uint256 originalCanFinalizeAt = harness.getGuardianRecoveryStateViaStorage().pendingGuardianTimestamp;

        // Call: cancel recovery guardian update then accept recovery guardian update, expecting `NoPendingRecoveryGuardianUpdate` revert.
        harness.cancelRecoveryGuardianUpdateViaLibrary();
        vm.warp(originalCanFinalizeAt + 1 days);
        vm.expectRevert(IOrganizationGuardianRecovery.NoPendingRecoveryGuardianUpdate.selector);
        harness.acceptGuardianRecoveryViaLibrary();

        // Verify: guardian remains unchanged.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().pendingGuardian,
            address(0),
            "pending guardian should remain cleared after cancel"
        );
        assertEq(harness.getGuardianViaLibrary(), GUARDIAN, "guardian should remain unchanged");
    }

    /// @dev Verifies that deferred-init lifecycle sets config after timelock finalize.
    function test_OGR_INT_4_deferredInitLifecycle_configuresRecovery() public {
        // Setup: start from clean recovery state.
        harness.resetGuardianRecoveryStorageViaHarness();

        // Call: initiate deferred recovery initialization then finalize deferred recovery initialization.
        harness.initiateInitializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);
        vm.warp(harness.getGuardianRecoveryStateViaStorage().pendingInit.pendingTimestamp);
        harness.finalizeInitializeGuardianRecoveryViaLibrary();

        // Verify: recovery address should configure after deferred finalize.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().recoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS,
            "recovery address should configure after deferred finalize"
        );
    }

    /// @dev Verifies that deferred-init cancel and retry works.
    function test_OGR_INT_5_deferredInitCancelThenRetry_succeeds() public {
        // Setup: start from clean recovery state and seed pending deferred-init tuple.
        harness.resetGuardianRecoveryStorageViaHarness();
        harness.initiateInitializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);

        // Call: cancel deferred recovery initialization then initiate deferred recovery initialization.
        harness.cancelInitializeGuardianRecoveryViaLibrary();
        harness.initiateInitializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS_B, 4 days);

        // Verify: retry should set new pending deferred-init tuple.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().pendingInit.pendingRecoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS_B,
            "retry should set new pending deferred-init tuple"
        );
    }

    /// @dev Verifies that deferred-init finalize followed by full recovery update flow succeeds.
    function test_OGR_INT_6_fullLifecycleAfterDeferredInit_succeeds() public {
        // Setup: start from clean recovery state, seed pending deferred-init tuple, and position timestamp at timelock boundary.
        harness.resetGuardianRecoveryStorageViaHarness();
        harness.initiateInitializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);
        vm.warp(harness.getGuardianRecoveryStateViaStorage().pendingInit.pendingTimestamp);
        harness.finalizeInitializeGuardianRecoveryViaLibrary();

        // Call: initiate recovery guardian update, finalize recovery guardian update, then accept recovery guardian update.
        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        vm.warp(harness.getGuardianRecoveryStateViaStorage().pendingGuardianTimestamp);
        harness.finalizeRecoveryGuardianUpdateViaLibrary();
        harness.acceptGuardianRecoveryViaLibrary();

        // Verify: guardian updates in post-deferred full lifecycle.
        assertEq(
            harness.getGuardianViaLibrary(), NEW_GUARDIAN_A, "guardian should update in post-deferred full lifecycle"
        );
    }

    /// @dev Verifies that recovery and normal guardian flows can run in parallel and complete independently.
    function test_OGR_INT_7_recoveryAndNormalFlows_parallelAndIndependent() public {
        // Setup: reconfigure baseline recovery address and timelock and seed pending recovery-guardian update.
        _resetAndConfigureRecovery();
        harness.initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_B);

        // Call: finalize normal guardian update, accept normal guardian update, then finalize recovery guardian update.
        vm.warp(harness.getPendingGuardianUpdateTimestampViaLibrary());
        harness.finalizeGuardianUpdateViaLibrary();
        harness.acceptGuardianViaLibrary();

        vm.warp(harness.getGuardianRecoveryStateViaStorage().pendingGuardianTimestamp);
        harness.finalizeRecoveryGuardianUpdateViaLibrary();
        harness.acceptGuardianRecoveryViaLibrary();

        // Verify: normal pending state clears.
        assertEq(
            harness.getGuardianViaLibrary(),
            NEW_GUARDIAN_B,
            "latest completed flow should set guardian while both flows complete independently"
        );
        assertEq(harness.getPendingGuardianViaLibrary(), address(0), "normal pending state should clear");
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().pendingGuardian,
            address(0),
            "recovery pending state should clear"
        );
    }

    /// @dev Verifies that completing one flow does not block later use of the other flow.
    function test_OGR_INT_8__OGR_INT_9_eachFlowStillUsableAfterOtherCompletes() public {
        // Setup: reconfigure baseline recovery address and timelock.
        _resetAndConfigureRecovery();

        // Call: initiate recovery guardian update, finalize recovery guardian update, then accept recovery guardian update.
        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        vm.warp(harness.getGuardianRecoveryStateViaStorage().pendingGuardianTimestamp);
        harness.finalizeRecoveryGuardianUpdateViaLibrary();
        harness.acceptGuardianRecoveryViaLibrary();

        harness.initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_B);
        vm.warp(harness.getPendingGuardianUpdateTimestampViaLibrary());
        harness.finalizeGuardianUpdateViaLibrary();
        harness.acceptGuardianViaLibrary();

        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_C);
        vm.warp(harness.getGuardianRecoveryStateViaStorage().pendingGuardianTimestamp);
        harness.finalizeRecoveryGuardianUpdateViaLibrary();
        harness.acceptGuardianRecoveryViaLibrary();

        // Verify: both flows remain usable sequentially.
        assertEq(harness.getGuardianViaLibrary(), NEW_GUARDIAN_C, "both flows should remain usable sequentially");
    }

    /// @dev Verifies that multiple sequential recovery updates can complete.
    function test_OGR_INT_10_multipleSequentialRecoveryUpdates_complete() public {
        // Setup: reconfigure baseline recovery address and timelock.
        _resetAndConfigureRecovery();

        // Call: initiate recovery guardian update, finalize recovery guardian update, then accept recovery guardian update.
        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        vm.warp(harness.getGuardianRecoveryStateViaStorage().pendingGuardianTimestamp);
        harness.finalizeRecoveryGuardianUpdateViaLibrary();
        harness.acceptGuardianRecoveryViaLibrary();

        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_B);
        vm.warp(harness.getGuardianRecoveryStateViaStorage().pendingGuardianTimestamp);
        harness.finalizeRecoveryGuardianUpdateViaLibrary();
        harness.acceptGuardianRecoveryViaLibrary();

        // Verify: second recovery update should complete.
        assertEq(harness.getGuardianViaLibrary(), NEW_GUARDIAN_B, "second recovery update should complete");
    }

    /// @dev Verifies that deferred-init finalize/cancel are idempotent with second call reverting.
    function test_OGR_INT_15_deferredInitIdempotency_secondFinalizeOrCancelRevertsNoPending() public {
        // Setup: start from clean recovery state and seed pending deferred-init tuple.
        harness.resetGuardianRecoveryStorageViaHarness();
        harness.initiateInitializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);

        // Call: cancel deferred recovery initialization, initiate deferred recovery initialization, then finalize deferred recovery initialization, expecting `NoGuardianRecoveryInitializationPending` revert.
        harness.cancelInitializeGuardianRecoveryViaLibrary();
        vm.expectRevert(IOrganizationGuardianRecovery.NoGuardianRecoveryInitializationPending.selector);
        harness.cancelInitializeGuardianRecoveryViaLibrary();

        harness.initiateInitializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);
        vm.warp(harness.getGuardianRecoveryStateViaStorage().pendingInit.pendingTimestamp);
        harness.finalizeInitializeGuardianRecoveryViaLibrary();

        vm.expectRevert(IOrganizationGuardianRecovery.NoGuardianRecoveryInitializationPending.selector);
        harness.finalizeInitializeGuardianRecoveryViaLibrary();

        // Verify: pending init remains cleared after idempotent second calls.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().pendingInit.pendingTimestamp,
            0,
            "pending init should remain cleared after idempotent second calls"
        );
    }
}
