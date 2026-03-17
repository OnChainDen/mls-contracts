// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
import {
    LibOrganizationGuardianSuiteBase
} from "test/organization/libraries/LibOrganizationGuardian/LibOrganizationGuardianSuiteBase.sol";

/**
 * @dev Unit tests for guardian enforcement helpers in `LibOrganizationGuardian`.
 */
contract LibOrganizationGuardianEnforcementTest is LibOrganizationGuardianSuiteBase {
    /// @dev Verifies `enforceOnlyGuardian` passes when caller equals guardian.
    function test_callerIsGuardian_doesNotRevert() public {
        // Setup
        guardianStateHarness.setGuardian(NEW_GUARDIAN_A);

        // Call
        vm.prank(NEW_GUARDIAN_A);
        harness.enforceOnlyGuardianViaLibrary();

        // Verify
        assertEq(harness.getGuardianViaLibrary(), NEW_GUARDIAN_A, "guardian should remain unchanged");
    }

    /// @dev Verifies `enforceOnlyGuardian` reverts for non-guardian caller.
    function test_callerNotGuardian_revertsUnauthorizedGuardian() public {
        // Setup
        guardianStateHarness.setGuardian(NEW_GUARDIAN_A);

        // Call
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationGuardian.UnauthorizedGuardian.selector, NEW_GUARDIAN_B, NEW_GUARDIAN_A)
        );
        vm.prank(NEW_GUARDIAN_B);
        harness.enforceOnlyGuardianViaLibrary();

        // Verify
        assertEq(harness.getGuardianViaLibrary(), NEW_GUARDIAN_A, "guardian should remain unchanged");
    }

    /// @dev Verifies `UnauthorizedGuardian` error includes caller and expected guardian.
    function test_errorIncludesCallerAndExpectedGuardian() public {
        // Setup
        guardianStateHarness.setGuardian(NEW_GUARDIAN_A);

        // Call
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationGuardian.UnauthorizedGuardian.selector, NEW_GUARDIAN_B, NEW_GUARDIAN_A)
        );
        vm.prank(NEW_GUARDIAN_B);
        harness.enforceOnlyGuardianViaLibrary();

        // Verify
        assertEq(harness.getGuardianViaLibrary(), NEW_GUARDIAN_A, "guardian should remain unchanged");
    }

    /// @dev Verifies `enforceOnlyPendingGuardian` passes when caller equals pending guardian.
    function test_callerIsPendingGuardian_doesNotRevert() public {
        // Setup
        guardianStateHarness.setPendingGuardian(NEW_GUARDIAN_A);

        // Call
        vm.prank(NEW_GUARDIAN_A);
        harness.enforceOnlyPendingGuardianViaLibrary();

        // Verify
        assertEq(harness.getPendingGuardianViaLibrary(), NEW_GUARDIAN_A, "pending guardian should remain unchanged");
    }

    /// @dev Verifies `enforceOnlyPendingGuardian` reverts for non-pending-guardian caller.
    function test_callerNotPendingGuardian_revertsUnauthorizedGuardianAcceptance() public {
        // Setup
        guardianStateHarness.setPendingGuardian(NEW_GUARDIAN_A);

        // Call
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardian.UnauthorizedGuardianAcceptance.selector, NEW_GUARDIAN_B, NEW_GUARDIAN_A
            )
        );
        vm.prank(NEW_GUARDIAN_B);
        harness.enforceOnlyPendingGuardianViaLibrary();

        // Verify
        assertEq(harness.getPendingGuardianViaLibrary(), NEW_GUARDIAN_A, "pending guardian should remain unchanged");
    }

    /// @dev Verifies no pending update causes all callers to revert.
    function test_noPendingGuardian_anyCallerReverts() public {
        // Setup
        guardianStateHarness.setPendingGuardian(address(0));

        // Call
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardian.UnauthorizedGuardianAcceptance.selector, NEW_GUARDIAN_B, address(0)
            )
        );
        vm.prank(NEW_GUARDIAN_B);
        harness.enforceOnlyPendingGuardianViaLibrary();

        // Verify
        assertEq(harness.getPendingGuardianViaLibrary(), address(0), "pending guardian should remain unset");
    }

    /// @dev Verifies `UnauthorizedGuardianAcceptance` includes caller and expected pending guardian.
    function test_errorIncludesCallerAndExpectedPendingGuardian() public {
        // Setup
        guardianStateHarness.setPendingGuardian(NEW_GUARDIAN_A);

        // Call
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardian.UnauthorizedGuardianAcceptance.selector, NEW_GUARDIAN_B, NEW_GUARDIAN_A
            )
        );
        vm.prank(NEW_GUARDIAN_B);
        harness.enforceOnlyPendingGuardianViaLibrary();

        // Verify
        assertEq(harness.getPendingGuardianViaLibrary(), NEW_GUARDIAN_A, "pending guardian should remain unchanged");
    }
}
