// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";

import {TimelockUtils} from "libraries/TimelockUtils.sol";

/**
 * @dev TimelockUtilsHarness
 *      Test harness that exposes the internal TimelockUtils.validateTimelockDurationOrRevert
 *      function and the library constants via public wrappers.
 */
contract TimelockUtilsHarness {
    function validateTimelockDurationOrRevert(uint256 timelockDurationSeconds) external pure {
        TimelockUtils.validateTimelockDurationOrRevert(timelockDurationSeconds);
    }

    function minTimelockDuration() external pure returns (uint256) {
        return TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS;
    }

    function maxTimelockDuration() external pure returns (uint256) {
        return TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS;
    }
}

/**
 * @dev TimelockUtilsTest
 *      Tests for TimelockUtils library.
 *      Covers boundary validation for timelock durations:
 *      - MIN_TIMELOCK_DURATION_SECONDS = 2 days (172800 seconds)
 *      - MAX_TIMELOCK_DURATION_SECONDS = 30 days (2592000 seconds)
 *      All tests verify that durations within [MIN, MAX] succeed and durations
 *      outside that range revert with InvalidTimelockDuration.
 * @author Den Technologies Inc
 */
contract TimelockUtilsTest is Test {
    TimelockUtilsHarness public harness;

    /// @dev Cached values from the library constants for readability
    uint256 MIN_DURATION;
    uint256 MAX_DURATION;

    function setUp() public {
        harness = new TimelockUtilsHarness();
        MIN_DURATION = harness.minTimelockDuration();
        MAX_DURATION = harness.maxTimelockDuration();

        // Sanity check: verify constants match expected values
        assertEq(MIN_DURATION, 2 days, "MIN should be 2 days");
        assertEq(MAX_DURATION, 30 days, "MAX should be 30 days");
    }

    /// @dev Test case: Duration exactly at MIN (2 days) should succeed.
    function test_validateTimelockDurationOrRevert_atMin_succeeds() public view {
        // Should not revert
        harness.validateTimelockDurationOrRevert(MIN_DURATION);
    }

    /// @dev Test case: Duration exactly at MAX (30 days) should succeed.
    function test_validateTimelockDurationOrRevert_atMax_succeeds() public view {
        // Should not revert
        harness.validateTimelockDurationOrRevert(MAX_DURATION);
    }

    /// @dev Test case: Duration at MIN - 1 should revert with InvalidTimelockDuration.
    function test_validateTimelockDurationOrRevert_belowMin_reverts() public {
        uint256 belowMin = MIN_DURATION - 1;

        vm.expectRevert(
            abi.encodeWithSelector(TimelockUtils.InvalidTimelockDuration.selector, belowMin, MIN_DURATION, MAX_DURATION)
        );
        harness.validateTimelockDurationOrRevert(belowMin);
    }

    /// @dev Test case: Duration at MAX + 1 should revert with InvalidTimelockDuration.
    function test_validateTimelockDurationOrRevert_aboveMax_reverts() public {
        uint256 aboveMax = MAX_DURATION + 1;

        vm.expectRevert(
            abi.encodeWithSelector(TimelockUtils.InvalidTimelockDuration.selector, aboveMax, MIN_DURATION, MAX_DURATION)
        );
        harness.validateTimelockDurationOrRevert(aboveMax);
    }

    /// @dev Test case: Duration of 0 should revert with InvalidTimelockDuration.
    function test_validateTimelockDurationOrRevert_zero_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(TimelockUtils.InvalidTimelockDuration.selector, 0, MIN_DURATION, MAX_DURATION)
        );
        harness.validateTimelockDurationOrRevert(0);
    }

    /// @dev Test case: Mid-range duration (7 days) should succeed.
    function test_validateTimelockDurationOrRevert_midRange_succeeds() public view {
        harness.validateTimelockDurationOrRevert(7 days);
    }

    /// @dev Test case: Any duration in [MIN, MAX] should succeed.
    function testFuzz_validateTimelockDurationOrRevert_withinRange_succeeds(uint256 duration) public view {
        duration = bound(duration, MIN_DURATION, MAX_DURATION);

        // Should not revert for any value in the valid range
        harness.validateTimelockDurationOrRevert(duration);
    }

    /// @dev Test case: Any duration outside [MIN, MAX] should revert with InvalidTimelockDuration.
    function testFuzz_validateTimelockDurationOrRevert_outsideRange_reverts(uint256 duration) public {
        // Constrain to outside the valid range
        vm.assume(duration < MIN_DURATION || duration > MAX_DURATION);

        vm.expectRevert(
            abi.encodeWithSelector(TimelockUtils.InvalidTimelockDuration.selector, duration, MIN_DURATION, MAX_DURATION)
        );
        harness.validateTimelockDurationOrRevert(duration);
    }
}
