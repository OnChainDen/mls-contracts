// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
import {
    LibOrganizationGuardianSuiteBase
} from "test/organization/libraries/LibOrganizationGuardian/LibOrganizationGuardianSuiteBase.sol";

/**
 * @dev Unit tests for `LibOrganizationGuardian.initiateGuardianUpdate`.
 */
contract LibOrganizationGuardianInitiateGuardianUpdateTest is LibOrganizationGuardianSuiteBase {
    /// @dev Verifies valid new guardian sets pending guardian in storage.
    function test_validNewGuardian_setsPendingGuardian() public {
        // Setup
        _clearPendingGuardianState();

        // Call
        harness.initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);

        // Verify
        assertEq(harness.getPendingGuardianViaLibrary(), NEW_GUARDIAN_A, "pending guardian should be set");
    }

    /// @dev Verifies zero-address guardian reverts `InvalidGuardianAddress`.
    function test_zeroAddress_revertsInvalidGuardianAddress() public {
        // Setup
        _clearPendingGuardianState();

        // Call
        vm.expectRevert(IOrganizationGuardian.InvalidGuardianAddress.selector);
        harness.initiateGuardianUpdateViaLibrary(address(0));

        // Verify
        assertEq(harness.getPendingGuardianViaLibrary(), address(0), "pending guardian should remain unset");
    }

    /// @dev Verifies existing pending update reverts `GuardianUpdateAlreadyPending`.
    function test_alreadyPending_revertsGuardianUpdateAlreadyPending() public {
        // Setup
        guardianStateHarness.setPendingGuardian(NEW_GUARDIAN_A);
        guardianStateHarness.setPendingGuardianUpdateTimestamp(block.timestamp + 1 days);
        guardianStateHarness.setIsGuardianUpdateReadyForAcceptance(false);

        // Call
        vm.expectRevert(IOrganizationGuardian.GuardianUpdateAlreadyPending.selector);
        harness.initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_B);

        // Verify
        assertEq(harness.getPendingGuardianViaLibrary(), NEW_GUARDIAN_A, "existing pending guardian should remain");
    }

    /// @dev Verifies `canFinalizeAtTimestamp` equals `block.timestamp + timelockDuration`.
    function test_canFinalizeTimestamp_equalsBlockTimestampPlusTimelockDuration() public {
        // Setup
        _clearPendingGuardianState();
        uint256 expectedCanFinalizeAt = block.timestamp + ADMIN_OPERATION_TIMELOCK;

        // Call
        harness.initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);

        // Verify
        assertEq(
            harness.getPendingGuardianUpdateTimestampViaLibrary(),
            expectedCanFinalizeAt,
            "pending timestamp should match computed finalize timestamp"
        );
    }

    /// @dev Verifies initiation sets `isGuardianUpdateReadyForAcceptance` to false.
    function test_setsReadyForAcceptanceFalse() public {
        // Setup
        guardianStateHarness.setIsGuardianUpdateReadyForAcceptance(true);
        guardianStateHarness.setPendingGuardian(address(0));
        guardianStateHarness.setPendingGuardianUpdateTimestamp(0);

        // Call
        harness.initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);

        // Verify
        assertFalse(
            harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(),
            "ready-for-acceptance should be false after initiate"
        );
    }

    /// @dev Verifies initiation emits `GuardianUpdateInitiated` with expected payload.
    function test_emitsGuardianUpdateInitiated() public {
        // Setup
        _clearPendingGuardianState();
        uint256 expectedCanFinalizeAt = block.timestamp + ADMIN_OPERATION_TIMELOCK;

        // Call
        vm.expectEmit(true, true, false, true);
        emit IOrganizationGuardian.GuardianUpdateInitiated(GUARDIAN, NEW_GUARDIAN_A, expectedCanFinalizeAt);
        harness.initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);

        // Verify
        assertEq(harness.getPendingGuardianViaLibrary(), NEW_GUARDIAN_A, "pending guardian should be set");
    }

    /// @dev Verifies `LibOrganizationGuardian.initiateGuardianUpdate` emits the same `canFinalizeAtTimestamp` that it
    /// persists in storage for the pending guardian update.
    function test_initiateGuardianUpdate_eventTimestampMatchesPersistedPendingTimestamp() public {
        // Setup: clear any pending guardian state and precompute the expected finalize timestamp from the admin-op
        // timelock.
        _clearPendingGuardianState();
        uint256 expectedCanFinalizeAt = block.timestamp + ADMIN_OPERATION_TIMELOCK;

        // Call: initiate the guardian update while asserting the emitted event payload.
        vm.expectEmit(true, true, false, true);
        emit IOrganizationGuardian.GuardianUpdateInitiated(GUARDIAN, NEW_GUARDIAN_A, expectedCanFinalizeAt);
        harness.initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);

        // Verify: the stored pending timestamp matches the exact timestamp emitted in the event.
        assertEq(
            harness.getPendingGuardianUpdateTimestampViaLibrary(),
            expectedCanFinalizeAt,
            "event timestamp should match the persisted pending timestamp"
        );
    }

    /// @dev Verifies initiating update does not change current guardian.
    function test_currentGuardianRemainsUnchangedDuringPendingState() public {
        // Setup
        _clearPendingGuardianState();

        // Call
        harness.initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);

        // Verify
        assertEq(harness.getGuardianViaLibrary(), GUARDIAN, "current guardian should not change during initiate");
    }

    /// @dev Verifies proposing the same address as current guardian is allowed.
    function test_sameAddressAsCurrentGuardian_stillSucceeds() public {
        // Setup
        _clearPendingGuardianState();

        // Call
        harness.initiateGuardianUpdateViaLibrary(GUARDIAN);

        // Verify
        assertEq(harness.getPendingGuardianViaLibrary(), GUARDIAN, "pending guardian can equal current guardian");
        assertEq(
            harness.getPendingGuardianUpdateTimestampViaLibrary(),
            block.timestamp + ADMIN_OPERATION_TIMELOCK,
            "timelock should still be set for same-address proposal"
        );
    }
}
