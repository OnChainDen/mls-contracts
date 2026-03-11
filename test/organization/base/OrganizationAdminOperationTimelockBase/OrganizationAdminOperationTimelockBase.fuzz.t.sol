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

    /// @dev Verifies `adminOperationTimelockDurationSeconds` always reflects the initialized value and stays
    /// unchanged across guardian update and deferred recovery-initialization flows.
    /// @param rawAdminDuration Fuzzed admin-operation timelock seed bounded into the valid range.
    /// @param rawGuardianRecoveryDuration Fuzzed guardian-recovery timelock seed bounded into the valid range.
    /// @param rawTxRecoveryDuration Fuzzed tx-recovery timelock seed bounded into the valid range.
    /// @param guardian Fuzzed initial guardian address.
    /// @param newGuardian Fuzzed pending guardian address for the update flow.
    /// @param guardianRecoveryAddress Fuzzed guardian-recovery address for deferred initialization.
    /// @param txRecoveryAddress Fuzzed tx-recovery address for deferred initialization.
    function testFuzz_FOAOTB_DUR_25_adminOperationTimelockDurationSeconds_remainsStableAcrossGuardianAndRecoveryFlows(
        uint256 rawAdminDuration,
        uint256 rawGuardianRecoveryDuration,
        uint256 rawTxRecoveryDuration,
        address guardian,
        address newGuardian,
        address guardianRecoveryAddress,
        address txRecoveryAddress
    ) public {
        // Setup: bound all durations into the documented range and constrain every actor address to a distinct
        // non-zero value.
        uint256 adminDuration = bound(
            rawAdminDuration, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        );
        uint256 guardianRecoveryDuration = bound(
            rawGuardianRecoveryDuration,
            TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
            TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        );
        uint256 txRecoveryDuration = bound(
            rawTxRecoveryDuration,
            TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
            TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        );
        vm.assume(guardian != address(0));
        vm.assume(newGuardian != address(0));
        vm.assume(guardianRecoveryAddress != address(0));
        vm.assume(txRecoveryAddress != address(0));
        vm.assume(guardian != newGuardian);
        vm.assume(guardian != guardianRecoveryAddress);
        vm.assume(guardian != txRecoveryAddress);
        vm.assume(newGuardian != guardianRecoveryAddress);
        vm.assume(newGuardian != txRecoveryAddress);
        vm.assume(guardianRecoveryAddress != txRecoveryAddress);

        harness.initializeAdminOperationTimelockViaLibrary(adminDuration);
        harness.initializeGuardianViaLibrary(guardian);
        assertEq(
            harness.adminOperationTimelockDurationSeconds(),
            adminDuration,
            "base getter should return the initialized admin timelock"
        );

        // Call: run the normal guardian-update flow, then both deferred recovery-initialization flows.
        uint256 guardianFinalizeAt = block.timestamp + adminDuration;
        harness.initiateGuardianUpdateViaLibrary(newGuardian);
        assertEq(
            harness.adminOperationTimelockDurationSeconds(),
            adminDuration,
            "guardian update initiation should not mutate the base getter"
        );

        vm.warp(guardianFinalizeAt);
        harness.finalizeGuardianUpdateViaLibrary();
        assertEq(
            harness.adminOperationTimelockDurationSeconds(),
            adminDuration,
            "guardian update finalization should not mutate the base getter"
        );

        harness.acceptGuardianViaLibrary();
        assertEq(
            harness.adminOperationTimelockDurationSeconds(),
            adminDuration,
            "guardian acceptance should not mutate the base getter"
        );

        uint256 guardianRecoveryFinalizeAt = block.timestamp + adminDuration;
        harness.initiateInitializeGuardianRecoveryViaLibrary(guardianRecoveryAddress, guardianRecoveryDuration);
        assertEq(
            harness.adminOperationTimelockDurationSeconds(),
            adminDuration,
            "guardian recovery initiation should not mutate the base getter"
        );

        vm.warp(guardianRecoveryFinalizeAt);
        harness.finalizeInitializeGuardianRecoveryViaLibrary();
        assertEq(
            harness.adminOperationTimelockDurationSeconds(),
            adminDuration,
            "guardian recovery finalization should not mutate the base getter"
        );

        uint256 txRecoveryFinalizeAt = block.timestamp + adminDuration;
        harness.initiateInitializeTxRecoveryViaLibrary(txRecoveryAddress, txRecoveryDuration);
        assertEq(
            harness.adminOperationTimelockDurationSeconds(),
            adminDuration,
            "tx recovery initiation should not mutate the base getter"
        );

        vm.warp(txRecoveryFinalizeAt);
        harness.finalizeInitializeTxRecoveryViaLibrary();

        // Verify: the base getter remains pinned to the original initialized value after all unrelated flows finish.
        assertEq(
            harness.adminOperationTimelockDurationSeconds(),
            adminDuration,
            "tx recovery finalization should not mutate the base getter"
        );
    }
}
