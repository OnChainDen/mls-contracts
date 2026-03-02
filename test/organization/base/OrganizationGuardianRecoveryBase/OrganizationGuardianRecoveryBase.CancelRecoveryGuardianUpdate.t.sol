// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    OrganizationGuardianRecoveryBaseSuiteBase
} from "test/organization/base/OrganizationGuardianRecoveryBase/OrganizationGuardianRecoveryBaseSuiteBase.sol";

/**
 * @dev Unit tests for `OrganizationGuardianRecoveryBase.cancelRecoveryGuardianUpdate`.
 */
contract OrganizationGuardianRecoveryBaseCancelRecoveryGuardianUpdateTest is OrganizationGuardianRecoveryBaseSuiteBase {
    /// @dev Verifies `OrganizationGuardianRecoveryBase.cancelRecoveryGuardianUpdate` reverts when called by a
    /// non-recovery address.
    function test_OGRB_CRGU_1_nonRecoveryAddressCaller_revertsOnlyGuardianRecoveryAddress() public {
        // Setup: seed pending recovery-guardian update.
        recoveryStateHarness.setGuardianRecoveryPendingUpdate(
            NEW_GUARDIAN_A, block.timestamp + GUARDIAN_RECOVERY_TIMELOCK, false
        );

        // Call: cancel recovery guardian update as `NON_GUARDIAN`, expecting revert from the recovery-address gate.
        _expectOnlyGuardianRecoveryAddressRevert(NON_GUARDIAN, GUARDIAN_RECOVERY_ADDRESS);
        vm.prank(NON_GUARDIAN);
        harness.cancelRecoveryGuardianUpdate();

        // Verify: pending guardian remains unchanged.
        assertEq(
            harness.getGuardianRecoveryState().pendingGuardian,
            NEW_GUARDIAN_A,
            "pending guardian should remain unchanged"
        );
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.cancelRecoveryGuardianUpdate` recovery address caller delegates
    /// to library and clears pending state.
    function test_OGRB_CRGU_2_recoveryAddressCaller_delegatesToLibrary() public {
        // Setup: seed pending recovery-guardian update.
        recoveryStateHarness.setGuardianRecoveryPendingUpdate(
            NEW_GUARDIAN_A, block.timestamp + GUARDIAN_RECOVERY_TIMELOCK, true
        );

        // Call: cancel recovery guardian update as `GUARDIAN_RECOVERY_ADDRESS`.
        vm.prank(GUARDIAN_RECOVERY_ADDRESS);
        harness.cancelRecoveryGuardianUpdate();

        // Verify: pending guardian clears; pending timestamp clears.
        assertEq(harness.getGuardianRecoveryState().pendingGuardian, address(0), "pending guardian should clear");
        assertEq(harness.getGuardianRecoveryState().pendingGuardianTimestamp, 0, "pending timestamp should clear");
        assertFalse(harness.getGuardianRecoveryState().isUpdateReadyForAcceptance, "ready flag should clear");
    }
}
