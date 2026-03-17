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
    function test_finalizeSetsReadyAndPreservesOtherFields() public {
        // Setup: reconfigure baseline recovery address and timelock, seed pending deferred-init tuple, and seed pending
        // recovery-guardian update.
        _resetAndConfigureRecovery();
        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS_B, 5 days, block.timestamp + 9 days
        );
        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        GuardianRecoveryState memory beforeState = harness.getGuardianRecoveryStateViaStorage();
        vm.warp(beforeState.pendingGuardianTimestamp);

        // Call: finalize recovery guardian update.
        vm.expectEmit(true, true, true, true);
        emit IOrganizationGuardianRecovery.RecoveryGuardianUpdateFinalized(NEW_GUARDIAN_A);
        harness.finalizeRecoveryGuardianUpdateViaLibrary();

        // Verify: ready flag is true after finalize; pending guardian remains unchanged.
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
    function test_beforeExpiryReverts_exactlyAtExpirySucceeds() public {
        // Setup: reconfigure baseline recovery address and timelock and seed pending recovery-guardian update.
        _resetAndConfigureRecovery();
        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        uint256 canFinalizeAt = harness.getGuardianRecoveryStateViaStorage().pendingGuardianTimestamp;

        // Call: finalize recovery guardian update, expecting authorization/state-validation revert.
        vm.warp(canFinalizeAt - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdminOperationTimelock.TimelockNotExpired.selector, canFinalizeAt, canFinalizeAt - 1
            )
        );
        harness.finalizeRecoveryGuardianUpdateViaLibrary();

        vm.warp(canFinalizeAt);
        harness.finalizeRecoveryGuardianUpdateViaLibrary();

        // Verify: finalize at exact boundary should succeed.
        assertTrue(
            harness.getGuardianRecoveryStateViaStorage().isUpdateReadyForAcceptance,
            "finalize at exact boundary should succeed"
        );
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.finalizeRecoveryGuardianUpdate` no pending update reverts with
    /// `NoPendingRecoveryGuardianUpdate`.
    function test_noPendingUpdate_revertsNoPendingRecoveryGuardianUpdate() public {
        // Setup: reconfigure baseline recovery address and timelock.
        _resetAndConfigureRecovery();

        // Call: finalize recovery guardian update, expecting `NoPendingRecoveryGuardianUpdate` revert.
        vm.expectRevert(IOrganizationGuardianRecovery.NoPendingRecoveryGuardianUpdate.selector);
        harness.finalizeRecoveryGuardianUpdateViaLibrary();

        // Verify: ready flag remains false.
        assertFalse(
            harness.getGuardianRecoveryStateViaStorage().isUpdateReadyForAcceptance, "ready flag should remain false"
        );
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.finalizeRecoveryGuardianUpdate` double finalize is an idempotent
    /// no-op after first success.
    function test_doubleFinalize_secondCallIsNoOp() public {
        // Setup: reconfigure baseline recovery address and timelock, seed pending recovery-guardian update, and
        // position timestamp at timelock boundary.
        _resetAndConfigureRecovery();
        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_B);
        vm.warp(harness.getGuardianRecoveryStateViaStorage().pendingGuardianTimestamp);
        harness.finalizeRecoveryGuardianUpdateViaLibrary();

        // Call: finalize recovery guardian update.
        harness.finalizeRecoveryGuardianUpdateViaLibrary();

        // Verify: ready flag remains true after second finalize; pending guardian remains unchanged after second
        // finalize.
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

    /// @dev Verifies `LibOrganizationGuardianRecovery.finalizeRecoveryGuardianUpdate` succeeds when
    /// `block.timestamp` is strictly greater than the pending guardian timestamp.
    function test_finalizeRecoveryGuardianUpdate_afterPendingTimestampSucceeds() public {
        // Setup: configure guardian recovery, stage a recovery guardian update, and advance one second past expiry.
        _resetAndConfigureRecovery();
        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_C);
        vm.warp(harness.getGuardianRecoveryStateViaStorage().pendingGuardianTimestamp + 1);

        // Call: finalize the recovery guardian update after the timelock has already expired.
        harness.finalizeRecoveryGuardianUpdateViaLibrary();

        // Verify: post-expiry finalization succeeds and marks the recovery update ready for acceptance.
        assertTrue(
            harness.getGuardianRecoveryStateViaStorage().isUpdateReadyForAcceptance,
            "post-expiry recovery finalize should succeed"
        );
    }
}
