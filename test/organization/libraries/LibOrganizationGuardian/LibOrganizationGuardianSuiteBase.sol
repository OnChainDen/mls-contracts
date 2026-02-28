// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibOrganizationGuardianHarness
} from "test/organization/libraries/LibOrganizationGuardian/LibOrganizationGuardianHarness.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";
import {OrganizationAdminTestBase} from "test/organization/shared/OrganizationAdminTestBase.sol";
import {OrganizationGuardianStateHarness} from "test/organization/shared/OrganizationGuardianStateHarness.sol";

/**
 * @dev Shared deployment/setup helpers for `LibOrganizationGuardian` suites.
 */
abstract contract LibOrganizationGuardianSuiteBase is OrganizationAdminTestBase {
    /// @dev Timelock used for normal guardian update flow in tests.
    uint256 internal constant ADMIN_OPERATION_TIMELOCK = 2 days;

    /// @dev Timelock used for guardian recovery flow in tests.
    uint256 internal constant GUARDIAN_RECOVERY_TIMELOCK = 2 days;

    /// @dev Deterministic proposed guardian fixtures.
    address internal constant NEW_GUARDIAN_A = address(0x9011);
    address internal constant NEW_GUARDIAN_B = address(0x9012);
    address internal constant NEW_GUARDIAN_C = address(0x9013);

    /// @dev Deterministic guardian-recovery admin fixture.
    address internal constant GUARDIAN_RECOVERY_ADDRESS = address(0x9021);

    /// @dev Concrete harness used by all library-focused section suites.
    LibOrganizationGuardianHarness internal harness;

    /// @dev Typed shared-state surface for guardian storage helpers.
    OrganizationGuardianStateHarness internal guardianStateHarness;

    /**
     * @dev Deploys the library-focused harness for section suites.
     */
    function _deployHarness() internal override returns (OrganizationAdminStateHarness) {
        harness = new LibOrganizationGuardianHarness();
        return OrganizationAdminStateHarness(address(harness));
    }

    /**
     * @dev Seeds baseline timelock configuration and guardian recovery setup.
     */
    function setUp() public virtual override {
        super.setUp();
        guardianStateHarness = OrganizationGuardianStateHarness(address(harness));
        guardianStateHarness.setAdminOperationTimelockDurationSeconds(ADMIN_OPERATION_TIMELOCK);
    }

    /**
     * @dev Clears pending guardian update fields.
     */
    function _clearPendingGuardianState() internal {
        guardianStateHarness.setPendingGuardian(address(0));
        guardianStateHarness.setPendingGuardianUpdateTimestamp(0);
        guardianStateHarness.setIsGuardianUpdateReadyForAcceptance(false);
    }

    /**
     * @dev Creates a pending guardian update via library initiate wrapper.
     */
    function _initiateGuardianUpdateViaLibrary(address newGuardian) internal {
        harness.initiateGuardianUpdateViaLibrary(newGuardian);
    }

    /**
     * @dev Finalizes current pending guardian update after advancing to timelock expiry.
     */
    function _finalizeGuardianUpdateViaLibraryAfterTimelock() internal {
        vm.warp(harness.getPendingGuardianUpdateTimestampViaLibrary());
        harness.finalizeGuardianUpdateViaLibrary();
    }

    /**
     * @dev Configures guardian-recovery flow for integration tests.
     */
    function _initializeGuardianRecoveryConfig() internal {
        harness.initializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);
    }
}
