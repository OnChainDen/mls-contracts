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
    /// @dev Verifies cancel clears `pendingGuardian`.
    function test_clearsPendingGuardian() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);

        // Call
        harness.cancelGuardianUpdateViaLibrary();

        // Verify
        assertEq(harness.getPendingGuardianViaLibrary(), address(0), "pending guardian should clear");
    }

    /// @dev Verifies cancel clears `pendingGuardianUpdateTimestamp`.
    function test_clearsPendingGuardianUpdateTimestamp() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);

        // Call
        harness.cancelGuardianUpdateViaLibrary();

        // Verify
        assertEq(harness.getPendingGuardianUpdateTimestampViaLibrary(), 0, "pending timestamp should clear");
    }

    /// @dev Verifies cancel clears `isGuardianUpdateReadyForAcceptance`.
    function test_clearsReadyForAcceptanceFlag() public {
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

    /// @dev Verifies no pending update reverts `NoPendingGuardianUpdate`.
    function test_noPendingUpdate_revertsNoPendingGuardianUpdate() public {
        // Setup
        _clearPendingGuardianState();

        // Call
        vm.expectRevert(IOrganizationGuardian.NoPendingGuardianUpdate.selector);
        harness.cancelGuardianUpdateViaLibrary();

        // Verify
        assertEq(harness.getPendingGuardianViaLibrary(), address(0), "pending guardian should remain unset");
    }

    /// @dev Verifies cancel emits `GuardianUpdateCancelled(currentGuardian, cancelledGuardian)`.
    function test_emitsGuardianUpdateCancelled() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);

        // Call
        vm.expectEmit(true, true, false, true);
        emit IOrganizationGuardian.GuardianUpdateCancelled(GUARDIAN, NEW_GUARDIAN_A);
        harness.cancelGuardianUpdateViaLibrary();

        // Verify
        assertEq(harness.getPendingGuardianViaLibrary(), address(0), "pending guardian should clear");
    }

    /// @dev Verifies `LibOrganizationGuardian.cancelGuardianUpdate` clears the pending timestamp and emits
    /// `GuardianUpdateCancelled` with the cancelled pending guardian in one flow.
    function test_cancelGuardianUpdate_clearsPendingTimestampAndEmitsCancelledGuardian() public {
        // Setup: stage a pending guardian update so both the timestamp and cancelled guardian are non-zero.
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);

        // Call: cancel the pending update while asserting the exact cancelled-guardian event payload.
        vm.expectEmit(true, true, false, true);
        emit IOrganizationGuardian.GuardianUpdateCancelled(GUARDIAN, NEW_GUARDIAN_A);
        harness.cancelGuardianUpdateViaLibrary();

        // Verify: cancel clears the pending timestamp alongside the cancelled guardian state.
        assertEq(
            harness.getPendingGuardianUpdateTimestampViaLibrary(),
            0,
            "cancel should clear the pending finalize timestamp"
        );
    }

    /// @dev Verifies cancel before finalize clears pending state correctly.
    function test_cancelBeforeFinalize_clearsPendingStateCorrectly() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);

        // Call
        harness.cancelGuardianUpdateViaLibrary();

        // Verify
        assertEq(harness.getPendingGuardianViaLibrary(), address(0), "pending guardian should clear");
        assertEq(harness.getPendingGuardianUpdateTimestampViaLibrary(), 0, "pending timestamp should clear");
        assertFalse(harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(), "ready flag should be false");
    }

    /// @dev Verifies cancel after finalize clears ready-for-acceptance state.
    function test_cancelAfterFinalize_clearsReadyForAcceptanceState() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        vm.warp(harness.getPendingGuardianUpdateTimestampViaLibrary());
        harness.finalizeGuardianUpdateViaLibrary();

        // Call
        harness.cancelGuardianUpdateViaLibrary();

        // Verify
        assertFalse(
            harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(), "ready-for-acceptance should clear after cancel"
        );
        assertEq(harness.getPendingGuardianViaLibrary(), address(0), "pending guardian should clear");
    }

    /// @dev Verifies `LibOrganizationGuardian.cancelGuardianUpdate` succeeds after the pending timestamp has expired
    /// even when finalize has not been called yet.
    function test_cancelGuardianUpdate_afterPendingTimestampBeforeFinalizeStillSucceeds() public {
        // Setup: stage a pending guardian update and advance one second past its finalize timestamp without finalizing.
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        vm.warp(harness.getPendingGuardianUpdateTimestampViaLibrary() + 1);

        // Call: cancel the still-pending update after the expiry boundary has passed.
        harness.cancelGuardianUpdateViaLibrary();

        // Verify: cancel remains valid post-expiry and clears all pending guardian-update state.
        assertEq(harness.getPendingGuardianViaLibrary(), address(0), "post-expiry cancel should clear pending guardian");
        assertEq(
            harness.getPendingGuardianUpdateTimestampViaLibrary(),
            0,
            "post-expiry cancel should clear pending timestamp"
        );
        assertFalse(
            harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(),
            "post-expiry cancel should leave the update not ready for acceptance"
        );
    }

    /// @dev Verifies accepting after cancel reverts `NoPendingGuardianUpdate`.
    function test_cancelAfterFinalize_thenAccept_revertsNoPendingGuardianUpdate() public {
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

    /// @dev Verifies `LibOrganizationGuardian.cancelGuardianUpdate` lets a later re-initiation compute a fresh
    /// finalize timestamp from the new start time.
    function test_cancelGuardianUpdate_reinitiationComputesFreshPendingTimestamp() public {
        // Setup: stage and cancel one guardian update, then move time forward before starting a new one.
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        harness.cancelGuardianUpdateViaLibrary();
        vm.warp(block.timestamp + 5 days);
        uint256 expectedFreshCanFinalizeAt = block.timestamp + ADMIN_OPERATION_TIMELOCK;

        // Call: initiate a new guardian update after the prior pending state was cancelled.
        harness.initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_B);

        // Verify: the new pending timestamp is recomputed from the new start time rather than reusing stale state.
        assertEq(
            harness.getPendingGuardianUpdateTimestampViaLibrary(),
            expectedFreshCanFinalizeAt,
            "re-initiation should compute a fresh pending timestamp"
        );
        assertEq(harness.getPendingGuardianViaLibrary(), NEW_GUARDIAN_B, "new pending guardian should be stored");
    }
}
