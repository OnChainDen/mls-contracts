// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
import {
    LibOrganizationGuardianSuiteBase
} from "test/organization/libraries/LibOrganizationGuardian/LibOrganizationGuardianSuiteBase.sol";

/**
 * @dev Unit tests for `LibOrganizationGuardian.acceptGuardian`.
 */
contract LibOrganizationGuardianAcceptGuardianTest is LibOrganizationGuardianSuiteBase {
    /// @dev Verifies LOG-AG-1: accept updates guardian to pending guardian address.
    function test_LOG_AG_1_updatesGuardianToPendingGuardian() public {
        // Setup
        _prepareReadyPendingGuardian(NEW_GUARDIAN_A);

        // Call
        harness.acceptGuardianViaLibrary();

        // Verify
        assertEq(harness.getGuardianViaLibrary(), NEW_GUARDIAN_A, "guardian should update to pending guardian");
    }

    /// @dev Verifies LOG-AG-2: accept clears `pendingGuardian`.
    function test_LOG_AG_2_clearsPendingGuardian() public {
        // Setup
        _prepareReadyPendingGuardian(NEW_GUARDIAN_A);

        // Call
        harness.acceptGuardianViaLibrary();

        // Verify
        assertEq(harness.getPendingGuardianViaLibrary(), address(0), "pending guardian should clear after accept");
    }

    /// @dev Verifies LOG-AG-3: accept clears `pendingGuardianUpdateTimestamp`.
    function test_LOG_AG_3_clearsPendingGuardianUpdateTimestamp() public {
        // Setup
        _prepareReadyPendingGuardian(NEW_GUARDIAN_A);

        // Call
        harness.acceptGuardianViaLibrary();

        // Verify
        assertEq(
            harness.getPendingGuardianUpdateTimestampViaLibrary(), 0, "pending timestamp should clear after accept"
        );
    }

    /// @dev Verifies LOG-AG-4: accept clears `isGuardianUpdateReadyForAcceptance`.
    function test_LOG_AG_4_clearsReadyForAcceptanceFlag() public {
        // Setup
        _prepareReadyPendingGuardian(NEW_GUARDIAN_A);

        // Call
        harness.acceptGuardianViaLibrary();

        // Verify
        assertFalse(
            harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(),
            "ready-for-acceptance flag should clear after accept"
        );
    }

    /// @dev Verifies LOG-AG-5: no pending update reverts `NoPendingGuardianUpdate`.
    function test_LOG_AG_5_noPendingUpdate_revertsNoPendingGuardianUpdate() public {
        // Setup
        _clearPendingGuardianState();

        // Call
        vm.expectRevert(IOrganizationGuardian.NoPendingGuardianUpdate.selector);
        harness.acceptGuardianViaLibrary();

        // Verify
        assertEq(harness.getGuardianViaLibrary(), GUARDIAN, "guardian should remain unchanged");
    }

    /// @dev Verifies LOG-AG-6: pending update not ready reverts `GuardianUpdateNotReadyForAcceptance`.
    function test_LOG_AG_6_notReadyForAcceptance_revertsGuardianUpdateNotReadyForAcceptance() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);

        // Call
        vm.expectRevert(IOrganizationGuardian.GuardianUpdateNotReadyForAcceptance.selector);
        harness.acceptGuardianViaLibrary();

        // Verify
        assertEq(harness.getGuardianViaLibrary(), GUARDIAN, "guardian should remain unchanged");
    }

    /// @dev Verifies LOG-AG-7: accept emits `GuardianUpdateAccepted(previousGuardian, newGuardian)`.
    function test_LOG_AG_7_emitsGuardianUpdateAccepted() public {
        // Setup
        _prepareReadyPendingGuardian(NEW_GUARDIAN_A);

        // Call
        vm.expectEmit(true, true, false, true);
        emit IOrganizationGuardian.GuardianUpdateAccepted(GUARDIAN, NEW_GUARDIAN_A);
        harness.acceptGuardianViaLibrary();

        // Verify
        assertEq(harness.getGuardianViaLibrary(), NEW_GUARDIAN_A, "guardian should update");
    }

    /// @dev Verifies LOG-AG-8: old guardian is no longer guardian after acceptance.
    function test_LOG_AG_8_oldGuardianNoLongerGuardian_afterAcceptance() public {
        // Setup
        _prepareReadyPendingGuardian(NEW_GUARDIAN_A);

        // Call
        harness.acceptGuardianViaLibrary();

        // Verify
        assertTrue(harness.getGuardianViaLibrary() != GUARDIAN, "old guardian should no longer be guardian");
    }

    /// @dev Verifies LOG-AG-9: new guardian is current guardian after acceptance.
    function test_LOG_AG_9_newGuardianIsCurrentGuardian_afterAcceptance() public {
        // Setup
        _prepareReadyPendingGuardian(NEW_GUARDIAN_B);

        // Call
        harness.acceptGuardianViaLibrary();

        // Verify
        assertEq(harness.getGuardianViaLibrary(), NEW_GUARDIAN_B, "new guardian should become current guardian");
    }

    /**
     * @dev Prepares a pending guardian update that is finalized and ready for acceptance.
     */
    function _prepareReadyPendingGuardian(address newGuardian) internal {
        _initiateGuardianUpdateViaLibrary(newGuardian);
        vm.warp(harness.getPendingGuardianUpdateTimestampViaLibrary());
        harness.finalizeGuardianUpdateViaLibrary();
    }
}
