// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {PolicyLibrariesFuzzTestBase} from "test/organization/libraries/policy/PolicyLibrariesFuzzTestBase.sol";
import {Policy, RateLimitScope, RateLimitType} from "types/PolicyTypes.sol";

/**
 * @dev Fuzz tests for `LibPolicyRateLimits`.
 */
contract LibPolicyRateLimitsFuzzTest is PolicyLibrariesFuzzTestBase {
    /// @dev Verifies `LibPolicyRateLimits.checkAndUpdateRateLimit` treats `None` and zero-hour interval modes as
    /// no-op success paths.
    /// @param policyId The base policy identifier used to derive distinct usage domains.
    /// @param account The source account for rate-limit tracking.
    /// @param destination The destination account for rate-limit tracking.
    /// @param initiator The initiator account for rate-limit tracking.
    /// @param usageAmount The attempted usage increment.
    function testFuzz_FLPRL_RATE_82_checkAndUpdateRateLimit_noneAndZeroHourModesAreNoOpSuccess(
        uint256 policyId,
        address account,
        address destination,
        address initiator,
        uint256 usageAmount
    ) public {
        // Setup: configure one `limitType == None` policy and one zero-hour time-interval policy.
        Policy memory nonePolicy = _buildBasePolicy();
        nonePolicy.config.rateLimit.limitType = RateLimitType.None;
        nonePolicy.config.rateLimit.timeIntervalHours = 24;
        nonePolicy.config.rateLimit.timeIntervalLimit = type(uint128).max;

        Policy memory zeroHoursPolicy = _timeIntervalPolicy(0, type(uint128).max);
        uint256 zeroHoursPolicyId = policyId ^ uint256(1);

        // Call: execute both no-op branches against arbitrary usage amounts.
        bool noneAllowed =
            harness.checkAndUpdateRateLimitViaPolicyLibrary(policyId, nonePolicy, account, destination, initiator, usageAmount);
        bool zeroHoursAllowed = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            zeroHoursPolicyId, zeroHoursPolicy, account, destination, initiator, usageAmount
        );

        // Verify: both branches succeed without writing any usage into storage.
        bytes32 noneKey = harness.computeUsageKeyViaPolicyLibrary(policyId, nonePolicy, account, destination, initiator);
        bytes32 zeroHoursKey =
            harness.computeUsageKeyViaPolicyLibrary(zeroHoursPolicyId, zeroHoursPolicy, account, destination, initiator);
        assertTrue(noneAllowed, "limitType None should always succeed");
        assertTrue(zeroHoursAllowed, "zero-hour intervals should always succeed");
        assertEq(policyStateHarness.getPolicyUsage(noneKey, harness.computeTimeWindowViaPolicyLibrary(nonePolicy)), 0);
        assertEq(policyStateHarness.getPolicyUsage(zeroHoursKey, 0), 0);
    }

    /// @dev Verifies `LibPolicyRateLimits.checkAndUpdateRateLimit` increments tracked usage by exactly
    /// `usageAmount` when the increment stays within the limit.
    /// @param policyId The policy identifier used for the tracked usage entry.
    /// @param rawCurrentUsage The seeded usage already stored in the current time window.
    /// @param rawIncrement The additional usage applied by the fuzzed call.
    function testFuzz_FLPRL_RATE_84_checkAndUpdateRateLimit_withinLimitIncrementsExactly(
        uint256 policyId,
        uint96 rawCurrentUsage,
        uint96 rawIncrement
    ) public {
        uint256 currentUsage = rawCurrentUsage;
        uint256 usageAmount = rawIncrement;

        // Setup: seed the current window with existing usage and choose a limit that exactly fits the increment.
        Policy memory policy = _timeIntervalPolicy(1, currentUsage + usageAmount);
        address account = address(0x8401);
        address destination = address(0x8402);
        address initiator = address(0x8403);
        bytes32 usageKey = harness.computeUsageKeyViaPolicyLibrary(policyId, policy, account, destination, initiator);
        uint256 window = harness.computeTimeWindowViaPolicyLibrary(policy);
        policyStateHarness.setPolicyUsage(usageKey, window, currentUsage);

        // Call: apply a within-limit increment to the seeded usage bucket.
        bool allowed =
            harness.checkAndUpdateRateLimitViaPolicyLibrary(policyId, policy, account, destination, initiator, usageAmount);

        // Verify: the call succeeds and stored usage increases by exactly `usageAmount`.
        assertTrue(allowed, "within-limit usage should succeed");
        assertEq(policyStateHarness.getPolicyUsage(usageKey, window), currentUsage + usageAmount);
    }

    /// @dev Verifies `LibPolicyRateLimits.checkAndUpdateRateLimit` rejects over-limit usage without mutating state.
    /// @param policyId The policy identifier used for the tracked usage entry.
    /// @param rawCurrentUsage The seeded usage already stored in the current time window.
    /// @param rawRemaining The remaining budget before reaching the configured limit.
    function testFuzz_FLPRL_RATE_85_checkAndUpdateRateLimit_overLimitDoesNotMutateUsage(
        uint256 policyId,
        uint96 rawCurrentUsage,
        uint96 rawRemaining
    ) public {
        uint256 currentUsage = rawCurrentUsage;
        uint256 remainingBudget = rawRemaining;
        uint256 usageAmount = remainingBudget + 1;

        // Setup: seed usage so the next increment exceeds the configured limit by exactly one unit.
        Policy memory policy = _timeIntervalPolicy(1, currentUsage + remainingBudget);
        address account = address(0x8501);
        address destination = address(0x8502);
        address initiator = address(0x8503);
        bytes32 usageKey = harness.computeUsageKeyViaPolicyLibrary(policyId, policy, account, destination, initiator);
        uint256 window = harness.computeTimeWindowViaPolicyLibrary(policy);
        policyStateHarness.setPolicyUsage(usageKey, window, currentUsage);

        // Call: attempt the over-limit increment.
        bool allowed =
            harness.checkAndUpdateRateLimitViaPolicyLibrary(policyId, policy, account, destination, initiator, usageAmount);

        // Verify: the call fails and leaves the tracked usage unchanged.
        assertFalse(allowed, "over-limit usage should fail");
        assertEq(policyStateHarness.getPolicyUsage(usageKey, window), currentUsage);
    }

    /// @dev Verifies `LibPolicyRateLimits.computeTimeWindow` and `getCurrentUsage` keep usage window-local and reset
    /// visibility when the window changes.
    /// @param policyId The policy identifier used for the tracked usage entry.
    /// @param rawHours The interval length in hours, bounded to a small non-zero range.
    /// @param rawUsage The usage amount consumed in each window.
    function testFuzz_FLPRL_WINDOW_86_usageIsWindowLocalAndResetsAcrossWindows(
        uint256 policyId,
        uint16 rawHours,
        uint96 rawUsage
    ) public {
        uint16 intervalHours = uint16(bound(uint256(rawHours), 1, 48));
        uint256 usageAmount = bound(uint256(rawUsage), 1, type(uint96).max);

        // Setup: configure a rate-limited policy with one reusable usage bucket across time windows.
        Policy memory policy = _timeIntervalPolicy(intervalHours, usageAmount);
        address account = address(0x8601);
        address destination = address(0x8602);
        address initiator = address(0x8603);
        bytes32 usageKey = harness.computeUsageKeyViaPolicyLibrary(policyId, policy, account, destination, initiator);

        vm.warp(10_000);

        // Call: consume the full budget in one window, advance exactly one interval, and consume it again.
        bool firstAllowed =
            harness.checkAndUpdateRateLimitViaPolicyLibrary(policyId, policy, account, destination, initiator, usageAmount);
        uint256 firstWindow = harness.computeTimeWindowViaPolicyLibrary(policy);
        uint256 firstVisibleUsage =
            harness.getCurrentUsageViaPolicyLibrary(policyId, policy, account, destination, initiator);

        vm.warp(10_000 + (uint256(intervalHours) * 3600));
        uint256 secondWindow = harness.computeTimeWindowViaPolicyLibrary(policy);
        uint256 preSecondUsage =
            harness.getCurrentUsageViaPolicyLibrary(policyId, policy, account, destination, initiator);
        bool secondAllowed =
            harness.checkAndUpdateRateLimitViaPolicyLibrary(policyId, policy, account, destination, initiator, usageAmount);
        uint256 secondVisibleUsage =
            harness.getCurrentUsageViaPolicyLibrary(policyId, policy, account, destination, initiator);

        // Verify: usage is visible only inside its current window and resets when the window rolls forward.
        assertTrue(firstAllowed, "first-window usage should succeed");
        assertEq(firstVisibleUsage, usageAmount, "current usage should reflect first-window consumption");
        assertTrue(secondWindow > firstWindow, "time window should advance after the interval elapses");
        assertEq(preSecondUsage, 0, "new windows should start with zero visible usage");
        assertTrue(secondAllowed, "second-window usage should succeed independently");
        assertEq(policyStateHarness.getPolicyUsage(usageKey, firstWindow), usageAmount);
        assertEq(policyStateHarness.getPolicyUsage(usageKey, secondWindow), usageAmount);
        assertEq(secondVisibleUsage, usageAmount, "current usage should reflect second-window consumption");
    }

    /// @dev Verifies `LibPolicyRateLimits.checkAndUpdateRateLimit` fails closed instead of panicking when usage
    /// arithmetic approaches `uint256` overflow.
    /// @param policyId The policy identifier used for the tracked usage entry.
    /// @param deltaRaw The small gap between the seeded usage and `type(uint256).max`.
    function testFuzz_FLPRL_RATE_87_checkAndUpdateRateLimit_nearOverflowFailsClosedWithoutPanic(
        uint256 policyId,
        uint8 deltaRaw
    ) public {
        uint256 delta = bound(uint256(deltaRaw), 0, 3);
        uint256 currentUsage = type(uint256).max - delta;
        uint256 usageAmount = delta + 1;

        // Setup: seed usage near `uint256` overflow with a limit large enough that only the arithmetic guard matters.
        Policy memory policy = _timeIntervalPolicy(1, type(uint256).max);
        address account = address(0x8701);
        address destination = address(0x8702);
        address initiator = address(0x8703);
        bytes32 usageKey = harness.computeUsageKeyViaPolicyLibrary(policyId, policy, account, destination, initiator);
        uint256 window = harness.computeTimeWindowViaPolicyLibrary(policy);
        policyStateHarness.setPolicyUsage(usageKey, window, currentUsage);

        // Call: attempt an increment that would overflow the cumulative usage arithmetic.
        bool allowed =
            harness.checkAndUpdateRateLimitViaPolicyLibrary(policyId, policy, account, destination, initiator, usageAmount);

        // Verify: the helper returns `false` and preserves the original tracked usage instead of panicking.
        assertFalse(allowed, "near-overflow arithmetic should fail closed");
        assertEq(policyStateHarness.getPolicyUsage(usageKey, window), currentUsage);
    }
}
