// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibOrganizationGuardianSuiteBase
} from "test/organization/libraries/LibOrganizationGuardian/LibOrganizationGuardianSuiteBase.sol";

/**
 * @dev Unit tests for `LibOrganizationGuardian` view functions.
 */
contract LibOrganizationGuardianViewsTest is LibOrganizationGuardianSuiteBase {
    /// @dev Verifies `getGuardian` returns current guardian.
    function test_getGuardian_returnsCurrentGuardian() public {
        // Setup
        guardianStateHarness.setGuardian(NEW_GUARDIAN_A);

        // Call
        address currentGuardian = harness.getGuardianViaLibrary();

        // Verify
        assertEq(currentGuardian, NEW_GUARDIAN_A, "getGuardian should return current guardian");
    }

    /// @dev Verifies `getPendingGuardian` returns zero when no pending update exists.
    function test_getPendingGuardian_returnsZeroWhenNoPendingUpdate() public {
        // Setup
        _clearPendingGuardianState();

        // Call
        address pendingGuardian = harness.getPendingGuardianViaLibrary();

        // Verify
        assertEq(pendingGuardian, address(0), "pending guardian should be zero with no pending update");
    }

    /// @dev Verifies `getPendingGuardian` returns correct address during pending update.
    function test_getPendingGuardian_returnsCorrectAddressDuringPendingUpdate() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);

        // Call
        address pendingGuardian = harness.getPendingGuardianViaLibrary();

        // Verify
        assertEq(pendingGuardian, NEW_GUARDIAN_A, "pending guardian should match initiated address");
    }

    /// @dev Verifies `getPendingGuardianUpdateTimestamp` returns zero when no pending update exists.
    function test_getPendingGuardianUpdateTimestamp_returnsZeroWhenNoPendingUpdate() public {
        // Setup
        _clearPendingGuardianState();

        // Call
        uint256 pendingTimestamp = harness.getPendingGuardianUpdateTimestampViaLibrary();

        // Verify
        assertEq(pendingTimestamp, 0, "pending timestamp should be zero with no pending update");
    }

    /// @dev Verifies `getPendingGuardianUpdateTimestamp` returns correct value during pending update.
    function test_getPendingGuardianUpdateTimestamp_returnsCorrectTimestampDuringPendingUpdate() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        uint256 expectedTimestamp = block.timestamp + ADMIN_OPERATION_TIMELOCK;

        // Call
        uint256 pendingTimestamp = harness.getPendingGuardianUpdateTimestampViaLibrary();

        // Verify
        assertEq(pendingTimestamp, expectedTimestamp, "pending timestamp should match computed finalize timestamp");
    }

    /// @dev Verifies `getIsGuardianUpdateReadyForAcceptance` is false when no pending update exists.
    function test_getIsReady_returnsFalseWhenNoPendingUpdate() public {
        // Setup
        _clearPendingGuardianState();

        // Call
        bool isReady = harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary();

        // Verify
        assertFalse(isReady, "ready flag should be false without pending update");
    }

    /// @dev Verifies `getIsGuardianUpdateReadyForAcceptance` is false after initiate (before finalize).
    function test_getIsReady_returnsFalseAfterInitiateBeforeFinalize() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);

        // Call
        bool isReady = harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary();

        // Verify
        assertFalse(isReady, "ready flag should be false after initiate and before finalize");
    }

    /// @dev Verifies `getIsGuardianUpdateReadyForAcceptance` is true after finalize.
    function test_getIsReady_returnsTrueAfterFinalize() public {
        // Setup
        _initiateGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        vm.warp(harness.getPendingGuardianUpdateTimestampViaLibrary());
        harness.finalizeGuardianUpdateViaLibrary();

        // Call
        bool isReady = harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary();

        // Verify
        assertTrue(isReady, "ready flag should be true after finalize");
    }
}
