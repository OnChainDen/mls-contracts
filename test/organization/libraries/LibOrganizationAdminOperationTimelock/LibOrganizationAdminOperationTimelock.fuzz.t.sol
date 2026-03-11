// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";

import {IOrganizationAdminOperationTimelock} from "interfaces/organization/IOrganizationAdminOperationTimelock.sol";
import {TimelockUtils} from "libraries/TimelockUtils.sol";
import {LibOrganizationAdminOperationTimelock} from "organization/libraries/LibOrganizationAdminOperationTimelock.sol";

/**
 * @dev Library-focused harness exposing `LibOrganizationAdminOperationTimelock` helpers.
 */
contract LibOrganizationAdminOperationTimelockHarness {
    /**
     * @dev Exposes `LibOrganizationAdminOperationTimelock.initializeAdminOperationTimelock`.
     * @param durationSeconds Timelock duration to validate and persist.
     */
    function initializeViaLibrary(uint256 durationSeconds) external {
        LibOrganizationAdminOperationTimelock.initializeAdminOperationTimelock(durationSeconds);
    }

    /**
     * @dev Exposes `LibOrganizationAdminOperationTimelock.getAdminOperationTimelockDurationSeconds`.
     * @return durationSeconds The persisted admin-operation timelock duration.
     */
    function getDurationViaLibrary() external view returns (uint256 durationSeconds) {
        return LibOrganizationAdminOperationTimelock.getAdminOperationTimelockDurationSeconds();
    }

    /**
     * @dev Exposes `LibOrganizationAdminOperationTimelock.validateTimelockExpiredOrRevert`.
     * @param canFinalizeAtTimestamp Timestamp being checked against `block.timestamp`.
     */
    function validateExpiredOrRevertViaLibrary(uint256 canFinalizeAtTimestamp) external view {
        LibOrganizationAdminOperationTimelock.validateTimelockExpiredOrRevert(canFinalizeAtTimestamp);
    }

    /**
     * @dev Exposes `LibOrganizationAdminOperationTimelock.computeCanFinalizeAtTimestamp`.
     * @return canFinalizeAtTimestamp Current `block.timestamp + configuredDuration`.
     */
    function computeCanFinalizeAtTimestampViaLibrary() external view returns (uint256 canFinalizeAtTimestamp) {
        return LibOrganizationAdminOperationTimelock.computeCanFinalizeAtTimestamp();
    }
}

/**
 * @dev Fuzz tests for `LibOrganizationAdminOperationTimelock`.
 */
contract LibOrganizationAdminOperationTimelockFuzzTest is Test {
    /// @dev Library harness under test.
    LibOrganizationAdminOperationTimelockHarness internal harness;

    /**
     * @dev Deploys a fresh library harness before each test.
     */
    function setUp() public {
        harness = new LibOrganizationAdminOperationTimelockHarness();
    }

}
