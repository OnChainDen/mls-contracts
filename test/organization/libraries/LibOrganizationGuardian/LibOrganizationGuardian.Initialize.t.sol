// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
import {
    LibOrganizationGuardianSuiteBase
} from "test/organization/libraries/LibOrganizationGuardian/LibOrganizationGuardianSuiteBase.sol";

/**
 * @dev Unit tests for `LibOrganizationGuardian.initializeGuardian`.
 */
contract LibOrganizationGuardianInitializeTest is LibOrganizationGuardianSuiteBase {
    /// @dev Verifies valid address sets guardian in storage.
    function test_validAddress_setsGuardianInStorage() public {
        // Setup
        harness.resetGuardianStorage();

        // Call
        harness.initializeGuardianViaLibrary(NEW_GUARDIAN_A);

        // Verify
        assertEq(harness.getGuardianViaLibrary(), NEW_GUARDIAN_A, "guardian should be initialized");
    }

    /// @dev Verifies zero address reverts `InvalidGuardianAddress`.
    function test_zeroAddress_revertsInvalidGuardianAddress() public {
        // Setup
        harness.resetGuardianStorage();

        // Call
        vm.expectRevert(IOrganizationGuardian.InvalidGuardianAddress.selector);
        harness.initializeGuardianViaLibrary(address(0));

        // Verify
        assertEq(harness.getGuardianViaLibrary(), address(0), "guardian should remain unset");
    }

    /// @dev Verifies initialized guardian is readable via `getGuardian`.
    function test_initializedGuardian_readableViaGetGuardian() public {
        // Setup
        harness.resetGuardianStorage();

        // Call
        harness.initializeGuardianViaLibrary(NEW_GUARDIAN_B);
        address currentGuardian = harness.getGuardianViaLibrary();

        // Verify
        assertEq(currentGuardian, NEW_GUARDIAN_B, "getGuardian should return initialized guardian");
    }

    /// @dev Verifies guardian re-initialization is rejected once guardian is already configured.
    function test_guardianAlreadyInitialized_revertsOnReInitialization() public {
        // Setup
        harness.resetGuardianStorage();
        harness.initializeGuardianViaLibrary(NEW_GUARDIAN_A);

        // Call
        vm.expectRevert(IOrganizationGuardian.GuardianAlreadyInitialized.selector);
        harness.initializeGuardianViaLibrary(NEW_GUARDIAN_B);

        // Verify
        assertEq(harness.getGuardianViaLibrary(), NEW_GUARDIAN_A, "guardian should remain initial value");
    }

    /// @dev Verifies initialization only touches guardian and keeps pending state cleared.
    function test_initializationOnlyTouchesGuardian_pendingStateRemainsCleared() public {
        // Setup
        harness.resetGuardianStorage();

        // Call
        harness.initializeGuardianViaLibrary(NEW_GUARDIAN_A);

        // Verify
        assertEq(harness.getGuardianViaLibrary(), NEW_GUARDIAN_A, "guardian should be initialized");
        assertEq(harness.getPendingGuardianViaLibrary(), address(0), "pending guardian should stay cleared");
        assertEq(harness.getPendingGuardianUpdateTimestampViaLibrary(), 0, "pending timestamp should stay cleared");
        assertFalse(
            harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(), "ready-for-acceptance flag should stay cleared"
        );
    }
}
