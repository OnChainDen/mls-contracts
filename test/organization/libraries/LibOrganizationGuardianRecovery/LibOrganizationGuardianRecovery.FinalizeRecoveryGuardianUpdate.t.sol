// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdminOperationTimelock} from "interfaces/organization/IOrganizationAdminOperationTimelock.sol";
import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {
    LibOrganizationGuardianRecoverySuiteBase
} from "test/organization/libraries/LibOrganizationGuardianRecovery/LibOrganizationGuardianRecoverySuiteBase.sol";
import {GuardianRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Unit tests for `LibOrganizationGuardianRecovery.finalizeRecoveryGuardianUpdate`.
 */
contract LibOrganizationGuardianRecoveryFinalizeRecoveryGuardianUpdateTest is LibOrganizationGuardianRecoverySuiteBase {
    /// @dev Verifies `LibOrganizationGuardianRecovery.finalizeRecoveryGuardianUpdate` finalize emits event, sets ready
    /// flag only, and preserves other fields.
    function test_LOGR_FRGU_1__LOGR_FRGU_5__LOGR_FRGU_6__LOGR_FRGU_7__LOGR_FRGU_9_finalizeSetsReadyAndPreservesOtherFields()
        public
    {
        // Setup: configure recovery address/timelock on a clean state; seed a pending deferred-init timelock tuple;
        // seed a pending recovery-guardian update.
        _resetAndConfigureRecovery();
        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS_B, 5 days, block.timestamp + 9 days
        );
        _initiateRecoveryUpdate(NEW_GUARDIAN_A);
        GuardianRecoveryState memory beforeState = harness.getGuardianRecoveryStateViaStorage();
        vm.warp(beforeState.pendingGuardianTimestamp);

        // Call: invoke `LibOrganizationGuardianRecovery.finalizeRecoveryGuardianUpdate`.
        vm.expectEmit(true, true, true, true);
        emit IOrganizationGuardianRecovery.RecoveryGuardianUpdateFinalized(NEW_GUARDIAN_A);
        harness.finalizeRecoveryGuardianUpdateViaLibrary();

        // Verify: confirm the pending deferred-init state remains unchanged.
        GuardianRecoveryState memory afterState = harness.getGuardianRecoveryStateViaStorage();
        assertTrue(afterState.isUpdateReadyForAcceptance, "ready flag should be true after finalize");
        assertEq(afterState.pendingGuardian, beforeState.pendingGuardian, "pending guardian should remain unchanged");
        assertEq(
            afterState.pendingGuardianTimestamp,
            beforeState.pendingGuardianTimestamp,
            "pending timestamp should remain unchanged"
        );
        assertEq(
            afterState.recoveryAddress, beforeState.recoveryAddress, "config recovery address should remain unchanged"
        );
        assertEq(
            afterState.timelockDurationSeconds,
            beforeState.timelockDurationSeconds,
            "config timelock should remain unchanged"
        );
        assertEq(
            afterState.pendingInit.pendingRecoveryAddress,
            beforeState.pendingInit.pendingRecoveryAddress,
            "pending-init address should remain unchanged"
        );
        assertEq(
            afterState.pendingInit.pendingTimelockDurationSeconds,
            beforeState.pendingInit.pendingTimelockDurationSeconds,
            "pending-init timelock should remain unchanged"
        );
        assertEq(
            afterState.pendingInit.pendingTimestamp,
            beforeState.pendingInit.pendingTimestamp,
            "pending-init timestamp should remain unchanged"
        );
        assertEq(harness.getGuardianViaLibrary(), GUARDIAN, "guardian should not change during finalize");
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.finalizeRecoveryGuardianUpdate` finalize reverts before expiry
    /// and succeeds exactly at expiry.
    function test_LOGR_FRGU_2__LOGR_FRGU_3_beforeExpiryReverts_exactlyAtExpirySucceeds() public {
        // Setup: configure recovery address/timelock on a clean state; seed a pending recovery-guardian update.
        _resetAndConfigureRecovery();
        _initiateRecoveryUpdate(NEW_GUARDIAN_A);
        uint256 canFinalizeAt = harness.getGuardianRecoveryStateViaStorage().pendingGuardianTimestamp;

        // Call: invoke `LibOrganizationGuardianRecovery.finalizeRecoveryGuardianUpdate` and assert the expected revert.
        vm.warp(canFinalizeAt - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdminOperationTimelock.TimelockNotExpired.selector, canFinalizeAt, canFinalizeAt - 1
            )
        );
        harness.finalizeRecoveryGuardianUpdateViaLibrary();

        vm.warp(canFinalizeAt);
        harness.finalizeRecoveryGuardianUpdateViaLibrary();

        // Verify: confirm pending recovery-update fields.
        assertTrue(
            harness.getGuardianRecoveryStateViaStorage().isUpdateReadyForAcceptance,
            "finalize at exact boundary should succeed"
        );
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.finalizeRecoveryGuardianUpdate` no pending update reverts with
    /// `NoPendingRecoveryGuardianUpdate`.
    function test_LOGR_FRGU_4_noPendingUpdate_revertsNoPendingRecoveryGuardianUpdate() public {
        // Setup: configure recovery address/timelock on a clean state.
        _resetAndConfigureRecovery();

        // Call: invoke `LibOrganizationGuardianRecovery.finalizeRecoveryGuardianUpdate` and assert the expected revert.
        vm.expectRevert(IOrganizationGuardianRecovery.NoPendingRecoveryGuardianUpdate.selector);
        harness.finalizeRecoveryGuardianUpdateViaLibrary();

        // Verify: confirm pending recovery-update fields.
        assertFalse(
            harness.getGuardianRecoveryStateViaStorage().isUpdateReadyForAcceptance, "ready flag should remain false"
        );
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.finalizeRecoveryGuardianUpdate` double finalize is an idempotent
    /// no-op after first success.
    function test_LOGR_FRGU_8_doubleFinalize_secondCallIsNoOp() public {
        // Setup: configure recovery address/timelock on a clean state; seed a pending recovery-guardian update.
        _resetAndConfigureRecovery();
        _initiateRecoveryUpdate(NEW_GUARDIAN_B);
        _finalizeRecoveryUpdateAfterTimelock();

        // Call: invoke `LibOrganizationGuardianRecovery.finalizeRecoveryGuardianUpdate`.
        harness.finalizeRecoveryGuardianUpdateViaLibrary();

        // Verify: confirm pending recovery-update state remains unchanged.
        assertTrue(
            harness.getGuardianRecoveryStateViaStorage().isUpdateReadyForAcceptance,
            "ready flag should remain true after second finalize"
        );
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().pendingGuardian,
            NEW_GUARDIAN_B,
            "pending guardian should remain unchanged after second finalize"
        );
    }
}
