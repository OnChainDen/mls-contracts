// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdminOperationTimelock} from "interfaces/organization/IOrganizationAdminOperationTimelock.sol";
import {
    OrganizationGuardianRecoveryBaseSuiteBase
} from "test/organization/base/OrganizationGuardianRecoveryBase/OrganizationGuardianRecoveryBaseSuiteBase.sol";

/**
 * @dev Unit tests for `OrganizationGuardianRecoveryBase.finalizeRecoveryGuardianUpdate`.
 */
contract OrganizationGuardianRecoveryBaseFinalizeRecoveryGuardianUpdateTest is
    OrganizationGuardianRecoveryBaseSuiteBase
{
    /// @dev Verifies recovery-only guardian entrypoints reject unauthorized callers before readiness flags can change.
    function test_nonRecoveryAddressCaller_revertsOnlyGuardianRecoveryAddress() public {
        // Setup: seed pending recovery-guardian update.
        recoveryStateHarness.setGuardianRecoveryPendingUpdate(
            NEW_GUARDIAN_A, block.timestamp + GUARDIAN_RECOVERY_TIMELOCK, false
        );

        // Call: finalize recovery guardian update as `NON_GUARDIAN`, expecting revert from the recovery-address gate.
        _expectOnlyGuardianRecoveryAddressRevert(NON_GUARDIAN, GUARDIAN_RECOVERY_ADDRESS);
        vm.prank(NON_GUARDIAN);
        harness.finalizeRecoveryGuardianUpdate();

        // Verify: ready flag remains false.
        assertFalse(harness.getGuardianRecoveryState().isUpdateReadyForAcceptance, "ready flag should remain false");
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.finalizeRecoveryGuardianUpdate` recovery address caller
    /// delegates to library and marks update ready.
    function test_recoveryAddressCaller_delegatesToLibrary() public {
        // Setup: seed pending recovery-guardian update.
        recoveryStateHarness.setGuardianRecoveryPendingUpdate(NEW_GUARDIAN_A, block.timestamp, false);

        // Call: finalize recovery guardian update as `GUARDIAN_RECOVERY_ADDRESS`.
        vm.prank(GUARDIAN_RECOVERY_ADDRESS);
        harness.finalizeRecoveryGuardianUpdate();

        // Verify: ready flag is true.
        assertTrue(harness.getGuardianRecoveryState().isUpdateReadyForAcceptance, "ready flag should be true");
        assertEq(
            harness.getGuardianRecoveryState().pendingGuardian,
            NEW_GUARDIAN_A,
            "pending guardian should remain unchanged"
        );
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.finalizeRecoveryGuardianUpdate` reverts before the configured
    /// recovery timelock expires and succeeds at the exact boundary.
    function test_finalizeRecoveryGuardianUpdate_beforeTimelockReverts_andBoundarySucceeds() public {
        // Setup: stage a recovery-only guardian update whose finalize timestamp is one recovery timelock in the
        // future.
        vm.prank(GUARDIAN_RECOVERY_ADDRESS);
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN_A);

        uint256 canFinalizeAt = harness.getGuardianRecoveryState().pendingGuardianTimestamp;

        // Call: finalize once before the recovery timelock expires, then retry at the exact boundary.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdminOperationTimelock.TimelockNotExpired.selector, canFinalizeAt, block.timestamp
            )
        );
        vm.prank(GUARDIAN_RECOVERY_ADDRESS);
        harness.finalizeRecoveryGuardianUpdate();

        vm.warp(canFinalizeAt);
        vm.prank(GUARDIAN_RECOVERY_ADDRESS);
        harness.finalizeRecoveryGuardianUpdate();

        // Verify: boundary success marks the recovery update ready for acceptance without mutating the pending
        // guardian value itself.
        assertTrue(harness.getGuardianRecoveryState().isUpdateReadyForAcceptance, "ready flag should be true");
        assertEq(
            harness.getGuardianRecoveryState().pendingGuardian,
            NEW_GUARDIAN_A,
            "pending guardian should remain staged for accept"
        );
        assertEq(
            harness.getGuardianRecoveryState().pendingGuardianTimestamp,
            canFinalizeAt,
            "timelock boundary should preserve the staged finalize timestamp"
        );
    }
}
