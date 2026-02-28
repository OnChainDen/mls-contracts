// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
import {
    LibOrganizationGuardianSuiteBase
} from "test/organization/libraries/LibOrganizationGuardian/LibOrganizationGuardianSuiteBase.sol";

/**
 * @dev Unit tests for `LibOrganizationGuardian.cancelGuardianUpdate`.
 */
contract LibOrganizationGuardianCancelGuardianUpdateTest is LibOrganizationGuardianSuiteBase {
    /// @dev Verifies LOG-CGU-1: cancel clears `pendingGuardian`.
    function test_LOG_CGU_1_clearsPendingGuardian() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);

        // Call
        harness.cancelGuardianUpdateViaLibrary();

        // Verify
        assertEq(harness.getPendingGuardianViaLibrary(), address(0), "pending guardian should clear");
    }

    /// @dev Verifies LOG-CGU-2: cancel clears `pendingGuardianUpdateTimestamp`.
    function test_LOG_CGU_2_clearsPendingGuardianUpdateTimestamp() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);

        // Call
        harness.cancelGuardianUpdateViaLibrary();

        // Verify
        assertEq(harness.getPendingGuardianUpdateTimestampViaLibrary(), 0, "pending timestamp should clear");
    }

    /// @dev Verifies LOG-CGU-3: cancel clears `isGuardianUpdateReadyForAcceptance`.
    function test_LOG_CGU_3_clearsReadyForAcceptanceFlag() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        vm.warp(harness.getPendingGuardianUpdateTimestampViaLibrary());
        harness.finalizeGuardianUpdateViaLibrary();
        assertTrue(harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(), "ready flag precondition not met");

        // Call
        harness.cancelGuardianUpdateViaLibrary();

        // Verify
        assertFalse(
            harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(),
            "ready-for-acceptance flag should clear on cancel"
        );
    }

    /// @dev Verifies LOG-CGU-4: no pending update reverts `NoPendingGuardianUpdate`.
    function test_LOG_CGU_4_noPendingUpdate_revertsNoPendingGuardianUpdate() public {
        // Setup
        _clearPendingGuardianState();

        // Call
        vm.expectRevert(IOrganizationGuardian.NoPendingGuardianUpdate.selector);
        harness.cancelGuardianUpdateViaLibrary();

        // Verify
        assertEq(harness.getPendingGuardianViaLibrary(), address(0), "pending guardian should remain unset");
    }

    /// @dev Verifies LOG-CGU-5: cancel emits `GuardianUpdateCancelled(currentGuardian, cancelledGuardian)`.
    function test_LOG_CGU_5_emitsGuardianUpdateCancelled() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);

        // Call
        vm.expectEmit(true, true, false, true);
        emit IOrganizationGuardian.GuardianUpdateCancelled(GUARDIAN, NEW_GUARDIAN_A);
        harness.cancelGuardianUpdateViaLibrary();

        // Verify
        assertEq(harness.getPendingGuardianViaLibrary(), address(0), "pending guardian should clear");
    }

    /// @dev Verifies LOG-CGU-6: cancel before finalize clears pending state correctly.
    function test_LOG_CGU_6_cancelBeforeFinalize_clearsPendingStateCorrectly() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);

        // Call
        harness.cancelGuardianUpdateViaLibrary();

        // Verify
        assertEq(harness.getPendingGuardianViaLibrary(), address(0), "pending guardian should clear");
        assertEq(harness.getPendingGuardianUpdateTimestampViaLibrary(), 0, "pending timestamp should clear");
        assertFalse(harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(), "ready flag should be false");
    }

    /// @dev Verifies LOG-CGU-7: cancel after finalize clears ready-for-acceptance state.
    function test_LOG_CGU_7_cancelAfterFinalize_clearsReadyForAcceptanceState() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        vm.warp(harness.getPendingGuardianUpdateTimestampViaLibrary());
        harness.finalizeGuardianUpdateViaLibrary();

        // Call
        harness.cancelGuardianUpdateViaLibrary();

        // Verify
        assertFalse(
            harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(),
            "ready-for-acceptance should clear after cancel"
        );
        assertEq(harness.getPendingGuardianViaLibrary(), address(0), "pending guardian should clear");
    }

    /// @dev Verifies LOG-CGU-8: accepting after cancel reverts `NoPendingGuardianUpdate`.
    function test_LOG_CGU_8_cancelAfterFinalize_thenAccept_revertsNoPendingGuardianUpdate() public {
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
