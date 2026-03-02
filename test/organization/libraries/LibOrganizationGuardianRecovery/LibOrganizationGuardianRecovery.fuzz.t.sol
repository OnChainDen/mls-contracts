// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdminOperationTimelock} from "interfaces/organization/IOrganizationAdminOperationTimelock.sol";
import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {TimelockUtils} from "libraries/TimelockUtils.sol";
import {
    LibOrganizationGuardianRecoverySuiteBase
} from "test/organization/libraries/LibOrganizationGuardianRecovery/LibOrganizationGuardianRecoverySuiteBase.sol";
import {GuardianRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Fuzz tests for guardian-recovery flows.
 */
contract LibOrganizationGuardianRecoveryFuzzTest is LibOrganizationGuardianRecoverySuiteBase {
    /// @dev Verifies that random non-zero recovery addresses with valid timelocks configure successfully.
    function testFuzz_OGR_FZ_1_randomNonZeroRecoveryAddress_validTimelock_configures(
        address recoveryAddress,
        uint256 timelock
    ) public {
        // Setup: reset library recovery state.
        vm.assume(recoveryAddress != address(0));
        uint256 boundedTimelock =
            bound(timelock, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS);
        _resetRecoveryState();

        // Call: invoke `LibOrganizationGuardianRecovery.initializeGuardianRecovery`.
        harness.initializeGuardianRecoveryViaLibrary(recoveryAddress, boundedTimelock);

        // Verify: confirm recovery configuration fields.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().recoveryAddress,
            recoveryAddress,
            "recovery address should match fuzz input"
        );
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().timelockDurationSeconds,
            boundedTimelock,
            "timelock should match bounded fuzz input"
        );
    }

    /// @dev Verifies that validation helper accepts in-range timelocks and rejects out-of-range values.
    function testFuzz_OGR_FZ_2__OGR_FZ_3_validateParams_acceptsInRangeRejectsOutOfRange(
        address recoveryAddress,
        uint256 timelock
    ) public {
        // Setup: use default fixture state.
        vm.assume(recoveryAddress != address(0));

        // Call: invoke `LibOrganizationGuardianRecovery.validateGuardianRecoveryParamsOrRevert` and assert the expected
        // revert.
        if (
            timelock >= TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS
                && timelock <= TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        ) {
            harness.validateGuardianRecoveryParamsOrRevertViaLibrary(recoveryAddress, timelock);
        } else {
            vm.expectRevert();
            harness.validateGuardianRecoveryParamsOrRevertViaLibrary(recoveryAddress, timelock);
        }

        // Verify: confirm the asserted post-conditions.
        assertTrue(true, "validation branch executed");
    }

    /// @dev Verifies that finalize behavior follows timestamp relation and pending timestamp equals
    /// block.timestamp+duration.
    function testFuzz_OGR_FZ_4__OGR_FZ_5__OGR_FZ_9_finalizeBeforeAfterTimelock_behavesByTimestamp(
        uint256 timelock,
        uint256 delta
    ) public {
        // Setup: reset library recovery state.
        uint256 boundedTimelock =
            bound(timelock, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS);
        _resetRecoveryState();
        harness.initializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, boundedTimelock);

        // Call: run the multi-step flow (`LibOrganizationGuardianRecovery.initiateRecoveryGuardianUpdate`,
        // `LibOrganizationGuardianRecovery.finalizeRecoveryGuardianUpdate`) and assert the revert branch.
        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        uint256 canFinalizeAt = harness.getGuardianRecoveryStateViaStorage().pendingGuardianTimestamp;
        assertEq(
            canFinalizeAt,
            block.timestamp + boundedTimelock,
            "pending timestamp should equal block.timestamp + duration"
        );

        if (delta % 2 == 0) {
            uint256 beforeSeconds = bound(delta, 1, boundedTimelock);
            vm.warp(canFinalizeAt - beforeSeconds);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IOrganizationAdminOperationTimelock.TimelockNotExpired.selector, canFinalizeAt, block.timestamp
                )
            );
            harness.finalizeRecoveryGuardianUpdateViaLibrary();
            assertFalse(
                harness.getGuardianRecoveryStateViaStorage().isUpdateReadyForAcceptance,
                "ready flag should stay false before expiry"
            );
        } else {
            uint256 afterSeconds = bound(delta, 0, boundedTimelock);
            vm.warp(canFinalizeAt + afterSeconds);
            harness.finalizeRecoveryGuardianUpdateViaLibrary();
            assertTrue(
                harness.getGuardianRecoveryStateViaStorage().isUpdateReadyForAcceptance,
                "ready flag should be true at/after expiry"
            );
        }

        // Verify: confirm the asserted post-conditions.
        assertTrue(true, "finalize branch behavior matched timestamp relation");
    }

    /// @dev Verifies that random non-zero guardians complete flow while zero guardian always reverts on initiate.
    function testFuzz_OGR_FZ_6__OGR_FZ_10_randomGuardiansOrZero_initiateBehavior(address newGuardian) public {
        // Setup: configure recovery address/timelock on a clean state.
        _resetAndConfigureRecovery();

        // Call: run the multi-step flow (`LibOrganizationGuardianRecovery.initiateRecoveryGuardianUpdate`,
        // `LibOrganizationGuardianRecovery.finalizeRecoveryGuardianUpdate`,
        // `LibOrganizationGuardianRecovery.acceptGuardianRecovery`) and assert the revert branch.
        if (newGuardian == address(0)) {
            vm.expectRevert(IOrganizationGuardianRecovery.InvalidNewGuardianAddress.selector);
            harness.initiateRecoveryGuardianUpdateViaLibrary(address(0));
        } else {
            harness.initiateRecoveryGuardianUpdateViaLibrary(newGuardian);
            vm.warp(harness.getGuardianRecoveryStateViaStorage().pendingGuardianTimestamp);
            harness.finalizeRecoveryGuardianUpdateViaLibrary();
            harness.acceptGuardianRecoveryViaLibrary();
        }

        // Verify: confirm guardian value in normal guardian storage.
        if (newGuardian != address(0)) {
            assertEq(harness.getGuardianViaLibrary(), newGuardian, "guardian should become fuzzed non-zero guardian");
        }
    }

    /// @dev Verifies that random non-recovery addresses revert enforceOnlyGuardianRecoveryAddress.
    function testFuzz_OGR_FZ_7_randomNonRecoveryAddresses_revertOnEnforceOnlyGuardianRecoveryAddress(address caller)
        public
    {
        // Setup: configure recovery address/timelock on a clean state.
        vm.assume(caller != GUARDIAN_RECOVERY_ADDRESS);
        _resetAndConfigureRecovery();

        // Call: invoke `LibOrganizationGuardianRecovery.enforceOnlyGuardianRecoveryAddress` as `caller` and assert the
        // expected revert.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.UnauthorizedGuardianRecoveryAddress.selector,
                caller,
                GUARDIAN_RECOVERY_ADDRESS
            )
        );
        vm.prank(caller);
        harness.enforceOnlyGuardianRecoveryAddressViaLibrary();

        // Verify: confirm recovery configuration fields.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().recoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS,
            "config should remain unchanged"
        );
    }

    /// @dev Verifies that random non-pending-guardian addresses revert enforceOnlyRecoveryPendingGuardian.
    function testFuzz_OGR_FZ_8_randomNonPendingGuardianAddresses_revertOnEnforceOnlyRecoveryPendingGuardian(
        address pendingGuardian,
        address caller
    ) public {
        // Setup: configure recovery address/timelock on a clean state; seed a pending recovery-guardian update.
        vm.assume(pendingGuardian != address(0));
        vm.assume(caller != pendingGuardian);
        _resetAndConfigureRecovery();
        recoveryStateHarness.setGuardianRecoveryPendingUpdate(pendingGuardian, block.timestamp + 1 days, false);

        // Call: invoke `LibOrganizationGuardianRecovery.enforceOnlyRecoveryPendingGuardian` as `caller` and assert the
        // expected revert.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.UnauthorizedRecoveryGuardianAcceptance.selector, caller, pendingGuardian
            )
        );
        vm.prank(caller);
        harness.enforceOnlyRecoveryPendingGuardianViaLibrary();

        // Verify: confirm pending recovery-update state remains unchanged.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().pendingGuardian,
            pendingGuardian,
            "pending guardian should remain unchanged"
        );
    }

    /// @dev Verifies that random state transitions never change guardian except via successful accept.
    function testFuzz_OGR_FZ_11_statefulSequence_guardianChangesOnlyOnSuccessfulAccept(uint256 seed, uint8 steps)
        public
    {
        // Setup: configure recovery address/timelock on a clean state.
        _resetAndConfigureRecovery();
        uint256 count = bound(steps, 1, 20);
        address[] memory candidates = new address[](3);
        candidates[0] = address(uint160(uint256(keccak256(abi.encode(seed, "a"))) | 1));
        candidates[1] = address(uint160(uint256(keccak256(abi.encode(seed, "b"))) | 1));
        candidates[2] = address(uint160(uint256(keccak256(abi.encode(seed, "c"))) | 1));

        // Call: run a random operation sequence (initiate/finalize/cancel/accept/no-op) and track guardian changes.
        for (uint256 i = 0; i < count; i++) {
            uint8 op = uint8(uint256(keccak256(abi.encode(seed, i))) % 5);
            address guardianBefore = harness.getGuardianViaLibrary();

            if (op == 0) {
                (bool success,) = address(harness)
                    .call(abi.encodeCall(harness.initiateRecoveryGuardianUpdateViaLibrary, (candidates[i % 3])));
                if (success) {
                    assertEq(harness.getGuardianViaLibrary(), guardianBefore, "initiate must not change guardian");
                }
            } else if (op == 1) {
                (bool success,) =
                    address(harness).call(abi.encodeCall(harness.finalizeRecoveryGuardianUpdateViaLibrary, ()));
                if (success) {
                    assertEq(harness.getGuardianViaLibrary(), guardianBefore, "finalize must not change guardian");
                }
            } else if (op == 2) {
                (bool success,) =
                    address(harness).call(abi.encodeCall(harness.cancelRecoveryGuardianUpdateViaLibrary, ()));
                if (success) {
                    assertEq(harness.getGuardianViaLibrary(), guardianBefore, "cancel must not change guardian");
                }
            } else if (op == 3) {
                (bool success,) = address(harness).call(abi.encodeCall(harness.acceptGuardianRecoveryViaLibrary, ()));
                if (!success) {
                    assertEq(harness.getGuardianViaLibrary(), guardianBefore, "failed accept must not change guardian");
                }
            } else {
                vm.warp(block.timestamp + (uint256(uint8(seed)) % 3 days));
            }
        }

        // Verify: confirm guardian value in normal guardian storage.
        assertTrue(harness.getGuardianViaLibrary() != address(0), "guardian should remain non-zero throughout sequence");
    }

    /// @dev Verifies that configured state always has non-zero in-range timelock when recoveryAddress is non-zero.
    function testFuzz_OGR_FZ_12_configCoherence_whenConfiguredTimelockIsNonZeroAndInRange(
        address recoveryAddress,
        uint256 timelock
    ) public {
        // Setup: reset library recovery state.
        _resetRecoveryState();

        // Call: invoke `LibOrganizationGuardianRecovery.initializeGuardianRecovery`.
        if (recoveryAddress != address(0)) {
            uint256 bounded = bound(
                timelock, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            );
            harness.initializeGuardianRecoveryViaLibrary(recoveryAddress, bounded);
        }

        // Verify: confirm recovery configuration fields.
        GuardianRecoveryState memory state = harness.getGuardianRecoveryStateViaStorage();
        if (state.recoveryAddress != address(0)) {
            assertTrue(state.timelockDurationSeconds != 0, "configured state must have non-zero timelock");
            assertGe(
                state.timelockDurationSeconds, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS, "timelock must be >= min"
            );
            assertLe(
                state.timelockDurationSeconds, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS, "timelock must be <= max"
            );
        }
    }
}
