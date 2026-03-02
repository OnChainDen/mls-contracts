// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    OrganizationGuardianRecoveryBaseSuiteBase
} from "test/organization/base/OrganizationGuardianRecoveryBase/OrganizationGuardianRecoveryBaseSuiteBase.sol";

/**
 * @dev Unit tests for `OrganizationGuardianRecoveryBase.finalizeRecoveryGuardianUpdate`.
 */
contract OrganizationGuardianRecoveryBaseFinalizeRecoveryGuardianUpdateTest is
    OrganizationGuardianRecoveryBaseSuiteBase
{
    /// @dev Verifies `OrganizationGuardianRecoveryBase.finalizeRecoveryGuardianUpdate` reverts when called by a
    /// non-recovery address.
    function test_OGRB_FRGU_1_nonRecoveryAddressCaller_revertsOnlyGuardianRecoveryAddress() public {
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
    function test_OGRB_FRGU_2_recoveryAddressCaller_delegatesToLibrary() public {
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
}
