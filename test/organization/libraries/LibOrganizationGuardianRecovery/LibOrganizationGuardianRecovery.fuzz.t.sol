// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdminOperationTimelock} from "interfaces/organization/IOrganizationAdminOperationTimelock.sol";
import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {TimelockUtils} from "libraries/TimelockUtils.sol";
import {
    LibOrganizationGuardianRecoverySuiteBase
} from "test/organization/libraries/LibOrganizationGuardianRecovery/LibOrganizationGuardianRecoverySuiteBase.sol";
import {GuardianRecoveryState, PendingRecoveryInitTimelock, TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Fuzz tests for guardian-recovery flows.
 */
contract LibOrganizationGuardianRecoveryFuzzTest is LibOrganizationGuardianRecoverySuiteBase {
    /// @dev Verifies that random non-zero recovery addresses with valid timelocks configure successfully.
    function testFuzz_randomNonZeroRecoveryAddress_validTimelock_configures(address recoveryAddress, uint256 timelock)
        public
    {
        // Setup: start from clean recovery state.
        vm.assume(recoveryAddress != address(0));
        uint256 boundedTimelock =
            bound(timelock, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS);
        harness.resetGuardianRecoveryStorageViaHarness();

        // Call: initialize guardian-recovery config.
        harness.initializeGuardianRecoveryViaLibrary(recoveryAddress, boundedTimelock);

        // Verify: recovery address should match fuzz input; timelock should match bounded fuzz input.
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

    /// @dev Verifies `LibOrganizationGuardianRecovery.initializeGuardianRecovery` can configure recovery exactly once.
    /// @param recoveryAddress The first configured recovery address.
    /// @param timelock The first configured guardian-recovery timelock.
    /// @param secondRecoveryAddress The second attempted recovery address.
    /// @param secondTimelock The second attempted guardian-recovery timelock.
    function testFuzz_initializeGuardianRecovery_canOnlyBeConfiguredOnce(
        address recoveryAddress,
        uint256 timelock,
        address secondRecoveryAddress,
        uint256 secondTimelock
    ) public {
        vm.assume(recoveryAddress != address(0));
        vm.assume(secondRecoveryAddress != address(0));

        uint256 boundedTimelock =
            bound(timelock, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS);
        uint256 boundedSecondTimelock = bound(
            secondTimelock, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        );

        // Setup: start from zero recovery state and configure the first guardian-recovery tuple.
        harness.resetGuardianRecoveryStorageViaHarness();
        harness.initializeGuardianRecoveryViaLibrary(recoveryAddress, boundedTimelock);

        // Call: attempt to initialize again with a new tuple, expecting the one-time configuration revert.
        vm.expectRevert(IOrganizationGuardianRecovery.GuardianRecoveryAlreadyConfigured.selector);
        harness.initializeGuardianRecoveryViaLibrary(secondRecoveryAddress, boundedSecondTimelock);

        // Verify: the originally configured tuple remains unchanged after the rejected second initialization.
        GuardianRecoveryState memory state = harness.getGuardianRecoveryStateViaStorage();
        assertEq(state.recoveryAddress, recoveryAddress, "configured recovery address should remain unchanged");
        assertEq(state.timelockDurationSeconds, boundedTimelock, "configured timelock should remain unchanged");
    }

    /// @dev Verifies that validation helper accepts in-range timelocks and rejects out-of-range values.
    function testFuzz_validateParams_acceptsInRangeRejectsOutOfRange(address recoveryAddress, uint256 timelock) public {
        // Setup: reuse suite baseline where recovery is preconfigured.
        vm.assume(recoveryAddress != address(0));

        // Call: validate recovery params, expecting authorization/state-validation revert.
        if (
            timelock >= TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS
                && timelock <= TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        ) {
            harness.validateGuardianRecoveryParamsOrRevertViaLibrary(recoveryAddress, timelock);
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(
                    TimelockUtils.InvalidTimelockDuration.selector,
                    timelock,
                    TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                    TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
                )
            );
            harness.validateGuardianRecoveryParamsOrRevertViaLibrary(recoveryAddress, timelock);
        }

        // Verify: validation branch executed.
        assertTrue(true, "validation branch executed");
    }

    /// @dev Verifies recovery-guardian updates use the configured guardian-recovery timelock and enforce the
    /// finalize timestamp relation.
    function testFuzz_finalizeBeforeAfterTimelock_behavesByTimestamp(uint256 timelock, uint256 delta) public {
        // Setup: start from clean recovery state.
        uint256 boundedTimelock =
            bound(timelock, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS);
        harness.resetGuardianRecoveryStorageViaHarness();
        harness.initializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, boundedTimelock);

        // Call: initiate recovery guardian update then finalize recovery guardian update, expecting
        // authorization/state-validation revert.
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

        // Verify: finalize branch behavior matched timestamp relation.
        assertTrue(true, "finalize branch behavior matched timestamp relation");
    }

    /// @dev Verifies deferred guardian-recovery initialization uses the admin-operation timelock for initiate,
    /// finalize, and cancel paths.
    /// @param pendingRecoveryAddress The recovery address proposed through deferred initialization.
    /// @param pendingTimelock The recovery timelock proposed through deferred initialization.
    /// @param cancelAfterInitiate Whether to cancel immediately instead of finalizing after the timelock.
    function testFuzz_deferredGuardianRecoveryInit_obeysAdminOperationTimelock(
        address pendingRecoveryAddress,
        uint256 pendingTimelock,
        bool cancelAfterInitiate
    ) public {
        vm.assume(pendingRecoveryAddress != address(0));
        uint256 boundedPendingTimelock = bound(
            pendingTimelock, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        );
        vm.assume(boundedPendingTimelock != ADMIN_OPERATION_TIMELOCK);

        // Setup: clear active guardian-recovery config so deferred initialization is available.
        harness.resetGuardianRecoveryStorageViaHarness();

        // Call: initiate deferred initialization, then either cancel immediately or finalize after the admin timelock.
        harness.initiateInitializeGuardianRecoveryViaLibrary(pendingRecoveryAddress, boundedPendingTimelock);
        GuardianRecoveryState memory pendingState = harness.getGuardianRecoveryStateViaStorage();

        assertEq(
            pendingState.pendingInit.pendingTimestamp,
            block.timestamp + ADMIN_OPERATION_TIMELOCK,
            "pending-init timestamp should use the admin-operation timelock"
        );

        if (cancelAfterInitiate) {
            harness.cancelInitializeGuardianRecoveryViaLibrary();

            // Verify: cancel clears the pending tuple and leaves active recovery config unset.
            GuardianRecoveryState memory cancelledState = harness.getGuardianRecoveryStateViaStorage();
            assertEq(cancelledState.recoveryAddress, address(0), "cancel should not configure recovery");
            assertEq(
                cancelledState.pendingInit.pendingRecoveryAddress, address(0), "cancel should clear pending address"
            );
            assertEq(cancelledState.pendingInit.pendingTimestamp, 0, "cancel should clear pending timestamp");
            return;
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdminOperationTimelock.TimelockNotExpired.selector,
                pendingState.pendingInit.pendingTimestamp,
                block.timestamp
            )
        );
        harness.finalizeInitializeGuardianRecoveryViaLibrary();

        vm.warp(pendingState.pendingInit.pendingTimestamp);
        harness.finalizeInitializeGuardianRecoveryViaLibrary();

        // Verify: finalize succeeds only after the admin timelock and promotes the pending tuple into active config.
        GuardianRecoveryState memory finalizedState = harness.getGuardianRecoveryStateViaStorage();
        assertEq(finalizedState.recoveryAddress, pendingRecoveryAddress, "finalize should configure recovery address");
        assertEq(
            finalizedState.timelockDurationSeconds,
            boundedPendingTimelock,
            "finalize should configure recovery timelock"
        );
        assertEq(finalizedState.pendingInit.pendingRecoveryAddress, address(0), "finalize should clear pending address");
        assertEq(finalizedState.pendingInit.pendingTimestamp, 0, "finalize should clear pending timestamp");
    }

    /// @dev Verifies that random non-zero guardians complete flow while zero guardian always reverts on initiate.
    function testFuzz_randomGuardiansOrZero_initiateBehavior(address newGuardian) public {
        // Setup: reconfigure baseline recovery address and timelock.
        _resetAndConfigureRecovery();

        // Call: initiate recovery guardian update, finalize recovery guardian update, then accept recovery guardian
        // update, expecting `InvalidNewGuardianAddress` revert.
        if (newGuardian == address(0)) {
            vm.expectRevert(IOrganizationGuardianRecovery.InvalidNewGuardianAddress.selector);
            harness.initiateRecoveryGuardianUpdateViaLibrary(address(0));
        } else {
            harness.initiateRecoveryGuardianUpdateViaLibrary(newGuardian);
            vm.warp(harness.getGuardianRecoveryStateViaStorage().pendingGuardianTimestamp);
            harness.finalizeRecoveryGuardianUpdateViaLibrary();
            harness.acceptGuardianRecoveryViaLibrary();
        }

        // Verify: guardian should become fuzzed non-zero guardian.
        if (newGuardian != address(0)) {
            assertEq(harness.getGuardianViaLibrary(), newGuardian, "guardian should become fuzzed non-zero guardian");
        }
    }

    /// @dev Verifies that random non-recovery addresses revert enforceOnlyGuardianRecoveryAddress.
    function testFuzz_randomNonRecoveryAddresses_revertOnEnforceOnlyGuardianRecoveryAddress(address caller) public {
        // Setup: reconfigure baseline recovery address and timelock.
        vm.assume(caller != GUARDIAN_RECOVERY_ADDRESS);
        _resetAndConfigureRecovery();

        // Call: enforce recovery-address caller gate as `caller`, expecting authorization/state-validation revert.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.UnauthorizedGuardianRecoveryAddress.selector,
                caller,
                GUARDIAN_RECOVERY_ADDRESS
            )
        );
        vm.prank(caller);
        harness.enforceOnlyGuardianRecoveryAddressViaLibrary();

        // Verify: config remains unchanged.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().recoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS,
            "config should remain unchanged"
        );
    }

    /// @dev Verifies that random non-pending-guardian addresses revert enforceOnlyRecoveryPendingGuardian.
    function testFuzz_randomNonPendingGuardianAddresses_revertOnEnforceOnlyRecoveryPendingGuardian(
        address pendingGuardian,
        address caller
    ) public {
        // Setup: reconfigure baseline recovery address and timelock and seed pending recovery-guardian update.
        vm.assume(pendingGuardian != address(0));
        vm.assume(caller != pendingGuardian);
        _resetAndConfigureRecovery();
        recoveryStateHarness.setGuardianRecoveryPendingUpdate(pendingGuardian, block.timestamp + 1 days, false);

        // Call: enforce pending-guardian caller gate as `caller`, expecting authorization/state-validation revert.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.UnauthorizedRecoveryGuardianAcceptance.selector, caller, pendingGuardian
            )
        );
        vm.prank(caller);
        harness.enforceOnlyRecoveryPendingGuardianViaLibrary();

        // Verify: pending guardian remains unchanged.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().pendingGuardian,
            pendingGuardian,
            "pending guardian should remain unchanged"
        );
    }

    /// @dev Verifies that random state transitions never change guardian except via successful accept.
    function testFuzz_statefulSequence_guardianChangesOnlyOnSuccessfulAccept(uint256 seed, uint8 steps) public {
        // Setup: reconfigure baseline recovery address and timelock.
        _resetAndConfigureRecovery();
        uint256 count = bound(steps, 1, 20);
        address[] memory candidates = new address[](3);
        candidates[0] = address(uint160(uint256(keccak256(abi.encode(seed, "a"))) | 1));
        candidates[1] = address(uint160(uint256(keccak256(abi.encode(seed, "b"))) | 1));
        candidates[2] = address(uint160(uint256(keccak256(abi.encode(seed, "c"))) | 1));

        // Call: execute randomized recovery operations and check guardian immutability between successful accepts.
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
                vm.warp(block.timestamp + (seed % 3 days));
            }
        }

        // Verify: guardian remains non-zero throughout sequence.
        assertTrue(harness.getGuardianViaLibrary() != address(0), "guardian should remain non-zero throughout sequence");
    }

    /// @dev Verifies that configured state always has non-zero in-range timelock when recoveryAddress is non-zero.
    function testFuzz_configCoherence_whenConfiguredTimelockIsNonZeroAndInRange(
        address recoveryAddress,
        uint256 timelock
    ) public {
        // Setup: start from clean recovery state.
        harness.resetGuardianRecoveryStorageViaHarness();

        // Call: initialize guardian-recovery config.
        if (recoveryAddress != address(0)) {
            uint256 bounded = bound(
                timelock, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            );
            harness.initializeGuardianRecoveryViaLibrary(recoveryAddress, bounded);
        }

        // Verify: configured state must have non-zero timelock.
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

    /// @dev Verifies guardian-recovery operations never mutate tx-recovery storage.
    /// @param txRecoveryAddress The tx-recovery address seeded into storage.
    /// @param enabled Whether tx recovery starts enabled.
    /// @param txTimelock The tx-recovery timelock seeded into storage.
    /// @param pendingEnableTimestamp The pending tx-recovery enable timestamp seeded into storage.
    /// @param pendingInitAddress The pending tx-recovery init address seeded into storage.
    /// @param pendingInitTimelock The pending tx-recovery init timelock seeded into storage.
    /// @param pendingInitTimestamp The pending tx-recovery init timestamp seeded into storage.
    /// @param newGuardian The recovery guardian used for the guardian-recovery mutation path.
    function testFuzz_guardianRecoveryOperations_neverMutateTxRecoveryState(
        address txRecoveryAddress,
        bool enabled,
        uint256 txTimelock,
        uint256 pendingEnableTimestamp,
        address pendingInitAddress,
        uint256 pendingInitTimelock,
        uint256 pendingInitTimestamp,
        address newGuardian
    ) public {
        vm.assume(newGuardian != address(0));

        // Setup: seed arbitrary tx-recovery state, then perform guardian-recovery operations on the other state
        // subtree.
        TxRecoveryState memory beforeState = TxRecoveryState({
            recoveryAddress: txRecoveryAddress,
            isEnabled: enabled,
            timelockDurationSeconds: txTimelock,
            pendingEnableTimestamp: pendingEnableTimestamp,
            pendingInit: PendingRecoveryInitTimelock({
                pendingRecoveryAddress: pendingInitAddress,
                pendingTimelockDurationSeconds: pendingInitTimelock,
                pendingTimestamp: pendingInitTimestamp
            })
        });
        recoveryStateHarness.setTxRecoveryState(beforeState);
        _resetAndConfigureRecovery();

        harness.initiateRecoveryGuardianUpdateViaLibrary(newGuardian);
        harness.cancelRecoveryGuardianUpdateViaLibrary();

        // Verify: tx-recovery storage remains unchanged after guardian-recovery mutations.
        TxRecoveryState memory afterState = harness.getTxRecoveryStateViaStorage();
        assertEq(afterState.recoveryAddress, beforeState.recoveryAddress, "tx recovery address should not change");
        assertEq(afterState.isEnabled, beforeState.isEnabled, "tx recovery enabled flag should not change");
        assertEq(
            afterState.timelockDurationSeconds,
            beforeState.timelockDurationSeconds,
            "tx recovery timelock should not change"
        );
        assertEq(
            afterState.pendingEnableTimestamp,
            beforeState.pendingEnableTimestamp,
            "pending enable timestamp should not change"
        );
        assertEq(
            afterState.pendingInit.pendingRecoveryAddress,
            beforeState.pendingInit.pendingRecoveryAddress,
            "pending init address should not change"
        );
        assertEq(
            afterState.pendingInit.pendingTimelockDurationSeconds,
            beforeState.pendingInit.pendingTimelockDurationSeconds,
            "pending init timelock should not change"
        );
        assertEq(
            afterState.pendingInit.pendingTimestamp,
            beforeState.pendingInit.pendingTimestamp,
            "pending init timestamp should not change"
        );
    }

    /// @dev Verifies guardian-recovery helper wrappers stay idempotent and field-consistent.
    /// @param pendingAddress The pending deferred-init recovery address seeded into storage.
    /// @param pendingTimelock The pending deferred-init timelock seeded into storage.
    /// @param pendingTimestamp The pending deferred-init finalize timestamp seeded into storage.
    /// @param configuredRecovery The active recovery address used for the validate-not-configured branch.
    /// @param configuredTimelock The active recovery timelock used for the validate-not-configured branch.
    function testFuzz_helperWrappers_areIdempotentAndFieldConsistent(
        address pendingAddress,
        uint256 pendingTimelock,
        uint256 pendingTimestamp,
        address configuredRecovery,
        uint256 configuredTimelock
    ) public {
        vm.assume(pendingAddress != address(0));
        vm.assume(configuredRecovery != address(0));

        uint256 boundedPendingTimelock = bound(
            pendingTimelock, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        );

        // Setup: seed a pending deferred-init tuple, clear it twice through the helper, then seed active config.
        harness.resetGuardianRecoveryStorageViaHarness();
        recoveryStateHarness.setGuardianRecoveryPendingInit(pendingAddress, boundedPendingTimelock, pendingTimestamp);

        harness.clearPendingGuardianRecoveryInitTimelockViaLibrary();
        harness.clearPendingGuardianRecoveryInitTimelockViaLibrary();

        GuardianRecoveryState memory clearedState = harness.getGuardianRecoveryStateViaStorage();
        assertEq(clearedState.pendingInit.pendingRecoveryAddress, address(0), "clear helper should zero address");
        assertEq(clearedState.pendingInit.pendingTimelockDurationSeconds, 0, "clear helper should zero timelock");
        assertEq(clearedState.pendingInit.pendingTimestamp, 0, "clear helper should zero timestamp");

        recoveryStateHarness.setGuardianRecoveryConfig(configuredRecovery, configuredTimelock);

        // Call: run the not-configured validator after seeding active config.
        vm.expectRevert(IOrganizationGuardianRecovery.GuardianRecoveryAlreadyConfigured.selector);
        harness.validateGuardianRecoveryNotConfiguredOrRevertViaLibrary();

        // Verify: the helper revert leaves the active config intact.
        GuardianRecoveryState memory configuredState = harness.getGuardianRecoveryStateViaStorage();
        assertEq(configuredState.recoveryAddress, configuredRecovery, "configured recovery address should remain");
        assertEq(configuredState.timelockDurationSeconds, configuredTimelock, "configured timelock should remain");
    }
}
