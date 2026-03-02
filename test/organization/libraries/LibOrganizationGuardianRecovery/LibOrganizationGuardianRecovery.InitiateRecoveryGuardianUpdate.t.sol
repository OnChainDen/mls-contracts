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
 * @dev Unit tests for `LibOrganizationGuardianRecovery.initiateRecoveryGuardianUpdate`.
 */
contract LibOrganizationGuardianRecoveryInitiateRecoveryGuardianUpdateTest is LibOrganizationGuardianRecoverySuiteBase {
    /// @dev Verifies `LibOrganizationGuardianRecovery.initiateRecoveryGuardianUpdate` valid initiate writes pending
    /// guardian, timestamp, and ready=false.
    function test_LOGR_IRGU_1__LOGR_IRGU_2__LOGR_IRGU_3_validInitiate_writesPendingFields() public {
        // Setup: configure recovery address/timelock on a clean state.
        _resetAndConfigureRecovery();
        uint256 expectedCanFinalizeAt = block.timestamp + GUARDIAN_RECOVERY_TIMELOCK;

        // Call: invoke `LibOrganizationGuardianRecovery.initiateRecoveryGuardianUpdate`.
        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_A);

        // Verify: confirm pending recovery-update fields.
        GuardianRecoveryState memory state = harness.getGuardianRecoveryStateViaStorage();
        assertEq(state.pendingGuardian, NEW_GUARDIAN_A, "pending guardian should be set");
        assertEq(state.pendingGuardianTimestamp, expectedCanFinalizeAt, "pending timestamp should match expected");
        assertFalse(state.isUpdateReadyForAcceptance, "ready flag should be false after initiate");
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.initiateRecoveryGuardianUpdate` zero guardian and already-pending
    /// flows revert.
    function test_LOGR_IRGU_4__LOGR_IRGU_5_zeroGuardianOrAlreadyPending_revert() public {
        // Setup: configure recovery address/timelock on a clean state.
        _resetAndConfigureRecovery();

        // Call: invoke `LibOrganizationGuardianRecovery.initiateRecoveryGuardianUpdate` and assert the expected revert.
        vm.expectRevert(IOrganizationGuardianRecovery.InvalidNewGuardianAddress.selector);
        harness.initiateRecoveryGuardianUpdateViaLibrary(address(0));

        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        vm.expectRevert(IOrganizationGuardianRecovery.RecoveryGuardianUpdateAlreadyPending.selector);
        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_B);

        // Verify: confirm pending recovery-update fields.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().pendingGuardian,
            NEW_GUARDIAN_A,
            "first valid pending guardian should remain"
        );
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.initiateRecoveryGuardianUpdate` event emits guardian from normal
    /// storage and initiate does not change current guardian.
    function test_LOGR_IRGU_6__LOGR_IRGU_7__LOGR_IRGU_8_eventUsesNormalGuardianStorageAndGuardianRemainsUnchanged()
        public
    {
        // Setup: configure recovery address/timelock on a clean state.
        _resetAndConfigureRecovery();
        recoveryStateHarness.setGuardian(NEW_GUARDIAN_C);
        uint256 expectedCanFinalizeAt = block.timestamp + GUARDIAN_RECOVERY_TIMELOCK;

        // Call: invoke `LibOrganizationGuardianRecovery.initiateRecoveryGuardianUpdate`.
        vm.expectEmit(true, true, true, true);
        emit IOrganizationGuardianRecovery.RecoveryGuardianUpdateInitiated(
            NEW_GUARDIAN_C, NEW_GUARDIAN_A, expectedCanFinalizeAt
        );
        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_A);

        // Verify: confirm guardian value in normal guardian storage.
        assertEq(harness.getGuardianViaLibrary(), NEW_GUARDIAN_C, "current guardian should remain unchanged");
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.initiateRecoveryGuardianUpdate` initiating to same address as
    /// current guardian is allowed.
    function test_LOGR_IRGU_9_sameAsCurrentGuardian_succeeds() public {
        // Setup: configure recovery address/timelock on a clean state.
        _resetAndConfigureRecovery();
        recoveryStateHarness.setGuardian(NEW_GUARDIAN_A);

        // Call: invoke `LibOrganizationGuardianRecovery.initiateRecoveryGuardianUpdate`.
        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_A);

        // Verify: confirm pending recovery-update fields.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().pendingGuardian,
            NEW_GUARDIAN_A,
            "pending guardian can equal current guardian"
        );
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.initiateRecoveryGuardianUpdate` initiate mutates only
    /// recovery-update pending fields.
    function test_LOGR_IRGU_10_initiateOnlyMutatesRecoveryUpdatePendingFields() public {
        // Setup: configure recovery address/timelock on a clean state; seed a pending deferred-init timelock tuple.
        _resetAndConfigureRecovery();
        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS_B, 5 days, block.timestamp + 8 days
        );

        // Call: invoke `LibOrganizationGuardianRecovery.initiateRecoveryGuardianUpdate`.
        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_B);

        // Verify: confirm the pending deferred-init state remains unchanged.
        GuardianRecoveryState memory state = harness.getGuardianRecoveryStateViaStorage();
        assertEq(state.recoveryAddress, GUARDIAN_RECOVERY_ADDRESS, "config recovery address should remain unchanged");
        assertEq(state.timelockDurationSeconds, GUARDIAN_RECOVERY_TIMELOCK, "config timelock should remain unchanged");
        assertEq(
            state.pendingInit.pendingRecoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS_B,
            "pending-init address should remain unchanged"
        );
        assertEq(
            state.pendingInit.pendingTimelockDurationSeconds, 5 days, "pending-init timelock should remain unchanged"
        );
        assertEq(
            state.pendingInit.pendingTimestamp,
            block.timestamp + 8 days,
            "pending-init timestamp should remain unchanged"
        );
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.initiateRecoveryGuardianUpdate` invalid configured recovery
    /// timelock reverts and does not create pending update.
    function test_LOGR_IRGU_11_invalidConfiguredTimelock_revertsAndDoesNotCreatePendingUpdate() public {
        // Setup: reset library recovery state.
        harness.resetGuardianRecoveryStorageViaHarness();
        recoveryStateHarness.setGuardianRecoveryConfig(GUARDIAN_RECOVERY_ADDRESS, 1 days);

        // Call: invoke `LibOrganizationGuardianRecovery.initiateRecoveryGuardianUpdate` and assert the expected revert.
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                1 days,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_A);

        // Verify: confirm pending recovery-update fields.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().pendingGuardian,
            address(0),
            "pending guardian should remain unset"
        );
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().pendingGuardianTimestamp,
            0,
            "pending timestamp should remain unset"
        );
    }
}
