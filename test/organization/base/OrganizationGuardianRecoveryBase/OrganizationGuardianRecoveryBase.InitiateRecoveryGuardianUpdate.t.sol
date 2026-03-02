// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {TimelockUtils} from "libraries/TimelockUtils.sol";
import {
    OrganizationGuardianRecoveryBaseSuiteBase
} from "test/organization/base/OrganizationGuardianRecoveryBase/OrganizationGuardianRecoveryBaseSuiteBase.sol";

/**
 * @dev Unit tests for `OrganizationGuardianRecoveryBase.initiateRecoveryGuardianUpdate`.
 */
contract OrganizationGuardianRecoveryBaseInitiateRecoveryGuardianUpdateTest is
    OrganizationGuardianRecoveryBaseSuiteBase
{
    /// @dev Verifies `OrganizationGuardianRecoveryBase.initiateRecoveryGuardianUpdate` reverts when called by a
    /// non-recovery address.
    function test_OGRB_IRGU_1_nonRecoveryAddressCaller_revertsOnlyGuardianRecoveryAddress() public {
        // Setup: use default fixture state.
        address caller = address(0xCA11);

        // Call: invoke `OrganizationGuardianRecoveryBase.initiateRecoveryGuardianUpdate` as `caller`.
        _expectOnlyGuardianRecoveryAddressRevert(caller, GUARDIAN_RECOVERY_ADDRESS);
        vm.prank(caller);
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN_A);

        // Verify: confirm pending recovery-update fields.
        assertEq(harness.getGuardianRecoveryState().pendingGuardian, address(0), "pending guardian should remain clear");
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.initiateRecoveryGuardianUpdate` recovery address caller
    /// delegates to library and writes pending state.
    function test_OGRB_IRGU_2_recoveryAddressCaller_delegatesToLibrary() public {
        // Setup: use default fixture state.
        uint256 expectedFinalizeAt = block.timestamp + GUARDIAN_RECOVERY_TIMELOCK;

        // Call: invoke `OrganizationGuardianRecoveryBase.initiateRecoveryGuardianUpdate` as
        // `GUARDIAN_RECOVERY_ADDRESS`.
        vm.prank(GUARDIAN_RECOVERY_ADDRESS);
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN_A);

        // Verify: confirm pending recovery-update fields.
        assertEq(harness.getGuardianRecoveryState().pendingGuardian, NEW_GUARDIAN_A, "pending guardian should be set");
        assertEq(
            harness.getGuardianRecoveryState().pendingGuardianTimestamp,
            expectedFinalizeAt,
            "pending timestamp should equal block.timestamp + recovery timelock"
        );
        assertFalse(
            harness.getGuardianRecoveryState().isUpdateReadyForAcceptance,
            "ready flag should be false immediately after initiate"
        );
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.initiateRecoveryGuardianUpdate` out-of-range configured timelock
    /// reverts and does not create pending state.
    function test_OGRB_IRGU_3_invalidConfiguredTimelock_revertsInvalidTimelockAndDoesNotCreatePendingState() public {
        // Setup: use default fixture state.
        recoveryStateHarness.setGuardianRecoveryConfig(GUARDIAN_RECOVERY_ADDRESS, 1 days);

        // Call: invoke `OrganizationGuardianRecoveryBase.initiateRecoveryGuardianUpdate` as `GUARDIAN_RECOVERY_ADDRESS`
        // and assert the expected revert.
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                1 days,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        vm.prank(GUARDIAN_RECOVERY_ADDRESS);
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN_A);

        // Verify: confirm pending recovery-update fields.
        assertEq(harness.getGuardianRecoveryState().pendingGuardian, address(0), "pending guardian must remain clear");
        assertEq(harness.getGuardianRecoveryState().pendingGuardianTimestamp, 0, "pending timestamp must remain clear");
    }
}
