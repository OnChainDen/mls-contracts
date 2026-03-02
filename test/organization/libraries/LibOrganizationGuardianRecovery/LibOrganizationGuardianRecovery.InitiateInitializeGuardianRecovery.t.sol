// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {TimelockUtils} from "libraries/TimelockUtils.sol";
import {
    LibOrganizationGuardianRecoverySuiteBase
} from "test/organization/libraries/LibOrganizationGuardianRecovery/LibOrganizationGuardianRecoverySuiteBase.sol";
import {GuardianRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Unit tests for `LibOrganizationGuardianRecovery.initiateInitializeGuardianRecovery`.
 */
contract LibOrganizationGuardianRecoveryInitiateInitializeGuardianRecoveryTest is
    LibOrganizationGuardianRecoverySuiteBase
{
    /// @dev Verifies `LibOrganizationGuardianRecovery.initiateInitializeGuardianRecovery` valid initiate-init writes
    /// pending tuple, computes timestamp, and emits event.
    function test_LOGR_IIGR_1__LOGR_IIGR_2__LOGR_IIGR_3__LOGR_IIGR_9_validInitiateInit_writesPendingTupleAndEmits()
        public
    {
        // Setup: reset library recovery state.
        harness.resetGuardianRecoveryStorageViaHarness();
        uint256 expectedCanFinalizeAt = block.timestamp + ADMIN_OPERATION_TIMELOCK;

        // Call: invoke `LibOrganizationGuardianRecovery.initiateInitializeGuardianRecovery`.
        vm.expectEmit(true, true, true, true);
        emit IOrganizationGuardianRecovery.GuardianRecoveryInitializationInitiated(
            GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, expectedCanFinalizeAt
        );
        harness.initiateInitializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);

        // Verify: confirm pending deferred-init fields.
        GuardianRecoveryState memory state = harness.getGuardianRecoveryStateViaStorage();
        assertEq(
            state.pendingInit.pendingRecoveryAddress, GUARDIAN_RECOVERY_ADDRESS, "pending init address should be set"
        );
        assertEq(
            state.pendingInit.pendingTimelockDurationSeconds,
            GUARDIAN_RECOVERY_TIMELOCK,
            "pending init timelock should be set"
        );
        assertEq(state.pendingInit.pendingTimestamp, expectedCanFinalizeAt, "pending init timestamp should be computed");
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.initiateInitializeGuardianRecovery` validation order checks
    /// configured state before already-pending state.
    function test_LOGR_IIGR_4__LOGR_IIGR_10_notConfiguredValidationRunsBeforeAlreadyPendingCheck() public {
        // Setup: reset library recovery state; seed a pending deferred-init timelock tuple.
        harness.resetGuardianRecoveryStorageViaHarness();
        recoveryStateHarness.setGuardianRecoveryConfig(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);
        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS_B, 4 days, block.timestamp + 9 days
        );

        // Call: invoke `LibOrganizationGuardianRecovery.initiateInitializeGuardianRecovery` and assert the expected
        // revert.
        vm.expectRevert(IOrganizationGuardianRecovery.GuardianRecoveryAlreadyConfigured.selector);
        harness.initiateInitializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS_B, 3 days);

        // Verify: confirm pending deferred-init fields.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().pendingInit.pendingRecoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS_B,
            "pending tuple should remain untouched when configured check fails first"
        );
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.initiateInitializeGuardianRecovery` already-pending check runs
    /// before parameter validation.
    function test_LOGR_IIGR_5__LOGR_IIGR_11_alreadyPendingCheckRunsBeforeParameterValidation() public {
        // Setup: reset library recovery state; seed a pending deferred-init timelock tuple.
        harness.resetGuardianRecoveryStorageViaHarness();
        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, block.timestamp + 4 days
        );

        // Call: invoke `LibOrganizationGuardianRecovery.initiateInitializeGuardianRecovery` and assert the expected
        // revert.
        vm.expectRevert(IOrganizationGuardianRecovery.GuardianRecoveryInitializationAlreadyPending.selector);
        harness.initiateInitializeGuardianRecoveryViaLibrary(address(0), 1 days);

        // Verify: confirm the pending deferred-init state remains unchanged.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().pendingInit.pendingRecoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS,
            "existing pending tuple should remain unchanged"
        );
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.initiateInitializeGuardianRecovery` zero address and out-of-range
    /// timelock values revert.
    function test_LOGR_IIGR_6__LOGR_IIGR_7__LOGR_IIGR_8_invalidParams_revert() public {
        // Setup: reset library recovery state.
        harness.resetGuardianRecoveryStorageViaHarness();

        // Call: invoke `LibOrganizationGuardianRecovery.initiateInitializeGuardianRecovery` and assert the expected
        // revert.
        vm.expectRevert(IOrganizationGuardianRecovery.InvalidGuardianRecoveryAddress.selector);
        harness.initiateInitializeGuardianRecoveryViaLibrary(address(0), GUARDIAN_RECOVERY_TIMELOCK);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                1 days,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        harness.initiateInitializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, 1 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                31 days,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        harness.initiateInitializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, 31 days);

        // Verify: confirm pending deferred-init fields.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().pendingInit.pendingTimestamp,
            0,
            "invalid params should not create pending init state"
        );
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.initiateInitializeGuardianRecovery` initiate-init mutates only
    /// pendingInit fields.
    function test_LOGR_IIGR_12_initiateInitOnlyMutatesPendingInitFields() public {
        // Setup: reset library recovery state; seed a pending recovery-guardian update.
        harness.resetGuardianRecoveryStorageViaHarness();
        recoveryStateHarness.setGuardianRecoveryPendingUpdate(NEW_GUARDIAN_A, block.timestamp + 5 days, true);

        // Call: invoke `LibOrganizationGuardianRecovery.initiateInitializeGuardianRecovery`.
        harness.initiateInitializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);

        // Verify: confirm pending recovery-update state remains unchanged.
        GuardianRecoveryState memory state = harness.getGuardianRecoveryStateViaStorage();
        assertEq(state.recoveryAddress, address(0), "config recovery address should remain zero");
        assertEq(state.timelockDurationSeconds, 0, "config timelock should remain zero");
        assertEq(state.pendingGuardian, NEW_GUARDIAN_A, "recovery-update pending guardian should remain unchanged");
        assertEq(
            state.pendingGuardianTimestamp, block.timestamp + 5 days, "recovery-update pending timestamp unchanged"
        );
        assertTrue(state.isUpdateReadyForAcceptance, "recovery-update ready flag should remain unchanged");
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.initiateInitializeGuardianRecovery` boundary timelocks (2 days,
    /// 30 days) are accepted.
    function test_LOGR_IIGR_13_boundaryTimelocks_minAndMax_areAccepted() public {
        // Setup: reset library recovery state.
        harness.resetGuardianRecoveryStorageViaHarness();

        // Call: run the multi-step flow (`LibOrganizationGuardianRecovery.initiateInitializeGuardianRecovery`,
        // `LibOrganizationGuardianRecovery.cancelInitializeGuardianRecovery`).
        harness.initiateInitializeGuardianRecoveryViaLibrary(
            GUARDIAN_RECOVERY_ADDRESS, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS
        );
        harness.cancelInitializeGuardianRecoveryViaLibrary();
        harness.initiateInitializeGuardianRecoveryViaLibrary(
            GUARDIAN_RECOVERY_ADDRESS, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        );

        // Verify: confirm pending deferred-init fields.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().pendingInit.pendingTimelockDurationSeconds,
            TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS,
            "max-boundary timelock should be accepted"
        );
    }
}
