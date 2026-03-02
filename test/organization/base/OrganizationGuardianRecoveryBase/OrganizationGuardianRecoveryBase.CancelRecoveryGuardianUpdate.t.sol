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
        // Setup: use default fixture state.
        recoveryStateHarness.setGuardianRecoveryPendingUpdate(
            NEW_GUARDIAN_A, block.timestamp + GUARDIAN_RECOVERY_TIMELOCK, false
        );

        // Call: invoke `OrganizationGuardianRecoveryBase.cancelRecoveryGuardianUpdate` as `NON_GUARDIAN`.
        _expectOnlyGuardianRecoveryAddressRevert(NON_GUARDIAN, GUARDIAN_RECOVERY_ADDRESS);
        vm.prank(NON_GUARDIAN);
        harness.cancelRecoveryGuardianUpdate();

        // Verify: confirm pending recovery-update state remains unchanged.
        assertEq(
            harness.getGuardianRecoveryState().pendingGuardian,
            NEW_GUARDIAN_A,
            "pending guardian should remain unchanged"
        );
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.cancelRecoveryGuardianUpdate` recovery address caller delegates
    /// to library and clears pending state.
    function test_OGRB_CRGU_2_recoveryAddressCaller_delegatesToLibrary() public {
        // Setup: use default fixture state.
        recoveryStateHarness.setGuardianRecoveryPendingUpdate(
            NEW_GUARDIAN_A, block.timestamp + GUARDIAN_RECOVERY_TIMELOCK, true
        );

        // Call: invoke `OrganizationGuardianRecoveryBase.cancelRecoveryGuardianUpdate` as `GUARDIAN_RECOVERY_ADDRESS`.
        vm.prank(GUARDIAN_RECOVERY_ADDRESS);
        harness.cancelRecoveryGuardianUpdate();

        // Verify: confirm pending recovery-update fields are fully cleared.
        assertEq(harness.getGuardianRecoveryState().pendingGuardian, address(0), "pending guardian should clear");
        assertEq(harness.getGuardianRecoveryState().pendingGuardianTimestamp, 0, "pending timestamp should clear");
        assertFalse(harness.getGuardianRecoveryState().isUpdateReadyForAcceptance, "ready flag should clear");
    }
}
