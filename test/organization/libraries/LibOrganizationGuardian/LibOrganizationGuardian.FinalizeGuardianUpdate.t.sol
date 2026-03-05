// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdminOperationTimelock} from "interfaces/organization/IOrganizationAdminOperationTimelock.sol";
import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
import {
    LibOrganizationGuardianSuiteBase
} from "test/organization/libraries/LibOrganizationGuardian/LibOrganizationGuardianSuiteBase.sol";

/**
 * @dev Unit tests for `LibOrganizationGuardian.finalizeGuardianUpdate`.
 */
contract LibOrganizationGuardianFinalizeGuardianUpdateTest is LibOrganizationGuardianSuiteBase {
    /// @dev Verifies LOG-FGU-1: finalize after timelock marks update ready for acceptance.
    function test_LOG_FGU_1_afterTimelock_setsReadyForAcceptanceTrue() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        vm.warp(harness.getPendingGuardianUpdateTimestampViaLibrary());

        // Call
        harness.finalizeGuardianUpdateViaLibrary();

        // Verify
        assertTrue(
            harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(),
            "ready-for-acceptance should be true after finalize"
        );
    }

    /// @dev Verifies LOG-FGU-2: finalize before timelock reverts `TimelockNotExpired`.
    function test_LOG_FGU_2_beforeTimelock_revertsTimelockNotExpired() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        uint256 canFinalizeAt = harness.getPendingGuardianUpdateTimestampViaLibrary();

        // Call
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdminOperationTimelock.TimelockNotExpired.selector, canFinalizeAt, block.timestamp
            )
        );
        harness.finalizeGuardianUpdateViaLibrary();

        // Verify
        assertFalse(
            harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(),
            "ready-for-acceptance should remain false before timelock"
        );
    }

    /// @dev Verifies LOG-FGU-3: finalize at exact timelock expiry succeeds.
    function test_LOG_FGU_3_atExactTimelockExpiry_succeeds() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        vm.warp(harness.getPendingGuardianUpdateTimestampViaLibrary());

        // Call
        harness.finalizeGuardianUpdateViaLibrary();

        // Verify
        assertTrue(harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(), "finalize should succeed at expiry");
    }

    /// @dev Verifies LOG-FGU-4: no pending update reverts `NoPendingGuardianUpdate`.
    function test_LOG_FGU_4_noPendingUpdate_revertsNoPendingGuardianUpdate() public {
        // Setup
        _clearPendingGuardianState();

        // Call
        vm.expectRevert(IOrganizationGuardian.NoPendingGuardianUpdate.selector);
        harness.finalizeGuardianUpdateViaLibrary();

        // Verify
        assertFalse(
            harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(),
            "ready-for-acceptance should remain false without pending update"
        );
    }

    /// @dev Verifies LOG-FGU-5: finalize emits `GuardianUpdateFinalized`.
    function test_LOG_FGU_5_emitsGuardianUpdateFinalized() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        vm.warp(harness.getPendingGuardianUpdateTimestampViaLibrary());

        // Call
        vm.expectEmit(true, false, false, true);
        emit IOrganizationGuardian.GuardianUpdateFinalized(NEW_GUARDIAN_A);
        harness.finalizeGuardianUpdateViaLibrary();

        // Verify
        assertTrue(harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(), "ready flag should be true");
    }

    /// @dev Verifies LOG-FGU-6: finalize does not mutate guardian, only marks ready state.
    function test_LOG_FGU_6_finalizeDoesNotChangeGuardian_onlyMarksReady() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        vm.warp(harness.getPendingGuardianUpdateTimestampViaLibrary());

        // Call
        harness.finalizeGuardianUpdateViaLibrary();

        // Verify
        assertEq(harness.getGuardianViaLibrary(), GUARDIAN, "guardian should not change during finalize");
        assertEq(harness.getPendingGuardianViaLibrary(), NEW_GUARDIAN_A, "pending guardian should remain set");
        assertTrue(harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(), "ready flag should become true");
    }

    /// @dev Verifies LOG-FGU-7: double finalize is an idempotent no-op after first success.
    function test_LOG_FGU_7_doubleFinalize_secondCallIsNoOp() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        vm.warp(harness.getPendingGuardianUpdateTimestampViaLibrary());
        harness.finalizeGuardianUpdateViaLibrary();

        // Call
        harness.finalizeGuardianUpdateViaLibrary();

        // Verify
        assertEq(harness.getGuardianViaLibrary(), GUARDIAN, "guardian should remain unchanged");
        assertEq(harness.getPendingGuardianViaLibrary(), NEW_GUARDIAN_A, "pending guardian should remain set");
        assertTrue(harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(), "ready flag should stay true");
    }
}
