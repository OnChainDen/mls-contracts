// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {
    LibOrganizationGuardianRecoverySuiteBase
} from "test/organization/libraries/LibOrganizationGuardianRecovery/LibOrganizationGuardianRecoverySuiteBase.sol";
import {GuardianRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Unit tests for `LibOrganizationGuardianRecovery.acceptGuardianRecovery`.
 */
contract LibOrganizationGuardianRecoveryAcceptGuardianRecoveryTest is LibOrganizationGuardianRecoverySuiteBase {
    /// @dev Verifies `LibOrganizationGuardianRecovery.acceptGuardianRecovery` accept writes guardian in normal storage,
    /// clears pending, emits event, and preserves config/pending-init.
    function test_acceptUpdatesGuardianAndClearsPending() public {
        // Setup: reconfigure baseline recovery address and timelock, seed pending deferred-init tuple, and seed pending
        // recovery-guardian update.
        _resetAndConfigureRecovery();
        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS_B, 4 days, block.timestamp + 8 days
        );
        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        vm.warp(harness.getGuardianRecoveryStateViaStorage().pendingGuardianTimestamp);
        harness.finalizeRecoveryGuardianUpdateViaLibrary();

        address previousGuardian = harness.getGuardianViaLibrary();
        GuardianRecoveryState memory beforeState = harness.getGuardianRecoveryStateViaStorage();

        // Call: accept recovery guardian update.
        vm.expectEmit(true, true, true, true);
        emit IOrganizationGuardianRecovery.RecoveryGuardianUpdateAccepted(previousGuardian, NEW_GUARDIAN_A);
        harness.acceptGuardianRecoveryViaLibrary();

        // Verify: guardian updates in normal guardian storage; pending guardian clears.
        GuardianRecoveryState memory afterState = harness.getGuardianRecoveryStateViaStorage();
        assertEq(harness.getGuardianViaLibrary(), NEW_GUARDIAN_A, "guardian should update in normal guardian storage");
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
        assertTrue(previousGuardian != NEW_GUARDIAN_A, "old guardian should no longer be guardian after acceptance");
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.acceptGuardianRecovery` no pending update reverts with
    /// `NoPendingRecoveryGuardianUpdate`.
    function test_noPendingUpdate_revertsNoPendingRecoveryGuardianUpdate() public {
        // Setup: reconfigure baseline recovery address and timelock.
        _resetAndConfigureRecovery();

        // Call: accept recovery guardian update, expecting `NoPendingRecoveryGuardianUpdate` revert.
        vm.expectRevert(IOrganizationGuardianRecovery.NoPendingRecoveryGuardianUpdate.selector);
        harness.acceptGuardianRecoveryViaLibrary();

        // Verify: guardian remains unchanged.
        assertEq(harness.getGuardianViaLibrary(), GUARDIAN, "guardian should remain unchanged");
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.acceptGuardianRecovery` not-ready update reverts with
    /// `RecoveryGuardianUpdateNotReadyForAcceptance`.
    function test_notReadyForAcceptance_revertsRecoveryGuardianUpdateNotReadyForAcceptance() public {
        // Setup: reconfigure baseline recovery address and timelock and seed pending recovery-guardian update.
        _resetAndConfigureRecovery();
        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_A);

        // Call: accept recovery guardian update, expecting `RecoveryGuardianUpdateNotReadyForAcceptance` revert.
        vm.expectRevert(IOrganizationGuardianRecovery.RecoveryGuardianUpdateNotReadyForAcceptance.selector);
        harness.acceptGuardianRecoveryViaLibrary();

        // Verify: guardian remains unchanged.
        assertEq(harness.getGuardianViaLibrary(), GUARDIAN, "guardian should remain unchanged");
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.acceptGuardianRecovery` pending guardian equal to current
    /// guardian still clears pending and emits event with equal addresses.
    function test_pendingGuardianEqualsCurrentGuardian_acceptStillClearsStateAndEmits() public {
        // Setup: reconfigure baseline recovery address and timelock, seed pending recovery-guardian update, and
        // position timestamp at timelock boundary.
        _resetAndConfigureRecovery();
        recoveryStateHarness.setGuardian(NEW_GUARDIAN_B);
        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_B);
        vm.warp(harness.getGuardianRecoveryStateViaStorage().pendingGuardianTimestamp);
        harness.finalizeRecoveryGuardianUpdateViaLibrary();

        // Call: accept recovery guardian update.
        vm.expectEmit(true, true, true, true);
        emit IOrganizationGuardianRecovery.RecoveryGuardianUpdateAccepted(NEW_GUARDIAN_B, NEW_GUARDIAN_B);
        harness.acceptGuardianRecoveryViaLibrary();

        // Verify: guardian remains the same address.
        assertEq(harness.getGuardianViaLibrary(), NEW_GUARDIAN_B, "guardian should remain the same address");
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().pendingGuardian,
            address(0),
            "pending guardian should still clear"
        );
    }
}
