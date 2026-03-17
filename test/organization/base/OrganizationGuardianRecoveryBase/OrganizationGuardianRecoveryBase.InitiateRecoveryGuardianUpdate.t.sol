// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

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
    /// @dev Verifies recovery-only guardian entrypoints reject unauthorized callers before any pending recovery state
    /// is written. [OREC-GRF-2]
    function test_OGRB_IRGU_1__OREC_GRF_2__GREC_INV_6_A_nonRecoveryAddressCaller_revertsOnlyGuardianRecoveryAddress()
        public
    {
        // Setup: reuse suite baseline where guardian-recovery is configured.
        address caller = address(0xCA11);

        // Call: initiate recovery guardian update as `caller`, expecting revert from the recovery-address gate.
        _expectOnlyGuardianRecoveryAddressRevert(caller, GUARDIAN_RECOVERY_ADDRESS);
        vm.prank(caller);
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN_A);

        // Verify: pending guardian remains clear.
        assertEq(harness.getGuardianRecoveryState().pendingGuardian, address(0), "pending guardian should remain clear");
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.initiateRecoveryGuardianUpdate` recovery address caller
    /// delegates to library and writes pending state.
    function test_OGRB_IRGU_2_recoveryAddressCaller_delegatesToLibrary() public {
        // Setup: reuse suite baseline where guardian-recovery is configured.
        uint256 expectedFinalizeAt = block.timestamp + GUARDIAN_RECOVERY_TIMELOCK;

        // Call: initiate recovery guardian update as `GUARDIAN_RECOVERY_ADDRESS`.
        vm.prank(GUARDIAN_RECOVERY_ADDRESS);
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN_A);

        // Verify: pending guardian is set.
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
        // Setup: reuse suite baseline where guardian-recovery is configured.
        recoveryStateHarness.setGuardianRecoveryConfig(GUARDIAN_RECOVERY_ADDRESS, 1 days);

        // Call: initiate recovery guardian update as `GUARDIAN_RECOVERY_ADDRESS`, expecting
        // authorization/state-validation revert.
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

        // Verify: pending guardian must remain clear; pending timestamp must remain clear.
        assertEq(harness.getGuardianRecoveryState().pendingGuardian, address(0), "pending guardian must remain clear");
        assertEq(harness.getGuardianRecoveryState().pendingGuardianTimestamp, 0, "pending timestamp must remain clear");
    }
}
