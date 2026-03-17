// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {
    LibOrganizationGuardianRecoverySuiteBase
} from "test/organization/libraries/LibOrganizationGuardianRecovery/LibOrganizationGuardianRecoverySuiteBase.sol";
import {GuardianRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Unit tests for `LibOrganizationGuardianRecovery.cancelRecoveryGuardianUpdate`.
 */
contract LibOrganizationGuardianRecoveryCancelRecoveryGuardianUpdateTest is LibOrganizationGuardianRecoverySuiteBase {
    /// @dev Verifies `LibOrganizationGuardianRecovery.cancelRecoveryGuardianUpdate` cancel clears pending fields, emits
    /// event, and preserves config/pending-init.
    function test_LOGR_CRGU_1__LOGR_CRGU_2__LOGR_CRGU_3__LOGR_CRGU_5__LOGR_CRGU_6__LOGR_CRGU_8__LOGR_CRGU_9_cancelClearsPendingAndPreservesOtherState()
        public
    {
        // Setup: reconfigure baseline recovery address and timelock, seed pending deferred-init tuple, and seed pending
        // recovery-guardian update.
        _resetAndConfigureRecovery();
        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS_B, 4 days, block.timestamp + 7 days
        );
        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        GuardianRecoveryState memory beforeState = harness.getGuardianRecoveryStateViaStorage();

        // Call: cancel recovery guardian update.
        vm.expectEmit(true, true, true, true);
        emit IOrganizationGuardianRecovery.RecoveryGuardianUpdateCancelled(NEW_GUARDIAN_A);
        harness.cancelRecoveryGuardianUpdateViaLibrary();

        // Verify: pending guardian clears; pending guardian timestamp clears.
        GuardianRecoveryState memory afterState = harness.getGuardianRecoveryStateViaStorage();
        assertEq(afterState.pendingGuardian, address(0), "pending guardian should clear");
        assertEq(afterState.pendingGuardianTimestamp, 0, "pending guardian timestamp should clear");
        assertFalse(afterState.isUpdateReadyForAcceptance, "ready flag should clear");
        assertEq(afterState.recoveryAddress, beforeState.recoveryAddress, "config recovery address should remain");
        assertEq(
            afterState.timelockDurationSeconds, beforeState.timelockDurationSeconds, "config timelock should remain"
        );
        assertEq(
            afterState.pendingInit.pendingRecoveryAddress,
            beforeState.pendingInit.pendingRecoveryAddress,
            "pending-init address should remain"
        );
        assertEq(
            afterState.pendingInit.pendingTimelockDurationSeconds,
            beforeState.pendingInit.pendingTimelockDurationSeconds,
            "pending-init timelock should remain"
        );
        assertEq(
            afterState.pendingInit.pendingTimestamp,
            beforeState.pendingInit.pendingTimestamp,
            "pending-init timestamp should remain"
        );
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.cancelRecoveryGuardianUpdate` no pending update reverts with
    /// `NoPendingRecoveryGuardianUpdate`.
    function test_LOGR_CRGU_4_noPendingUpdate_revertsNoPendingRecoveryGuardianUpdate() public {
        // Setup: reconfigure baseline recovery address and timelock.
        _resetAndConfigureRecovery();

        // Call: cancel recovery guardian update, expecting `NoPendingRecoveryGuardianUpdate` revert.
        vm.expectRevert(IOrganizationGuardianRecovery.NoPendingRecoveryGuardianUpdate.selector);
        harness.cancelRecoveryGuardianUpdateViaLibrary();

        // Verify: pending guardian remains clear.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().pendingGuardian,
            address(0),
            "pending guardian should remain clear"
        );
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.cancelRecoveryGuardianUpdate` cancel after finalize still clears
    /// pending and ready-for-acceptance state.
    function test_LOGR_CRGU_7_cancelAfterFinalize_clearsReadyForAcceptanceState() public {
        // Setup: reconfigure baseline recovery address and timelock, seed pending recovery-guardian update, and
        // position timestamp at timelock boundary.
        _resetAndConfigureRecovery();
        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_B);
        vm.warp(harness.getGuardianRecoveryStateViaStorage().pendingGuardianTimestamp);
        harness.finalizeRecoveryGuardianUpdateViaLibrary();
        assertTrue(harness.getGuardianRecoveryStateViaStorage().isUpdateReadyForAcceptance, "precondition: ready=true");

        // Call: cancel recovery guardian update.
        harness.cancelRecoveryGuardianUpdateViaLibrary();

        // Verify: pending guardian clears after cancel; ready flag clears after cancel.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().pendingGuardian,
            address(0),
            "pending guardian should clear after cancel"
        );
        assertFalse(
            harness.getGuardianRecoveryStateViaStorage().isUpdateReadyForAcceptance,
            "ready flag should clear after cancel"
        );
    }
}
