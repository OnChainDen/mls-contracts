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
        // Setup: use default fixture state.
        _setPendingRecoveryUpdate(NEW_GUARDIAN_A, block.timestamp + GUARDIAN_RECOVERY_TIMELOCK, false);

        // Call: invoke `OrganizationGuardianRecoveryBase.finalizeRecoveryGuardianUpdate` as `NON_GUARDIAN`.
        _expectOnlyGuardianRecoveryAddressRevert(NON_GUARDIAN, GUARDIAN_RECOVERY_ADDRESS);
        vm.prank(NON_GUARDIAN);
        harness.finalizeRecoveryGuardianUpdate();

        // Verify: confirm pending recovery-update fields.
        assertFalse(harness.getGuardianRecoveryState().isUpdateReadyForAcceptance, "ready flag should remain false");
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.finalizeRecoveryGuardianUpdate` recovery address caller
    /// delegates to library and marks update ready.
    function test_OGRB_FRGU_2_recoveryAddressCaller_delegatesToLibrary() public {
        // Setup: use default fixture state.
        _setPendingRecoveryUpdate(NEW_GUARDIAN_A, block.timestamp, false);

        // Call: invoke `OrganizationGuardianRecoveryBase.finalizeRecoveryGuardianUpdate` as
        // `GUARDIAN_RECOVERY_ADDRESS`.
        vm.prank(GUARDIAN_RECOVERY_ADDRESS);
        harness.finalizeRecoveryGuardianUpdate();

        // Verify: confirm pending recovery-update state remains unchanged.
        assertTrue(harness.getGuardianRecoveryState().isUpdateReadyForAcceptance, "ready flag should be true");
        assertEq(
            harness.getGuardianRecoveryState().pendingGuardian,
            NEW_GUARDIAN_A,
            "pending guardian should remain unchanged"
        );
    }
}
