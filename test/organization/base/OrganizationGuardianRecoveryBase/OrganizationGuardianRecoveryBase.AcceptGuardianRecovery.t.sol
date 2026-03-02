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
    /// @dev Verifies `OrganizationGuardianRecoveryBase.acceptGuardianRecovery` reverts when called by a non-pending
    /// guardian.
    function test_OGRB_AGR_1_nonPendingGuardianCaller_revertsOnlyRecoveryPendingGuardian() public {
        // Setup: use default fixture state.
        _setPendingRecoveryUpdate(NEW_GUARDIAN_A, block.timestamp, true);

        // Call: execute `OrganizationGuardianRecoveryBase.acceptGuardianRecovery` from a non-pending guardian and
        // expect the pending-guardian gate revert.
        _expectOnlyRecoveryPendingGuardianRevert(NON_GUARDIAN, NEW_GUARDIAN_A);
        vm.prank(NON_GUARDIAN);
        harness.acceptGuardianRecovery();

        // Verify: confirm the asserted post-conditions.
        assertEq(recoveryStateHarness.getGuardianStorage(), GUARDIAN, "guardian should remain unchanged");
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.acceptGuardianRecovery` recovery pending guardian caller
    /// delegates to library and completes acceptance.
    function test_OGRB_AGR_2_recoveryPendingGuardianCaller_delegatesAndAccepts() public {
        // Setup: use default fixture state.
        _setPendingRecoveryUpdate(NEW_GUARDIAN_A, block.timestamp, true);

        // Call: invoke `OrganizationGuardianRecoveryBase.acceptGuardianRecovery` as `NEW_GUARDIAN_A`.
        vm.prank(NEW_GUARDIAN_A);
        harness.acceptGuardianRecovery();

        // Verify: confirm pending recovery-update fields are fully cleared.
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
}
