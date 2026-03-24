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
 * @dev Unit tests for `LibOrganizationGuardianRecovery.initiateInitializeGuardianRecovery`.
 */
contract LibOrganizationGuardianRecoveryInitiateInitializeGuardianRecoveryTest is
    LibOrganizationGuardianRecoverySuiteBase
{
    /// @dev Verifies `LibOrganizationGuardianRecovery.initiateInitializeGuardianRecovery` valid initiate-init writes
    /// pending tuple, computes timestamp, and emits event.
    function test_validInitiateInit_writesPendingTupleAndEmits() public {
        // Setup: start from clean recovery state.
        harness.resetGuardianRecoveryStorageViaHarness();
        uint256 expectedCanFinalizeAt = block.timestamp + ADMIN_OPERATION_TIMELOCK;

        // Call: initiate deferred recovery initialization.
        vm.expectEmit(true, true, true, true);
        emit IOrganizationGuardianRecovery.GuardianRecoveryInitializationInitiated(
            GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, expectedCanFinalizeAt
        );
        harness.initiateInitializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);

        // Verify: pending init timestamp is computed.
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

    /// @dev Verifies `LibOrganizationGuardianRecovery.finalizeInitializeGuardianRecovery` reverts in the same block
    /// the deferred initialization was initiated.
    function test_finalizeInitializeGuardianRecovery_sameBlockRevertsTimelockNotExpired() public {
        // Setup: start from clean recovery state and stage a deferred initialization in the current block.
        harness.resetGuardianRecoveryStorageViaHarness();
        harness.initiateInitializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);
        uint256 canFinalizeAt = harness.getGuardianRecoveryStateViaStorage().pendingInit.pendingTimestamp;

        // Call: finalize immediately in the same block, expecting the shared timelock-not-expired revert.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdminOperationTimelock.TimelockNotExpired.selector, canFinalizeAt, block.timestamp
            )
        );
        harness.finalizeInitializeGuardianRecoveryViaLibrary();

        // Verify: same-block finalization leaves the deferred-init tuple untouched.
        GuardianRecoveryState memory state = harness.getGuardianRecoveryStateViaStorage();
        assertEq(
            state.pendingInit.pendingRecoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS,
            "same-block finalize should preserve the pending recovery address"
        );
        assertEq(
            state.pendingInit.pendingTimelockDurationSeconds,
            GUARDIAN_RECOVERY_TIMELOCK,
            "same-block finalize should preserve the pending timelock"
        );
        assertEq(
            state.pendingInit.pendingTimestamp,
            canFinalizeAt,
            "same-block finalize should preserve the pending timestamp"
        );
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.initiateInitializeGuardianRecovery` validation order checks
    /// configured state before already-pending state.
    function test_notConfiguredValidationRunsBeforeAlreadyPendingCheck() public {
        // Setup: start from clean recovery state and seed pending deferred-init tuple.
        harness.resetGuardianRecoveryStorageViaHarness();
        recoveryStateHarness.setGuardianRecoveryConfig(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);
        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS_B, 4 days, block.timestamp + 9 days
        );

        // Call: initiate deferred recovery initialization, expecting `GuardianRecoveryAlreadyConfigured` revert.
        vm.expectRevert(IOrganizationGuardianRecovery.GuardianRecoveryAlreadyConfigured.selector);
        harness.initiateInitializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS_B, 3 days);

        // Verify: pending tuple remains untouched when configured check fails first.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().pendingInit.pendingRecoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS_B,
            "pending tuple should remain untouched when configured check fails first"
        );
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.initiateInitializeGuardianRecovery` already-pending check runs
    /// before parameter validation.
    function test_alreadyPendingCheckRunsBeforeParameterValidation() public {
        // Setup: start from clean recovery state and seed pending deferred-init tuple.
        harness.resetGuardianRecoveryStorageViaHarness();
        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, block.timestamp + 4 days
        );

        // Call: initiate deferred recovery initialization, expecting `GuardianRecoveryInitializationAlreadyPending`
        // revert.
        vm.expectRevert(IOrganizationGuardianRecovery.GuardianRecoveryInitializationAlreadyPending.selector);
        harness.initiateInitializeGuardianRecoveryViaLibrary(address(0), 1 days);

        // Verify: existing pending tuple remains unchanged.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().pendingInit.pendingRecoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS,
            "existing pending tuple should remain unchanged"
        );
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.initiateInitializeGuardianRecovery` zero address and out-of-range
    /// timelock values revert.
    function test_invalidParams_revert() public {
        // Setup: start from clean recovery state.
        harness.resetGuardianRecoveryStorageViaHarness();

        // Call: initiate deferred recovery initialization, expecting `InvalidGuardianRecoveryAddress` revert.
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

        // Verify: invalid params should not create pending init state.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().pendingInit.pendingTimestamp,
            0,
            "invalid params should not create pending init state"
        );
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.initiateInitializeGuardianRecovery` initiate-init mutates only
    /// pendingInit fields.
    function test_initiateInitOnlyMutatesPendingInitFields() public {
        // Setup: start from clean recovery state and seed pending recovery-guardian update.
        harness.resetGuardianRecoveryStorageViaHarness();
        recoveryStateHarness.setGuardianRecoveryPendingUpdate(NEW_GUARDIAN_A, block.timestamp + 5 days, true);

        // Call: initiate deferred recovery initialization.
        harness.initiateInitializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);

        // Verify: config recovery address remains zero; config timelock remains zero.
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
    function test_boundaryTimelocks_minAndMax_areAccepted() public {
        // Setup: start from clean recovery state.
        harness.resetGuardianRecoveryStorageViaHarness();

        // Call: initiate deferred recovery initialization then cancel deferred recovery initialization.
        harness.initiateInitializeGuardianRecoveryViaLibrary(
            GUARDIAN_RECOVERY_ADDRESS, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS
        );
        harness.cancelInitializeGuardianRecoveryViaLibrary();
        harness.initiateInitializeGuardianRecoveryViaLibrary(
            GUARDIAN_RECOVERY_ADDRESS, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        );

        // Verify: max-boundary timelock is accepted.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().pendingInit.pendingTimelockDurationSeconds,
            TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS,
            "max-boundary timelock should be accepted"
        );
    }
}
