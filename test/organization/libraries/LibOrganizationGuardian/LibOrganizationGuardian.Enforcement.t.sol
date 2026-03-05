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
    /// @dev Verifies LOG-EOG-1: `enforceOnlyGuardian` passes when caller equals guardian.
    function test_LOG_EOG_1_callerIsGuardian_doesNotRevert() public {
        // Setup
        guardianStateHarness.setGuardian(NEW_GUARDIAN_A);

        // Call
        vm.prank(NEW_GUARDIAN_A);
        harness.enforceOnlyGuardianViaLibrary();

        // Verify
        assertEq(harness.getGuardianViaLibrary(), NEW_GUARDIAN_A, "guardian should remain unchanged");
    }

    /// @dev Verifies LOG-EOG-2: `enforceOnlyGuardian` reverts for non-guardian caller.
    function test_LOG_EOG_2_callerNotGuardian_revertsUnauthorizedGuardian() public {
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

    /// @dev Verifies LOG-EOG-3: `UnauthorizedGuardian` error includes caller and expected guardian.
    function test_LOG_EOG_3_errorIncludesCallerAndExpectedGuardian() public {
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

    /// @dev Verifies LOG-EPG-1: `enforceOnlyPendingGuardian` passes when caller equals pending guardian.
    function test_LOG_EPG_1_callerIsPendingGuardian_doesNotRevert() public {
        // Setup
        guardianStateHarness.setPendingGuardian(NEW_GUARDIAN_A);

        // Call
        vm.prank(NEW_GUARDIAN_A);
        harness.enforceOnlyPendingGuardianViaLibrary();

        // Verify
        assertEq(harness.getPendingGuardianViaLibrary(), NEW_GUARDIAN_A, "pending guardian should remain unchanged");
    }

    /// @dev Verifies LOG-EPG-2: `enforceOnlyPendingGuardian` reverts for non-pending-guardian caller.
    function test_LOG_EPG_2_callerNotPendingGuardian_revertsUnauthorizedGuardianAcceptance() public {
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

    /// @dev Verifies LOG-EPG-3: no pending update causes all callers to revert.
    function test_LOG_EPG_3_noPendingGuardian_anyCallerReverts() public {
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

    /// @dev Verifies LOG-EPG-4: `UnauthorizedGuardianAcceptance` includes caller and expected pending guardian.
    function test_LOG_EPG_4_errorIncludesCallerAndExpectedPendingGuardian() public {
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
