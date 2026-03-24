// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    OrganizationGuardianBaseSuiteBase
} from "test/organization/base/OrganizationGuardianBase/OrganizationGuardianBaseSuiteBase.sol";

/**
 * @dev Unit tests for `OrganizationGuardianBase` view functions.
 */
contract OrganizationGuardianBaseViewsTest is OrganizationGuardianBaseSuiteBase {
    /// @dev Verifies `guardian()` returns current guardian via library getter.
    function test_guardian_returnsCurrentGuardian() public {
        // Setup
        guardianStateHarness.setGuardian(NEW_GUARDIAN_A);

        // Call
        address currentGuardian = harness.guardian();

        // Verify
        assertEq(currentGuardian, NEW_GUARDIAN_A, "guardian() should return current guardian address");
    }

    /// @dev Verifies `pendingGuardian()` returns current pending guardian.
    function test_pendingGuardian_returnsCurrentPendingGuardian() public {
        // Setup
        guardianStateHarness.setPendingGuardian(NEW_GUARDIAN_A);

        // Call
        address pending = harness.pendingGuardian();

        // Verify
        assertEq(pending, NEW_GUARDIAN_A, "pendingGuardian() should return pending guardian address");
    }

    /// @dev Verifies `pendingGuardianUpdateTimestamp()` returns current pending timestamp.
    function test_pendingGuardianUpdateTimestamp_returnsCurrentPendingTimestamp() public {
        // Setup
        uint256 expectedTimestamp = block.timestamp + 4 days;
        guardianStateHarness.setPendingGuardianUpdateTimestamp(expectedTimestamp);

        // Call
        uint256 pendingTimestamp = harness.pendingGuardianUpdateTimestamp();

        // Verify
        assertEq(
            pendingTimestamp, expectedTimestamp, "pendingGuardianUpdateTimestamp() should return pending timestamp"
        );
    }

    /// @dev Verifies `isGuardianUpdateReadyForAcceptance()` returns current ready flag.
    function test_isGuardianUpdateReadyForAcceptance_returnsCurrentReadyFlag() public {
        // Setup
        guardianStateHarness.setIsGuardianUpdateReadyForAcceptance(true);

        // Call
        bool isReady = harness.isGuardianUpdateReadyForAcceptance();

        // Verify
        assertTrue(isReady, "isGuardianUpdateReadyForAcceptance() should return true when set");
    }

    /// @dev Verifies all guardian view functions are callable by any address.
    function test_viewFunctions_callableByAnyone() public {
        // Setup
        guardianStateHarness.setGuardian(NEW_GUARDIAN_A);
        guardianStateHarness.setPendingGuardian(NEW_GUARDIAN_B);
        guardianStateHarness.setPendingGuardianUpdateTimestamp(block.timestamp + 2 days);
        guardianStateHarness.setIsGuardianUpdateReadyForAcceptance(true);

        // Call
        vm.startPrank(NON_GUARDIAN);
        address currentGuardian = harness.guardian();
        address pending = harness.pendingGuardian();
        uint256 pendingTimestamp = harness.pendingGuardianUpdateTimestamp();
        bool isReady = harness.isGuardianUpdateReadyForAcceptance();
        vm.stopPrank();

        // Verify
        assertEq(currentGuardian, NEW_GUARDIAN_A, "guardian view should be publicly callable");
        assertEq(pending, NEW_GUARDIAN_B, "pendingGuardian view should be publicly callable");
        assertEq(pendingTimestamp, block.timestamp + 2 days, "timestamp view should be publicly callable");
        assertTrue(isReady, "ready view should be publicly callable");
    }
}
