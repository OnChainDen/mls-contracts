// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";

import {TimelockUtils} from "libraries/TimelockUtils.sol";
import {OrganizationAdminOperationTimelockBase} from "organization/base/OrganizationAdminOperationTimelockBase.sol";
import {LibOrganizationAdminOperationTimelock} from "organization/libraries/LibOrganizationAdminOperationTimelock.sol";
import {LibOrganizationGuardian} from "organization/libraries/LibOrganizationGuardian.sol";
import {LibOrganizationGuardianRecovery} from "organization/libraries/LibOrganizationGuardianRecovery.sol";
import {LibOrganizationTxRecovery} from "organization/libraries/LibOrganizationTxRecovery.sol";

/**
 * @dev Harness exposing guardian and recovery flows around `OrganizationAdminOperationTimelockBase`.
 */
contract OrganizationAdminOperationTimelockBaseFlowHarness is OrganizationAdminOperationTimelockBase {
    /**
     * @dev Executes `LibOrganizationAdminOperationTimelock.initializeAdminOperationTimelock`.
     * @param durationSeconds Admin-operation timelock duration to persist.
     */
    function initializeAdminOperationTimelockViaLibrary(uint256 durationSeconds) external {
        LibOrganizationAdminOperationTimelock.initializeAdminOperationTimelock(durationSeconds);
    }

    /**
     * @dev Executes `LibOrganizationGuardian.initializeGuardian`.
     * @param guardian Initial guardian address.
     */
    function initializeGuardianViaLibrary(address guardian) external {
        LibOrganizationGuardian.initializeGuardian(guardian);
    }

    /**
     * @dev Executes `LibOrganizationGuardian.initiateGuardianUpdate`.
     * @param newGuardian Pending guardian to timelock.
     */
    function initiateGuardianUpdateViaLibrary(address newGuardian) external {
        LibOrganizationGuardian.initiateGuardianUpdate(newGuardian);
    }

    /**
     * @dev Executes `LibOrganizationGuardian.finalizeGuardianUpdate`.
     */
    function finalizeGuardianUpdateViaLibrary() external {
        LibOrganizationGuardian.finalizeGuardianUpdate();
    }

    /**
     * @dev Executes `LibOrganizationGuardian.acceptGuardian`.
     */
    function acceptGuardianViaLibrary() external {
        LibOrganizationGuardian.acceptGuardian();
    }

    /**
     * @dev Executes `LibOrganizationGuardianRecovery.initiateInitializeGuardianRecovery`.
     * @param recoveryAddress Guardian recovery address to configure after the admin-operation timelock expires.
     * @param timelockDurationSeconds Recovery timelock duration to configure.
     */
    function initiateInitializeGuardianRecoveryViaLibrary(address recoveryAddress, uint256 timelockDurationSeconds)
        external
    {
        LibOrganizationGuardianRecovery.initiateInitializeGuardianRecovery(recoveryAddress, timelockDurationSeconds);
    }

    /**
     * @dev Executes `LibOrganizationGuardianRecovery.finalizeInitializeGuardianRecovery`.
     */
    function finalizeInitializeGuardianRecoveryViaLibrary() external {
        LibOrganizationGuardianRecovery.finalizeInitializeGuardianRecovery();
    }

    /**
     * @dev Executes `LibOrganizationTxRecovery.initiateInitializeTxRecovery`.
     * @param recoveryAddress Transaction recovery address to configure after the admin-operation timelock expires.
     * @param timelockDurationSeconds Recovery timelock duration to configure.
     */
    function initiateInitializeTxRecoveryViaLibrary(address recoveryAddress, uint256 timelockDurationSeconds) external {
        LibOrganizationTxRecovery.initiateInitializeTxRecovery(recoveryAddress, timelockDurationSeconds);
    }

    /**
     * @dev Executes `LibOrganizationTxRecovery.finalizeInitializeTxRecovery`.
     */
    function finalizeInitializeTxRecoveryViaLibrary() external {
        LibOrganizationTxRecovery.finalizeInitializeTxRecovery();
    }
}

/**
 * @dev Fuzz tests for `OrganizationAdminOperationTimelockBase`.
 */
contract OrganizationAdminOperationTimelockBaseFuzzTest is Test {
    /// @dev Flow harness used to exercise the base getter across unrelated guardian and recovery mutations.
    OrganizationAdminOperationTimelockBaseFlowHarness internal harness;

    /**
     * @dev Deploys a fresh flow harness before each test.
     */
    function setUp() public {
        harness = new OrganizationAdminOperationTimelockBaseFlowHarness();
    }

    /// @dev Verifies `OrganizationAdminOperationTimelockBase.adminOperationTimelockDurationSeconds` returns the value
    /// stored through `LibOrganizationAdminOperationTimelock`.
    function test_adminOperationTimelockDurationSeconds_returnsStoredLibraryValue() public {
        // Setup: persist a valid admin-operation timelock duration through the shared library helper.
        uint256 configuredDuration = 11 days;
        harness.initializeAdminOperationTimelockViaLibrary(configuredDuration);

        // Call: read the external base getter.
        uint256 durationSeconds = harness.adminOperationTimelockDurationSeconds();

        // Verify: the base getter returns the exact persisted timelock duration.
        assertEq(durationSeconds, configuredDuration, "base getter should return the stored timelock duration");
    }

    /// @dev Verifies `OrganizationAdminOperationTimelockBase.adminOperationTimelockDurationSeconds` is permissionless.
    function test_adminOperationTimelockDurationSeconds_callableByAnyAddress() public {
        // Setup: persist a valid admin-operation timelock duration through the shared library helper.
        uint256 configuredDuration = TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS + 1;
        address randomCaller = address(0xA0A7);
        harness.initializeAdminOperationTimelockViaLibrary(configuredDuration);

        // Call: read the external base getter from a non-privileged caller address.
        vm.prank(randomCaller);
        uint256 durationSeconds = harness.adminOperationTimelockDurationSeconds();

        // Verify: arbitrary callers can read the stored timelock duration without authorization checks.
        assertEq(durationSeconds, configuredDuration, "permissionless getter should return the configured duration");
    }
}
