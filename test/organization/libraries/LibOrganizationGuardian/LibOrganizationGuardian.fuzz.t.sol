// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdminOperationTimelock} from "interfaces/organization/IOrganizationAdminOperationTimelock.sol";
import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
import {TimelockUtils} from "libraries/TimelockUtils.sol";
import {
    LibOrganizationGuardianSuiteBase
} from "test/organization/libraries/LibOrganizationGuardian/LibOrganizationGuardianSuiteBase.sol";

/**
 * @dev Fuzz tests for `LibOrganizationGuardian`.
 */
contract LibOrganizationGuardianFuzzTest is LibOrganizationGuardianSuiteBase {
    /// @dev Verifies GFZ-1: random valid guardian addresses can complete initiate->finalize->accept flow.
    function testFuzz_GFZ_1_randomValidNewGuardian_updateFlowCompletes(address newGuardian) public {
        // Setup
        vm.assume(newGuardian != address(0));
        _clearPendingGuardianState();

        // Call
        harness.initiateGuardianUpdateViaLibrary(newGuardian);
        vm.warp(harness.getPendingGuardianUpdateTimestampViaLibrary());
        harness.finalizeGuardianUpdateViaLibrary();
        harness.acceptGuardianViaLibrary();

        // Verify
        assertEq(harness.getGuardianViaLibrary(), newGuardian, "guardian should match fuzzed valid new guardian");
    }

    /// @dev Verifies `LibOrganizationGuardian.finalizeGuardianUpdate` reverts before the admin-operation timelock
    /// expires and succeeds once it has expired.
    function testFuzz_GFZ_2__FLOGU_FINAL_106_randomBeforeAfterTimelock_finalizePassFail(
        address newGuardian,
        bool beforeTimelock,
        uint256 delta
    ) public {
        // Setup
        vm.assume(newGuardian != address(0));
        _clearPendingGuardianState();
        harness.initiateGuardianUpdateViaLibrary(newGuardian);
        uint256 canFinalizeAt = harness.getPendingGuardianUpdateTimestampViaLibrary();

        // Call
        if (beforeTimelock) {
            uint256 secondsBefore = bound(delta, 1, ADMIN_OPERATION_TIMELOCK);
            vm.assume(canFinalizeAt > secondsBefore);
            vm.warp(canFinalizeAt - secondsBefore);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IOrganizationAdminOperationTimelock.TimelockNotExpired.selector, canFinalizeAt, block.timestamp
                )
            );
            harness.finalizeGuardianUpdateViaLibrary();
        } else {
            uint256 secondsAfter = bound(delta, 0, ADMIN_OPERATION_TIMELOCK);
            vm.warp(canFinalizeAt + secondsAfter);
            harness.finalizeGuardianUpdateViaLibrary();
        }

        // Verify
        bool expectedReady = !beforeTimelock;
        assertEq(
            harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(),
            expectedReady,
            "ready flag should track finalize pass/fail branch"
        );
    }

    /// @dev Verifies GFZ-3: using `address(0)` as new guardian always reverts.
    function testFuzz_GFZ_3_zeroAddress_alwaysRevertsInvalidGuardianAddress(uint256 seed) public {
        // Setup
        if (seed % 2 == 0) {
            _clearPendingGuardianState();
        } else {
            _clearPendingGuardianState();
        }

        // Call
        vm.expectRevert(IOrganizationGuardian.InvalidGuardianAddress.selector);
        harness.initiateGuardianUpdateViaLibrary(address(0));

        // Verify
        assertEq(harness.getPendingGuardianViaLibrary(), address(0), "pending guardian should remain unset");
    }

    /// @dev Verifies GFZ-4: random non-pending callers always fail `enforceOnlyPendingGuardian`.
    function testFuzz_GFZ_4_randomNonPendingGuardians_revertOnEnforceOnlyPendingGuardian(
        address pendingGuardian,
        address caller
    ) public {
        // Setup
        vm.assume(pendingGuardian != address(0));
        vm.assume(caller != pendingGuardian);
        guardianStateHarness.setPendingGuardian(pendingGuardian);

        // Call
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardian.UnauthorizedGuardianAcceptance.selector, caller, pendingGuardian
            )
        );
        vm.prank(caller);
        harness.enforceOnlyPendingGuardianViaLibrary();

        // Verify
        assertEq(harness.getPendingGuardianViaLibrary(), pendingGuardian, "pending guardian should remain unchanged");
    }

    /// @dev Verifies `LibOrganizationGuardian.initiateGuardianUpdate` stores both the pending guardian and the
    /// finalize timestamp derived from the admin-operation timelock.
    function testFuzz_GFZ_5__FLOGU_INIT_105_randomTimelockDurations_canFinalizeTimestampMatchesDuration(
        address newGuardian,
        uint256 timelockDuration
    ) public {
        // Setup
        vm.assume(newGuardian != address(0));
        uint256 boundedDuration = bound(
            timelockDuration, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        );
        guardianStateHarness.setAdminOperationTimelockDurationSeconds(boundedDuration);
        _clearPendingGuardianState();
        uint256 expectedCanFinalizeAt = block.timestamp + boundedDuration;

        // Call
        harness.initiateGuardianUpdateViaLibrary(newGuardian);

        // Verify
        assertEq(
            harness.getPendingGuardianUpdateTimestampViaLibrary(),
            expectedCanFinalizeAt,
            "pending timestamp should equal block.timestamp + fuzzed timelock duration"
        );
        assertEq(harness.getPendingGuardianViaLibrary(), newGuardian, "pending guardian should match fuzzed guardian");
    }

    /// @dev Verifies GFZ-6: random guardians pass `enforceOnlyGuardian`, while others fail.
    function testFuzz_GFZ_6_randomGuardians_enforceOnlyGuardianPassesForGuardianFailsForOthers(
        address guardian,
        address caller
    ) public {
        // Setup
        vm.assume(guardian != address(0));
        guardianStateHarness.setGuardian(guardian);

        // Call
        vm.prank(guardian);
        harness.enforceOnlyGuardianViaLibrary();

        if (caller != guardian) {
            vm.expectRevert(
                abi.encodeWithSelector(IOrganizationGuardian.UnauthorizedGuardian.selector, caller, guardian)
            );
            vm.prank(caller);
            harness.enforceOnlyGuardianViaLibrary();
        }

        // Verify
        assertEq(harness.getGuardianViaLibrary(), guardian, "guardian should remain unchanged");
    }

    /// @dev Verifies `LibOrganizationGuardian.acceptGuardian` only succeeds after finalization and only when the
    /// pending guardian is the caller accepted by `enforceOnlyPendingGuardian`.
    /// @param newGuardian The pending guardian used for the update flow.
    /// @param caller The caller tested against the pending-guardian gate.
    /// @param finalizeUpdate Whether to finalize the pending guardian update before acceptance.
    function testFuzz_FLOGU_ACCEPT_107_acceptGuardian_requiresFinalizedStateAndPendingGuardianCaller(
        address newGuardian,
        address caller,
        bool finalizeUpdate
    ) public {
        // Setup: seed one pending guardian update and optionally finalize it before the acceptance attempt.
        vm.assume(newGuardian != address(0));
        _clearPendingGuardianState();
        harness.initiateGuardianUpdateViaLibrary(newGuardian);

        if (finalizeUpdate) {
            vm.warp(harness.getPendingGuardianUpdateTimestampViaLibrary());
            harness.finalizeGuardianUpdateViaLibrary();
        }

        // Call: enforce the pending-guardian caller gate, then attempt acceptance under the selected branch.
        if (caller != newGuardian) {
            vm.expectRevert(
                abi.encodeWithSelector(IOrganizationGuardian.UnauthorizedGuardianAcceptance.selector, caller, newGuardian)
            );
            vm.prank(caller);
            harness.enforceOnlyPendingGuardianViaLibrary();

            // Verify: a wrong caller leaves the pending guardian state untouched.
            assertEq(harness.getPendingGuardianViaLibrary(), newGuardian, "pending guardian should remain unchanged");
            return;
        }

        if (!finalizeUpdate) {
            vm.expectRevert(IOrganizationGuardian.GuardianUpdateNotReadyForAcceptance.selector);
            harness.acceptGuardianViaLibrary();

            // Verify: unfinalized updates cannot be accepted and keep the old guardian in place.
            assertEq(harness.getPendingGuardianViaLibrary(), newGuardian, "pending guardian should stay pending");
            assertFalse(
                harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(),
                "ready flag should stay false before finalize"
            );
            return;
        }

        harness.acceptGuardianViaLibrary();

        // Verify: finalized updates accepted by the pending guardian replace the guardian and clear pending state.
        assertEq(harness.getGuardianViaLibrary(), newGuardian, "accepted guardian should become current guardian");
        assertEq(harness.getPendingGuardianViaLibrary(), address(0), "accept should clear pending guardian");
        assertEq(
            harness.getPendingGuardianUpdateTimestampViaLibrary(), 0, "accept should clear pending finalize timestamp"
        );
        assertFalse(
            harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(),
            "accept should clear the ready-for-acceptance flag"
        );
    }

    /// @dev Verifies `LibOrganizationGuardian.cancelGuardianUpdate` clears all pending guardian-update state.
    /// @param newGuardian The pending guardian cleared by the cancel path.
    function testFuzz_FLOGU_CANCEL_108_cancelGuardianUpdate_clearsAllPendingState(address newGuardian) public {
        // Setup: seed one pending guardian update and mark it as finalized to ensure cancel clears every pending field.
        vm.assume(newGuardian != address(0));
        _clearPendingGuardianState();
        harness.initiateGuardianUpdateViaLibrary(newGuardian);
        vm.warp(harness.getPendingGuardianUpdateTimestampViaLibrary());
        harness.finalizeGuardianUpdateViaLibrary();

        // Call: cancel the pending guardian update.
        harness.cancelGuardianUpdateViaLibrary();

        // Verify: cancel clears the pending guardian, timestamp, and ready-for-acceptance flag.
        assertEq(harness.getPendingGuardianViaLibrary(), address(0), "cancel should clear pending guardian");
        assertEq(
            harness.getPendingGuardianUpdateTimestampViaLibrary(), 0, "cancel should clear pending finalize timestamp"
        );
        assertFalse(
            harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(),
            "cancel should clear the ready-for-acceptance flag"
        );
    }
}
