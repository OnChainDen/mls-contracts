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

    /// @dev Verifies valid min/max admin-operation timelock boundaries persist exactly through the library getter.
    /// @param useMaxBoundary Fuzzed switch selecting the min or max valid boundary.
    function testFuzz_FLOAOT_INIT_23_initializeAdminOperationTimelock_validBoundariesPersistExactly(bool useMaxBoundary)
        public
    {
        // Setup: choose one exact boundary from the valid `[2 days, 30 days]` range.
        uint256 durationSeconds =
            useMaxBoundary ? TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS : TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS;

        // Call: initialize the admin-operation timelock with the chosen boundary.
        harness.initializeViaLibrary(durationSeconds);

        // Verify: the persisted getter should return the exact accepted boundary.
        assertEq(harness.getDurationViaLibrary(), durationSeconds, "valid boundary should persist exactly");
    }

    /// @dev Verifies out-of-range admin-operation timelock durations always revert through shared timelock
    /// validation.
    /// @param durationRaw Fuzzed seed used to derive an out-of-range duration.
    /// @param belowMin Fuzzed switch selecting below-min vs above-max invalid durations.
    function testFuzz_FLOAOT_INIT_23_initializeAdminOperationTimelock_outOfRangeAlwaysReverts(
        uint256 durationRaw,
        bool belowMin
    ) public {
        // Setup: derive a duration that is strictly outside the allowed timelock range.
        uint256 durationSeconds = belowMin
            ? bound(durationRaw, 0, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS - 1)
            : bound(
                durationRaw,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS + 1,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS + 365 days
            );

        // Call: initialize the admin-operation timelock with the invalid duration, expecting the shared range error.
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                durationSeconds,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        harness.initializeViaLibrary(durationSeconds);

        // Verify: invalid durations should never be persisted.
        assertEq(harness.getDurationViaLibrary(), 0, "failed initialization should not persist duration");
    }

    /// @dev Verifies `computeCanFinalizeAtTimestamp` always returns `block.timestamp + configuredDuration`.
    /// @param durationRaw Fuzzed duration seed constrained into the valid timelock range.
    function testFuzz_FLOAOT_EXPIRY_24_computeCanFinalizeAtTimestamp_matchesBlockTimestampPlusConfiguredDuration(uint256 durationRaw)
        public
    {
        // Setup: initialize the library with a valid fuzzed duration.
        uint256 durationSeconds = bound(
            durationRaw, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        );
        harness.initializeViaLibrary(durationSeconds);

        // Call: compute the finalization timestamp from the current block timestamp.
        uint256 canFinalizeAtTimestamp = harness.computeCanFinalizeAtTimestampViaLibrary();

        // Verify: the computed timestamp should be the current timestamp plus the configured duration exactly.
        assertEq(
            canFinalizeAtTimestamp,
            block.timestamp + durationSeconds,
            "computed finalization timestamp should add the configured duration"
        );
    }

    /// @dev Verifies timestamps strictly before `canFinalizeAt` revert with `TimelockNotExpired`.
    /// @param durationRaw Fuzzed duration seed constrained into the valid timelock range.
    /// @param earlyOffsetRaw Fuzzed offset seed constrained to keep the warp strictly before finalization.
    function testFuzz_FLOAOT_EXPIRY_24_validateTimelockExpired_beforeCanFinalizeAlwaysReverts(
        uint256 durationRaw,
        uint64 earlyOffsetRaw
    ) public {
        // Setup: initialize a valid duration and derive a timestamp that remains strictly before finalization.
        uint256 durationSeconds = bound(
            durationRaw, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        );
        harness.initializeViaLibrary(durationSeconds);
        uint256 canFinalizeAtTimestamp = harness.computeCanFinalizeAtTimestampViaLibrary();
        uint256 earlyOffset = bound(uint256(earlyOffsetRaw), 1, durationSeconds);
        uint256 currentTimestamp = canFinalizeAtTimestamp - earlyOffset;

        // Call: warp to the pre-finalization timestamp and validate the timelock, expecting `TimelockNotExpired`.
        vm.warp(currentTimestamp);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdminOperationTimelock.TimelockNotExpired.selector,
                canFinalizeAtTimestamp,
                currentTimestamp
            )
        );
        harness.validateExpiredOrRevertViaLibrary(canFinalizeAtTimestamp);

        // Verify: strictly pre-finalization timestamps should always revert.
    }

    /// @dev Verifies timestamps at or after `canFinalizeAt` always pass timelock validation.
    /// @param durationRaw Fuzzed duration seed constrained into the valid timelock range.
    /// @param lateOffsetRaw Fuzzed offset seed applied after the ready timestamp for the non-boundary branch.
    /// @param useExactBoundary Fuzzed switch selecting the exact-boundary vs after-boundary success path.
    function testFuzz_FLOAOT_EXPIRY_24_validateTimelockExpired_atOrAfterCanFinalizeSucceeds(
        uint256 durationRaw,
        uint64 lateOffsetRaw,
        bool useExactBoundary
    ) public {
        // Setup: initialize a valid duration and derive a timestamp at or after finalization readiness.
        uint256 durationSeconds = bound(
            durationRaw, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        );
        harness.initializeViaLibrary(durationSeconds);
        uint256 canFinalizeAtTimestamp = harness.computeCanFinalizeAtTimestampViaLibrary();
        uint256 currentTimestamp =
            useExactBoundary ? canFinalizeAtTimestamp : canFinalizeAtTimestamp + uint256(lateOffsetRaw);

        // Call: warp to the chosen ready timestamp and validate the timelock.
        vm.warp(currentTimestamp);
        harness.validateExpiredOrRevertViaLibrary(canFinalizeAtTimestamp);

        // Verify: boundary and post-boundary timestamps should both succeed.
    }
}
