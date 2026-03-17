// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    OrganizationGuardianRecoveryBaseSuiteBase
} from "test/organization/base/OrganizationGuardianRecoveryBase/OrganizationGuardianRecoveryBaseSuiteBase.sol";

/**
 * @dev Unit tests for `OrganizationGuardianRecoveryBase.acceptGuardianRecovery`.
 */
contract OrganizationGuardianRecoveryBaseAcceptGuardianRecoveryTest is OrganizationGuardianRecoveryBaseSuiteBase {
    /// @dev Verifies recovery-only guardian entrypoints reject unauthorized callers before a staged recovery guardian
    /// can be accepted.
    function test_nonPendingGuardianCaller_revertsOnlyRecoveryPendingGuardian()
        public
    {
        // Setup: seed pending recovery-guardian update.
        recoveryStateHarness.setGuardianRecoveryPendingUpdate(NEW_GUARDIAN_A, block.timestamp, true);

        // Call: accept recovery guardian update as `NON_GUARDIAN`, expecting revert from the pending-guardian gate.
        _expectOnlyRecoveryPendingGuardianRevert(NON_GUARDIAN, NEW_GUARDIAN_A);
        vm.prank(NON_GUARDIAN);
        harness.acceptGuardianRecovery();

        // Verify: guardian remains unchanged.
        assertEq(recoveryStateHarness.getGuardianStorage(), GUARDIAN, "guardian should remain unchanged");
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.acceptGuardianRecovery` recovery pending guardian caller
    /// delegates to library and completes acceptance.
    function test_recoveryPendingGuardianCaller_delegatesAndAccepts() public {
        // Setup: seed pending recovery-guardian update.
        recoveryStateHarness.setGuardianRecoveryPendingUpdate(NEW_GUARDIAN_A, block.timestamp, true);

        // Call: accept recovery guardian update as `NEW_GUARDIAN_A`.
        vm.prank(NEW_GUARDIAN_A);
        harness.acceptGuardianRecovery();

        // Verify: pending guardian clears.
        assertEq(
            recoveryStateHarness.getGuardianStorage(), NEW_GUARDIAN_A, "guardian should update to pending guardian"
        );
        assertEq(harness.getGuardianRecoveryState().pendingGuardian, address(0), "pending guardian should clear");
        assertEq(
            harness.getGuardianRecoveryState().pendingGuardianTimestamp, 0, "pending guardian timestamp should clear"
        );
        assertFalse(
            harness.getGuardianRecoveryState().isUpdateReadyForAcceptance, "ready-for-acceptance flag should clear"
        );
    }

    /// @dev Verifies a configured recovery address can rotate the guardian after the recovery timelock without any
    /// participation from the current guardian.
    function test_recoveryAddressRotatesGuardianAfterTimelockWithoutCurrentGuardianParticipation() public {
        // Setup: start from the suite baseline where guardian recovery is configured and no recovery update is
        // pending.
        address originalGuardian = recoveryStateHarness.getGuardianStorage();

        // Call: initiate and finalize as the recovery address, then accept as the pending guardian after the recovery
        // timelock elapses.
        vm.prank(GUARDIAN_RECOVERY_ADDRESS);
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN_A);

        vm.warp(harness.getGuardianRecoveryState().pendingGuardianTimestamp);
        vm.prank(GUARDIAN_RECOVERY_ADDRESS);
        harness.finalizeRecoveryGuardianUpdate();

        vm.prank(NEW_GUARDIAN_A);
        harness.acceptGuardianRecovery();

        // Verify: the guardian rotates away from the original guardian and the recovery-specific pending state fully
        // clears.
        assertEq(originalGuardian, GUARDIAN, "baseline guardian should start as the configured guardian fixture");
        assertEq(recoveryStateHarness.getGuardianStorage(), NEW_GUARDIAN_A, "guardian should rotate via recovery flow");
        assertEq(harness.getGuardianRecoveryState().pendingGuardian, address(0), "pending guardian should clear");
        assertEq(
            harness.getGuardianRecoveryState().pendingGuardianTimestamp,
            0,
            "pending recovery timelock timestamp should clear"
        );
        assertFalse(
            harness.getGuardianRecoveryState().isUpdateReadyForAcceptance,
            "ready-for-acceptance flag should clear after accept"
        );
    }

    /// @dev Verifies normal guardian updates and guardian-recovery updates can coexist without corrupting each
    /// other's pending state.
    function test_recoveryAndNormalGuardianUpdateFlowsRemainIsolated() public {
        // Setup: stage a normal guardian update directly in base guardian storage, then start a separate recovery
        // guardian update through the recovery-only entrypoint.
        recoveryStateHarness.setPendingGuardian(NEW_GUARDIAN_B);
        recoveryStateHarness.setPendingGuardianUpdateTimestamp(block.timestamp + 5 days);
        recoveryStateHarness.setIsGuardianUpdateReadyForAcceptance(false);

        uint256 normalPendingTimestamp = recoveryStateHarness.getPendingGuardianUpdateTimestampStorage();

        vm.prank(GUARDIAN_RECOVERY_ADDRESS);
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN_A);

        // Call: complete the recovery-specific guardian rotation while leaving the normal update untouched.
        vm.warp(harness.getGuardianRecoveryState().pendingGuardianTimestamp);
        vm.prank(GUARDIAN_RECOVERY_ADDRESS);
        harness.finalizeRecoveryGuardianUpdate();

        vm.prank(NEW_GUARDIAN_A);
        harness.acceptGuardianRecovery();

        // Verify: recovery flow rotates the active guardian and clears only recovery-specific pending state; the
        // normal pending update tuple remains intact.
        assertEq(recoveryStateHarness.getGuardianStorage(), NEW_GUARDIAN_A, "recovery accept should rotate guardian");
        assertEq(recoveryStateHarness.getPendingGuardianStorage(), NEW_GUARDIAN_B, "normal pending guardian persists");
        assertEq(
            recoveryStateHarness.getPendingGuardianUpdateTimestampStorage(),
            normalPendingTimestamp,
            "normal pending timestamp should be preserved"
        );
        assertFalse(
            recoveryStateHarness.getIsGuardianUpdateReadyForAcceptanceStorage(),
            "normal ready-for-acceptance flag should be preserved"
        );
        assertEq(harness.getGuardianRecoveryState().pendingGuardian, address(0), "recovery pending guardian clears");
        assertEq(harness.getGuardianRecoveryState().pendingGuardianTimestamp, 0, "recovery pending timestamp clears");
    }
}
