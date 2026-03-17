// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdminOperationTimelock} from "interfaces/organization/IOrganizationAdminOperationTimelock.sol";
import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
import {
    LibOrganizationGuardianSuiteBase
} from "test/organization/libraries/LibOrganizationGuardian/LibOrganizationGuardianSuiteBase.sol";

/**
 * @dev Unit tests for `LibOrganizationGuardian.finalizeGuardianUpdate`.
 */
contract LibOrganizationGuardianFinalizeGuardianUpdateTest is LibOrganizationGuardianSuiteBase {
    /// @dev Verifies LOG-FGU-1: finalize after timelock marks update ready for acceptance.
    function test_LOG_FGU_1_afterTimelock_setsReadyForAcceptanceTrue() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        vm.warp(harness.getPendingGuardianUpdateTimestampViaLibrary());

        // Call
        harness.finalizeGuardianUpdateViaLibrary();

        // Verify
        assertTrue(
            harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(),
            "ready-for-acceptance should be true after finalize"
        );
    }

    /// @dev Verifies LOG-FGU-2: finalize before timelock reverts `TimelockNotExpired`.
    function test_LOG_FGU_2__LOG_AOTIGU_3__LOG_AOTFGU_1_beforeTimelock_revertsTimelockNotExpired() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        uint256 canFinalizeAt = harness.getPendingGuardianUpdateTimestampViaLibrary();

        // Call
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdminOperationTimelock.TimelockNotExpired.selector, canFinalizeAt, block.timestamp
            )
        );
        harness.finalizeGuardianUpdateViaLibrary();

        // Verify
        assertFalse(
            harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(),
            "ready-for-acceptance should remain false before timelock"
        );
    }

    /// @dev Verifies LOG-FGU-3: finalize at exact timelock expiry succeeds.
    function test_LOG_FGU_3__LOG_AOTFGU_2_atExactTimelockExpiry_succeeds() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        vm.warp(harness.getPendingGuardianUpdateTimestampViaLibrary());

        // Call
        harness.finalizeGuardianUpdateViaLibrary();

        // Verify
        assertTrue(harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(), "finalize should succeed at expiry");
    }

    /// @dev Verifies `LibOrganizationGuardian.finalizeGuardianUpdate` succeeds after the pending timestamp has already
    /// passed.
    function test_LOG_AOTFGU_3_finalizeGuardianUpdate_afterPendingTimestampSucceeds() public {
        // Setup: stage a pending guardian update and advance one second past the stored finalize timestamp.
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        vm.warp(harness.getPendingGuardianUpdateTimestampViaLibrary() + 1);

        // Call: finalize the pending guardian update after expiry.
        harness.finalizeGuardianUpdateViaLibrary();

        // Verify: finalize succeeds after expiry and marks the update ready for acceptance.
        assertTrue(
            harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(),
            "finalize should succeed after the pending timestamp has passed"
        );
    }

    /// @dev Verifies `LibOrganizationGuardian.finalizeGuardianUpdate` sets the ready flag while preserving the
    /// pending guardian and pending timestamp until accept or cancel clears them.
    function test_LOG_AOTFGU_4_finalizeGuardianUpdate_preservesPendingGuardianAndTimestampWhileMarkingReady() public {
        // Setup: stage a pending guardian update and record its pending tuple before finalization.
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        uint256 canFinalizeAt = harness.getPendingGuardianUpdateTimestampViaLibrary();
        vm.warp(canFinalizeAt);

        // Call: finalize the pending guardian update at the exact expiry boundary.
        harness.finalizeGuardianUpdateViaLibrary();

        // Verify: finalize only toggles readiness and keeps the pending guardian tuple intact.
        assertTrue(harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(), "finalize should set ready=true");
        assertEq(harness.getPendingGuardianViaLibrary(), NEW_GUARDIAN_A, "finalize should preserve pending guardian");
        assertEq(
            harness.getPendingGuardianUpdateTimestampViaLibrary(),
            canFinalizeAt,
            "finalize should preserve the pending timestamp"
        );
    }

    /// @dev Verifies `LibOrganizationGuardian.finalizeGuardianUpdate` reverts with `NoPendingGuardianUpdate` after the
    /// pending update was cancelled, even once the cancelled timestamp has passed.
    function test_LOG_AOTFGU_5_finalizeGuardianUpdate_afterCancellationAndExpiryRevertsNoPendingGuardianUpdate()
        public
    {
        // Setup: stage and cancel a pending guardian update, then advance past the original finalize timestamp.
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        uint256 cancelledCanFinalizeAt = harness.getPendingGuardianUpdateTimestampViaLibrary();
        harness.cancelGuardianUpdateViaLibrary();
        vm.warp(cancelledCanFinalizeAt + 1);

        // Call: attempt to finalize the cancelled update after its original timestamp has passed.
        vm.expectRevert(IOrganizationGuardian.NoPendingGuardianUpdate.selector);
        harness.finalizeGuardianUpdateViaLibrary();

        // Verify: cancelled state remains cleared and cannot be revived by waiting out the old timestamp.
        assertEq(harness.getPendingGuardianViaLibrary(), address(0), "cancelled update should remain cleared");
    }

    /// @dev Verifies `LibOrganizationGuardian.finalizeGuardianUpdate` reverts with `NoPendingGuardianUpdate` after the
    /// pending guardian already accepted the finalized update.
    function test_LOG_AOTFGU_6_finalizeGuardianUpdate_afterAcceptanceAndOldExpiryRevertsNoPendingGuardianUpdate()
        public
    {
        // Setup: complete a full initiate-finalize-accept flow and then advance past the old finalize timestamp.
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        uint256 originalCanFinalizeAt = harness.getPendingGuardianUpdateTimestampViaLibrary();
        vm.warp(originalCanFinalizeAt);
        harness.finalizeGuardianUpdateViaLibrary();
        harness.acceptGuardianViaLibrary();
        vm.warp(originalCanFinalizeAt + 1);

        // Call: attempt to finalize again using the stale timestamp from the already-accepted update.
        vm.expectRevert(IOrganizationGuardian.NoPendingGuardianUpdate.selector);
        harness.finalizeGuardianUpdateViaLibrary();

        // Verify: the accepted guardian remains current and no pending update is recreated.
        assertEq(harness.getGuardianViaLibrary(), NEW_GUARDIAN_A, "accepted guardian should remain current");
        assertEq(harness.getPendingGuardianViaLibrary(), address(0), "accepted update should leave no pending guardian");
    }

    /// @dev Verifies LOG-FGU-4: no pending update reverts `NoPendingGuardianUpdate`.
    function test_LOG_FGU_4_noPendingUpdate_revertsNoPendingGuardianUpdate() public {
        // Setup
        _clearPendingGuardianState();

        // Call
        vm.expectRevert(IOrganizationGuardian.NoPendingGuardianUpdate.selector);
        harness.finalizeGuardianUpdateViaLibrary();

        // Verify
        assertFalse(
            harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(),
            "ready-for-acceptance should remain false without pending update"
        );
    }

    /// @dev Verifies LOG-FGU-5: finalize emits `GuardianUpdateFinalized`.
    function test_LOG_FGU_5_emitsGuardianUpdateFinalized() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        vm.warp(harness.getPendingGuardianUpdateTimestampViaLibrary());

        // Call
        vm.expectEmit(true, false, false, true);
        emit IOrganizationGuardian.GuardianUpdateFinalized(NEW_GUARDIAN_A);
        harness.finalizeGuardianUpdateViaLibrary();

        // Verify
        assertTrue(harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(), "ready flag should be true");
    }

    /// @dev Verifies LOG-FGU-6: finalize does not mutate guardian, only marks ready state.
    function test_LOG_FGU_6_finalizeDoesNotChangeGuardian_onlyMarksReady() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        vm.warp(harness.getPendingGuardianUpdateTimestampViaLibrary());

        // Call
        harness.finalizeGuardianUpdateViaLibrary();

        // Verify
        assertEq(harness.getGuardianViaLibrary(), GUARDIAN, "guardian should not change during finalize");
        assertEq(harness.getPendingGuardianViaLibrary(), NEW_GUARDIAN_A, "pending guardian should remain set");
        assertTrue(harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(), "ready flag should become true");
    }

    /// @dev Verifies LOG-FGU-7: double finalize is an idempotent no-op after first success.
    function test_LOG_FGU_7_doubleFinalize_secondCallIsNoOp() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        vm.warp(harness.getPendingGuardianUpdateTimestampViaLibrary());
        harness.finalizeGuardianUpdateViaLibrary();

        // Call
        harness.finalizeGuardianUpdateViaLibrary();

        // Verify
        assertEq(harness.getGuardianViaLibrary(), GUARDIAN, "guardian should remain unchanged");
        assertEq(harness.getPendingGuardianViaLibrary(), NEW_GUARDIAN_A, "pending guardian should remain set");
        assertTrue(harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(), "ready flag should stay true");
    }
}
