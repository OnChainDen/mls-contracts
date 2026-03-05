// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
import {
    LibOrganizationGuardianSuiteBase
} from "test/organization/libraries/LibOrganizationGuardian/LibOrganizationGuardianSuiteBase.sol";
import {GuardianRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Integration tests for combined guardian lifecycle behavior.
 */
contract LibOrganizationGuardianIntegrationTest is LibOrganizationGuardianSuiteBase {
    /// @dev Verifies GINT-1: initiate -> finalize -> accept updates guardian.
    function test_GINT_1_completeFlow_initiateFinalizeAccept_updatesGuardian() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        vm.warp(harness.getPendingGuardianUpdateTimestampViaLibrary());

        // Call
        harness.finalizeGuardianUpdateViaLibrary();
        harness.acceptGuardianViaLibrary();

        // Verify
        assertEq(harness.getGuardianViaLibrary(), NEW_GUARDIAN_A, "guardian should update after complete flow");
        assertEq(harness.getPendingGuardianViaLibrary(), address(0), "pending guardian should clear");
    }

    /// @dev Verifies GINT-2: cancel during pending allows re-initiation with a different address.
    function test_GINT_2_cancelDuringPending_thenInitiateAgainWithDifferentAddress_succeeds() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);

        // Call
        harness.cancelGuardianUpdateViaLibrary();
        harness.initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_B);

        // Verify
        assertEq(harness.getPendingGuardianViaLibrary(), NEW_GUARDIAN_B, "second initiated guardian should be pending");
    }

    /// @dev Verifies GINT-3: cancel after finalize clears all pending guardian state.
    function test_GINT_3_cancelAfterFinalize_clearsAllPendingState() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        vm.warp(harness.getPendingGuardianUpdateTimestampViaLibrary());
        harness.finalizeGuardianUpdateViaLibrary();

        // Call
        harness.cancelGuardianUpdateViaLibrary();

        // Verify
        assertEq(harness.getPendingGuardianViaLibrary(), address(0), "pending guardian should clear");
        assertEq(harness.getPendingGuardianUpdateTimestampViaLibrary(), 0, "pending timestamp should clear");
        assertFalse(harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(), "ready flag should clear");
    }

    /// @dev Verifies GINT-4: two sequential full updates can complete successfully.
    function test_GINT_4_multipleSequentialUpdates_completeFirstThenSecond() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        vm.warp(harness.getPendingGuardianUpdateTimestampViaLibrary());
        harness.finalizeGuardianUpdateViaLibrary();
        harness.acceptGuardianViaLibrary();

        // Call
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_B);
        vm.warp(harness.getPendingGuardianUpdateTimestampViaLibrary());
        harness.finalizeGuardianUpdateViaLibrary();
        harness.acceptGuardianViaLibrary();

        // Verify
        assertEq(harness.getGuardianViaLibrary(), NEW_GUARDIAN_B, "second completed update should set new guardian");
        assertEq(harness.getPendingGuardianViaLibrary(), address(0), "pending guardian should clear after second flow");
    }

    /// @dev Verifies GINT-5: normal and recovery flows can both hold pending updates simultaneously.
    function test_GINT_5_normalAndRecoveryFlow_canBothBePendingSimultaneously() public {
        // Setup
        _initializeGuardianRecoveryConfig();

        // Call
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_B);

        // Verify
        GuardianRecoveryState memory recoveryState = harness.getGuardianRecoveryStateViaStorage();
        assertEq(harness.getPendingGuardianViaLibrary(), NEW_GUARDIAN_A, "normal flow pending guardian should be set");
        assertEq(recoveryState.pendingGuardian, NEW_GUARDIAN_B, "recovery flow pending guardian should be set");
    }

    /// @dev Verifies GINT-6: accepting recovery update changes guardian without clearing normal-flow pending state.
    function test_GINT_6_recoveryCompletion_updatesGuardianWithoutClearingNormalPendingState() public {
        // Setup
        _initializeGuardianRecoveryConfig();
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_B);
        GuardianRecoveryState memory recoveryStateBeforeFinalize = harness.getGuardianRecoveryStateViaStorage();
        vm.warp(recoveryStateBeforeFinalize.pendingGuardianTimestamp);

        // Call
        harness.finalizeRecoveryGuardianUpdateViaLibrary();
        harness.acceptGuardianRecoveryViaLibrary();

        // Verify
        assertEq(harness.getGuardianViaLibrary(), NEW_GUARDIAN_B, "guardian should update from recovery completion");
        assertEq(
            harness.getPendingGuardianViaLibrary(),
            NEW_GUARDIAN_A,
            "normal flow pending guardian should remain untouched"
        );
        assertFalse(
            harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(),
            "normal flow ready flag should remain as previously set"
        );
    }

    /// @dev Verifies GINT-7: guardian change via recovery updates guardian-only authorization to the new guardian.
    function test_GINT_7_recoveryGuardianChange_updatesOnlyGuardianAuthorizationForNormalFlow() public {
        // Setup
        _initializeGuardianRecoveryConfig();
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_B);
        GuardianRecoveryState memory recoveryState = harness.getGuardianRecoveryStateViaStorage();
        vm.warp(recoveryState.pendingGuardianTimestamp);
        harness.finalizeRecoveryGuardianUpdateViaLibrary();
        harness.acceptGuardianRecoveryViaLibrary();

        // Call
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationGuardian.UnauthorizedGuardian.selector, GUARDIAN, NEW_GUARDIAN_B)
        );
        vm.prank(GUARDIAN);
        harness.enforceOnlyGuardianViaLibrary();

        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationGuardian.UnauthorizedGuardian.selector, NEW_GUARDIAN_A, NEW_GUARDIAN_B)
        );
        vm.prank(NEW_GUARDIAN_A);
        harness.enforceOnlyGuardianViaLibrary();

        vm.prank(NEW_GUARDIAN_B);
        harness.enforceOnlyGuardianViaLibrary();
        assertEq(
            harness.getPendingGuardianViaLibrary(),
            NEW_GUARDIAN_A,
            "normal flow pending guardian should still be intact before cancel"
        );
        harness.cancelGuardianUpdateViaLibrary();

        // Verify
        assertEq(harness.getGuardianViaLibrary(), NEW_GUARDIAN_B, "new guardian should remain authorized");
        assertEq(
            harness.getPendingGuardianViaLibrary(), address(0), "new guardian-controlled cancel should clear pending"
        );
    }

    /// @dev Verifies GINT-8: canceled pending update cannot be accepted even after original timelock passes.
    function test_GINT_8_cancelDuringPending_thenWaitPastTimelock_acceptStillReverts() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        uint256 originalCanFinalizeAt = harness.getPendingGuardianUpdateTimestampViaLibrary();
        harness.cancelGuardianUpdateViaLibrary();
        vm.warp(originalCanFinalizeAt + 1);

        // Call
        vm.expectRevert(IOrganizationGuardian.NoPendingGuardianUpdate.selector);
        harness.acceptGuardianViaLibrary();

        // Verify
        assertEq(harness.getGuardianViaLibrary(), GUARDIAN, "guardian should remain unchanged");
    }

    /// @dev Verifies GINT-9: canceled finalized update cannot be accepted.
    function test_GINT_9_cancelAfterFinalize_acceptRevertsNoPendingGuardianUpdate() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        vm.warp(harness.getPendingGuardianUpdateTimestampViaLibrary());
        harness.finalizeGuardianUpdateViaLibrary();
        harness.cancelGuardianUpdateViaLibrary();

        // Call
        vm.expectRevert(IOrganizationGuardian.NoPendingGuardianUpdate.selector);
        harness.acceptGuardianViaLibrary();

        // Verify
        assertEq(harness.getGuardianViaLibrary(), GUARDIAN, "guardian should remain unchanged");
    }
}
