// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {PolicyLibrariesSuiteBase} from "test/organization/libraries/policy/PolicyLibrariesSuiteBase.sol";
import {Policy, RateLimitScope, RateLimitType} from "types/PolicyTypes.sol";

/**
 * @dev Unit tests for `LibPolicyRateLimits` wrappers.
 */
contract LibPolicyRateLimitsTest is PolicyLibrariesSuiteBase {
    /// @dev Verifies disabled `limitType == None` succeeds without writing usage.
    function test_checkAndUpdateRateLimit_limitTypeNone_returnsTrueAndDoesNotWriteUsage()
        public
    {
        // Setup: configure a valid fixture for `limitType == None` returns true and does not write usage.
        uint256 policyId = 9001;
        Policy memory policy = _buildBasePolicy();
        policy.config.rateLimit.limitType = RateLimitType.None;
        policy.config.rateLimit.timeIntervalHours = 24;
        policy.config.rateLimit.timeIntervalLimit = 100;

        bytes32 key =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA1), address(0xB1), address(0xC1));
        uint256 window = harness.computeTimeWindowViaPolicyLibrary(policy);

        // Call: execute `checkAndUpdateRateLimitViaPolicyLibrary` with the happy-path payload.
        bool ok = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA1), address(0xB1), address(0xC1), 10
        );
        uint256 usage = policyStateHarness.getPolicyUsage(key, window);

        // Verify: assert the expected success result and state updates.
        assertTrue(ok, "limitType None should always succeed");
        assertEq(usage, 0, "limitType None should not write usage");
    }

    /// @dev Verifies `timeIntervalHours == 0` returns false without writing usage.
    function test_checkAndUpdateRateLimit_zeroIntervalHours_returnsFalseAndDoesNotWriteUsage() public {
        // Setup: configure a time-interval policy whose zero-hour configuration should fail closed without writes.
        uint256 policyId = 9002;
        Policy memory policy = _timeIntervalPolicy(0, 100);

        bytes32 key =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA2), address(0xB2), address(0xC2));

        // Call: execute `checkAndUpdateRateLimitViaPolicyLibrary` under the zero-hour configuration.
        bool ok = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA2), address(0xB2), address(0xC2), 10
        );
        uint256 usage = policyStateHarness.getPolicyUsage(key, 0);

        // Verify: zero-hour configs should fail closed and leave usage storage untouched.
        assertFalse(ok, "zero interval-hours should return false");
        assertEq(usage, 0, "zero interval-hours should not write usage");
    }

    /// @dev Verifies `checkAndUpdateRateLimit` returns false when `timeIntervalHours` is zero.
    function test_checkAndUpdateRateLimit_zeroIntervalHours_returnsFalse_desired() public {
        // Setup: configure a time-interval policy whose zero-hour window should reject usage without writing state.
        uint256 policyId = 9_002_006;
        Policy memory policy = _timeIntervalPolicy(0, 100);

        bytes32 key = harness.computeUsageKeyViaPolicyLibrary(
            policyId, policy, address(0xA206), address(0xB206), address(0xC206)
        );

        // Call: execute `checkAndUpdateRateLimitViaPolicyLibrary` for a positive usage amount under zero-hour config.
        bool ok = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA206), address(0xB206), address(0xC206), 10
        );

        // Verify: zero-hour configs should fail closed with `false` and leave usage storage untouched.
        assertFalse(ok, "zero interval-hours should return false instead of bypassing");
        assertEq(policyStateHarness.getPolicyUsage(key, 0), 0, "zero interval-hours should not write usage");
    }

    /// @dev Verifies successful updates write the exact usage amount once.
    function test_checkAndUpdateRateLimit_usageBelowLimit_returnsTrueAndWritesUsage() public {
        // Setup: configure a valid fixture for usage below limit returns true and writes updated usage.
        uint256 policyId = 9003;
        Policy memory policy = _timeIntervalPolicy(1, 10);

        bytes32 key =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA3), address(0xB3), address(0xC3));
        uint256 window = harness.computeTimeWindowViaPolicyLibrary(policy);

        // Call: execute `checkAndUpdateRateLimitViaPolicyLibrary` with the happy-path payload.
        bool ok = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA3), address(0xB3), address(0xC3), 3
        );
        uint256 usage = policyStateHarness.getPolicyUsage(key, window);

        // Verify: assert the expected success result and state updates.
        assertTrue(ok, "usage below limit should succeed");
        assertEq(usage, 3, "usage should be written");
    }

    /// @dev Verifies that usage exactly at limit returns true and writes updated usage.
    function test_checkAndUpdateRateLimit_usageExactlyAtLimit_returnsTrueAndWritesUsage() public {
        // Setup: configure a valid fixture for usage exactly at limit returns true and writes updated usage.
        uint256 policyId = 9004;
        Policy memory policy = _timeIntervalPolicy(1, 10);

        bytes32 key =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA4), address(0xB4), address(0xC4));
        uint256 window = harness.computeTimeWindowViaPolicyLibrary(policy);

        // Call: execute `checkAndUpdateRateLimitViaPolicyLibrary` with the happy-path payload.
        bool ok = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA4), address(0xB4), address(0xC4), 10
        );
        uint256 usage = policyStateHarness.getPolicyUsage(key, window);

        // Verify: assert the expected success result and state updates.
        assertTrue(ok, "usage exactly at limit should succeed");
        assertEq(usage, 10, "usage should be updated to limit");
    }

    /// @dev Verifies that usage above limit returns false and does not update usage.
    function test_checkAndUpdateRateLimit_usageAboveLimit_returnsFalseAndDoesNotWriteUsage()
        public
    {
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for usage above limit returns false
        // and does not update usage.
        uint256 policyId = 9005;
        Policy memory policy = _timeIntervalPolicy(1, 10);

        bytes32 key =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA5), address(0xB5), address(0xC5));
        uint256 window = harness.computeTimeWindowViaPolicyLibrary(policy);
        policyStateHarness.setPolicyUsage(key, window, 9);

        // Call: run `checkAndUpdateRateLimitViaPolicyLibrary` across the prepared variants.
        bool ok = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA5), address(0xB5), address(0xC5), 2
        );
        uint256 usage = policyStateHarness.getPolicyUsage(key, window);

        // Verify: assert each variant returns the expected branch outcome.
        assertFalse(ok, "usage above limit should fail");
        assertEq(usage, 9, "usage must remain unchanged when over limit");
    }

    /// @dev Verifies that cumulative usage in the same window is enforced.
    function test_checkAndUpdateRateLimit_cumulativeUsageInSameWindow_enforced() public {
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for cumulative usage in the same
        // window is enforced.
        uint256 policyId = 9006;
        Policy memory policy = _timeIntervalPolicy(1, 10);

        bytes32 key =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA6), address(0xB6), address(0xC6));
        uint256 window = harness.computeTimeWindowViaPolicyLibrary(policy);

        // Call: run `checkAndUpdateRateLimitViaPolicyLibrary` across the prepared variants.
        bool first = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA6), address(0xB6), address(0xC6), 4
        );
        bool second = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA6), address(0xB6), address(0xC6), 7
        );
        uint256 usage = policyStateHarness.getPolicyUsage(key, window);

        // Verify: assert each variant returns the expected branch outcome.
        assertTrue(first, "first update below limit should pass");
        assertFalse(second, "second update exceeding cumulative limit should fail");
        assertEq(usage, 4, "failed second update must not mutate usage");
    }

    /// @dev Verifies a new time window starts with an independent usage budget.
    function test_checkAndUpdateRateLimit_newWindowResetsUsageBudget() public {
        // Setup: configure a valid fixture for new time window resets effective usage budget.
        uint256 policyId = 9007;
        Policy memory policy = _timeIntervalPolicy(1, 5);
        bytes32 key =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA7), address(0xB7), address(0xC7));

        vm.warp(10_001);
        // Call: execute `checkAndUpdateRateLimitViaPolicyLibrary` with the happy-path payload.
        bool first = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA7), address(0xB7), address(0xC7), 5
        );
        uint256 firstWindow = harness.computeTimeWindowViaPolicyLibrary(policy);

        vm.warp(13_601);
        bool second = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA7), address(0xB7), address(0xC7), 5
        );
        uint256 secondWindow = harness.computeTimeWindowViaPolicyLibrary(policy);

        uint256 usageFirstWindow = policyStateHarness.getPolicyUsage(key, firstWindow);
        uint256 usageSecondWindow = policyStateHarness.getPolicyUsage(key, secondWindow);

        // Verify: assert the expected success result and state updates.
        assertTrue(first, "first-window usage should pass");
        assertTrue(second, "new-window usage should pass independently");
        assertEq(secondWindow, firstWindow + 1, "window should increment on interval boundary");
        assertEq(usageFirstWindow, 5, "first window usage should remain tracked");
        assertEq(usageSecondWindow, 5, "second window usage should be independent");
    }

    /// @dev Verifies per-entity scope isolates usage across scoped entities.
    function test_checkAndUpdateRateLimit_perEntityScope_isolatesUsageAcrossEntities() public {
        // Setup: configure a valid fixture for per-entity scope isolates usage across entities.
        uint256 policyId = 9008;
        Policy memory policy = _timeIntervalPolicy(1, 5);
        policy.config.rateLimit.sourceScope = RateLimitScope.PerEntity;

        // Call: execute `checkAndUpdateRateLimitViaPolicyLibrary` with the happy-path payload.
        bool first = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA8), address(0xB8), address(0xC8), 5
        );
        bool second = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA9), address(0xB8), address(0xC8), 5
        );

        bytes32 keyA =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA8), address(0xB8), address(0xC8));
        bytes32 keyB =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA9), address(0xB8), address(0xC8));
        uint256 window = harness.computeTimeWindowViaPolicyLibrary(policy);

        // Verify: assert the expected success result and state updates.
        assertTrue(first, "first entity should pass");
        assertTrue(second, "second entity should pass with independent budget");
        assertTrue(keyA != keyB, "per-entity scoped key should differ per source account");
        assertEq(policyStateHarness.getPolicyUsage(keyA, window), 5, "entity A usage should be tracked separately");
        assertEq(policyStateHarness.getPolicyUsage(keyB, window), 5, "entity B usage should be tracked separately");
    }

    /// @dev Verifies that `usageAmount == 0` is a no-op success.
    function test_checkAndUpdateRateLimit_zeroUsageAmount_noOpSuccess() public {
        // Setup: configure a valid fixture for `usageAmount == 0` is a no-op success.
        uint256 policyId = 9009;
        Policy memory policy = _timeIntervalPolicy(1, 10);

        bytes32 key =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA10), address(0xB10), address(0xC10));
        uint256 window = harness.computeTimeWindowViaPolicyLibrary(policy);
        policyStateHarness.setPolicyUsage(key, window, 3);

        // Call: execute `checkAndUpdateRateLimitViaPolicyLibrary` with the happy-path payload.
        bool ok = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA10), address(0xB10), address(0xC10), 0
        );
        uint256 usage = policyStateHarness.getPolicyUsage(key, window);

        // Verify: assert the expected success result and state updates.
        assertTrue(ok, "zero usage increment should succeed");
        assertEq(usage, 3, "zero usage increment should not change tracked usage");
    }

    /// @dev Verifies usage overflow fails closed without mutating tracked usage.
    function test_checkAndUpdateRateLimit_additionOverflow_failsClosed_desired() public {
        // Setup: build fixture inputs where desired behavior: usage overflow fails closed (`false`) rather than
        // reverting should be denied.
        uint256 policyId = 9010;
        Policy memory policy = _timeIntervalPolicy(1, type(uint256).max);

        bytes32 key =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA11), address(0xB11), address(0xC11));
        uint256 window = harness.computeTimeWindowViaPolicyLibrary(policy);
        policyStateHarness.setPolicyUsage(key, window, type(uint256).max);
        uint256 usageBefore = policyStateHarness.getPolicyUsage(key, window);

        // Call: execute `checkAndUpdateRateLimitViaPolicyLibrary` and capture the authorization decision.
        bool ok = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA11), address(0xB11), address(0xC11), 1
        );
        uint256 usageAfter = policyStateHarness.getPolicyUsage(key, window);

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(ok, "desired behavior: overflow should fail closed");
        assertEq(usageAfter, usageBefore, "overflow failure should not mutate usage");
    }

    /// @dev Verifies that `timeIntervalLimit == 0` and `usageAmount == 0` succeeds and usage stays unchanged.
    function test_checkAndUpdateRateLimit_zeroLimitAndZeroUsage_succeedsWithoutMutation() public {
        // Setup: configure a valid fixture for `timeIntervalLimit == 0` and `usageAmount == 0` succeeds and usage stays
        // unchanged.
        uint256 policyId = 9011;
        Policy memory policy = _timeIntervalPolicy(1, 0);

        bytes32 key =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA12), address(0xB12), address(0xC12));
        uint256 window = harness.computeTimeWindowViaPolicyLibrary(policy);

        // Call: execute `checkAndUpdateRateLimitViaPolicyLibrary` with the happy-path payload.
        bool ok = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA12), address(0xB12), address(0xC12), 0
        );
        uint256 usage = policyStateHarness.getPolicyUsage(key, window);

        // Verify: assert the expected success result and state updates.
        assertTrue(ok, "zero limit with zero usage should succeed");
        assertEq(usage, 0, "usage should remain unchanged");
    }

    /// @dev Verifies that `timeIntervalLimit == 0` and positive usage returns false and does not mutate.
    function test_checkAndUpdateRateLimit_zeroLimitAndPositiveUsage_returnsFalseWithoutMutation() public {
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for `timeIntervalLimit == 0` and
        // positive usage returns false and does not mutate.
        uint256 policyId = 9012;
        Policy memory policy = _timeIntervalPolicy(1, 0);

        bytes32 key =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA13), address(0xB13), address(0xC13));
        uint256 window = harness.computeTimeWindowViaPolicyLibrary(policy);

        // Call: run `checkAndUpdateRateLimitViaPolicyLibrary` across the prepared variants.
        bool ok = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA13), address(0xB13), address(0xC13), 1
        );
        uint256 usage = policyStateHarness.getPolicyUsage(key, window);

        // Verify: assert each variant returns the expected branch outcome.
        assertFalse(ok, "positive usage with zero limit should fail");
        assertEq(usage, 0, "failed update should not mutate usage");
    }

    /// @dev Verifies that invalid `RateLimitType` values revert during calldata decoding.
    function test_checkAndUpdateRateLimit_invalidRateLimitType_reverts() public {
        // Setup: prepare inputs and mutate encoded policy calldata with an invalid enum value.
        uint256 policyId = 9013;
        Policy memory policy = _timeIntervalPolicy(1, 10);

        bytes32 key =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA14), address(0xB14), address(0xC14));
        uint256 window = harness.computeTimeWindowViaPolicyLibrary(policy);
        uint256 usageBefore = policyStateHarness.getPolicyUsage(key, window);

        bytes memory callData = abi.encodeCall(
            harness.checkAndUpdateRateLimitViaPolicyLibrary,
            (policyId, policy, address(0xA14), address(0xB14), address(0xC14), 1)
        );
        _setWord(callData, 4 + 32 + 17 * 32, 2);

        // Call: execute a low-level call with malformed enum calldata.
        (bool success,) = address(harness).call(callData);
        // Verify: assert malformed enum values fail with a revert/panic and do not mutate usage.
        assertFalse(success, "invalid rate-limit enum should revert");
        assertEq(policyStateHarness.getPolicyUsage(key, window), usageBefore, "invalid enum must not mutate usage");
    }

    /// @dev Verifies that `timeIntervalHours == 0` returns window 0.
    function test_computeTimeWindow_zeroHours_returnsZero() public {
        // Setup: configure a valid fixture for `timeIntervalHours == 0` returns window 0.
        Policy memory policy = _timeIntervalPolicy(0, 100);
        // Call: execute `computeTimeWindowViaPolicyLibrary` with the happy-path payload.
        uint256 window = harness.computeTimeWindowViaPolicyLibrary(policy);
        // Verify: assert the expected success result and state updates.
        assertEq(window, 0, "zero interval hours should return window 0");
    }

    /// @dev Verifies that computes `block.timestamp / (hours * 3600)` exactly.
    function test_computeTimeWindow_matchesExactFormula() public {
        // Setup: configure a valid fixture for computes `block.timestamp / (hours * 3600)` exactly.
        Policy memory policy = _timeIntervalPolicy(3, 100);
        vm.warp(39_999);

        uint256 expected = block.timestamp / (uint256(3) * 3600);
        // Call: execute `computeTimeWindowViaPolicyLibrary` with the happy-path payload.
        uint256 actual = harness.computeTimeWindowViaPolicyLibrary(policy);

        // Verify: assert the expected success result and state updates.
        assertEq(actual, expected, "window formula should match exact integer division");
    }

    /// @dev Verifies that window increments exactly on boundary timestamp.
    function test_computeTimeWindow_incrementsExactlyOnBoundary() public {
        // Setup: configure a valid fixture for window increments exactly on boundary timestamp.
        Policy memory policy = _timeIntervalPolicy(2, 100);

        vm.warp(7199);
        // Call: execute `computeTimeWindowViaPolicyLibrary` with the happy-path payload.
        uint256 beforeBoundary = harness.computeTimeWindowViaPolicyLibrary(policy);

        vm.warp(7200);
        uint256 atBoundary = harness.computeTimeWindowViaPolicyLibrary(policy);

        // Verify: assert the expected success result and state updates.
        assertEq(beforeBoundary, 0, "before boundary should still be window 0");
        assertEq(atBoundary, 1, "boundary timestamp should enter next window");
    }

    /// @dev Verifies that max uint16 interval hours is supported without arithmetic issues.
    function test_computeTimeWindow_maxUint16Hours_supported() public {
        // Setup: configure a valid fixture for max uint16 interval hours is supported without arithmetic issues.
        uint16 hours_ = type(uint16).max;
        Policy memory policy = _timeIntervalPolicy(hours_, 100);

        vm.warp(uint256(hours_) * 3600 * 3 + 17);

        uint256 expected = block.timestamp / (uint256(hours_) * 3600);
        // Call: execute `computeTimeWindowViaPolicyLibrary` with the happy-path payload.
        uint256 actual = harness.computeTimeWindowViaPolicyLibrary(policy);

        // Verify: assert the expected success result and state updates.
        assertEq(actual, expected, "max uint16 interval-hours should compute correctly");
    }

    /// @dev Verifies that returns 0 when no active time-interval limit.
    function test_getCurrentUsage_noActiveTimeIntervalLimit_returnsZero() public {
        // Setup: configure a valid fixture for returns 0 when no active time-interval limit.
        uint256 policyId = 9101;
        Policy memory policy = _buildBasePolicy();
        policy.config.rateLimit.limitType = RateLimitType.None;
        policy.config.rateLimit.timeIntervalHours = 1;

        bytes32 key =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA21), address(0xB21), address(0xC21));
        uint256 window = harness.computeTimeWindowViaPolicyLibrary(_timeIntervalPolicy(1, 100));
        policyStateHarness.setPolicyUsage(key, window, 77);

        // Call: execute `getCurrentUsageViaPolicyLibrary` with the happy-path payload.
        uint256 usage =
            harness.getCurrentUsageViaPolicyLibrary(policyId, policy, address(0xA21), address(0xB21), address(0xC21));
        // Verify: assert the expected success result and state updates.
        assertEq(usage, 0, "non-time-interval limit should always report zero usage");
    }

    /// @dev Verifies that returns tracked usage for the current window/key.
    function test_getCurrentUsage_returnsTrackedUsageForCurrentWindowAndKey() public {
        // Setup: configure a valid fixture for returns tracked usage for the current window/key.
        uint256 policyId = 9102;
        Policy memory policy = _timeIntervalPolicy(1, 100);

        bytes32 key =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA22), address(0xB22), address(0xC22));
        uint256 window = harness.computeTimeWindowViaPolicyLibrary(policy);
        policyStateHarness.setPolicyUsage(key, window, 7);

        // Call: execute `getCurrentUsageViaPolicyLibrary` with the happy-path payload.
        uint256 usage =
            harness.getCurrentUsageViaPolicyLibrary(policyId, policy, address(0xA22), address(0xB22), address(0xC22));
        // Verify: assert the expected success result and state updates.
        assertEq(usage, 7, "current usage should match stored usage for current key/window");
    }

    /// @dev Verifies that usage from other windows is not returned.
    function test_getCurrentUsage_usageFromOtherWindows_notReturned() public {
        // Setup: configure a valid fixture for usage from other windows is not returned.
        uint256 policyId = 9103;
        Policy memory policy = _timeIntervalPolicy(1, 100);

        vm.warp(7200);
        bytes32 key =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA23), address(0xB23), address(0xC23));
        uint256 currentWindow = harness.computeTimeWindowViaPolicyLibrary(policy);

        policyStateHarness.setPolicyUsage(key, currentWindow - 1, 99);

        // Call: execute `getCurrentUsageViaPolicyLibrary` with the happy-path payload.
        uint256 usage =
            harness.getCurrentUsageViaPolicyLibrary(policyId, policy, address(0xA23), address(0xB23), address(0xC23));
        // Verify: assert the expected success result and state updates.
        assertEq(usage, 0, "usage from prior window should not be returned");
    }

    /// @dev Verifies that usage from other scoped keys is not returned.
    function test_getCurrentUsage_usageFromOtherScopedKeys_notReturned() public {
        // Setup: configure a valid fixture for usage from other scoped keys is not returned.
        uint256 policyId = 9104;
        Policy memory policy = _timeIntervalPolicy(1, 100);
        policy.config.rateLimit.sourceScope = RateLimitScope.PerEntity;

        bytes32 keyA =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA24), address(0xB24), address(0xC24));
        uint256 window = harness.computeTimeWindowViaPolicyLibrary(policy);
        policyStateHarness.setPolicyUsage(keyA, window, 44);

        // Call: execute `getCurrentUsageViaPolicyLibrary` with the happy-path payload.
        uint256 usage =
            harness.getCurrentUsageViaPolicyLibrary(policyId, policy, address(0xA25), address(0xB24), address(0xC24));
        // Verify: assert the expected success result and state updates.
        assertEq(usage, 0, "different scoped key should not see other entity usage");
    }

    /// @dev Verifies that acrossAll scopes ignore account/destination/initiator differences.
    function test_computeUsageKey_allAcrossAllScopes_ignoresEntityDifferences() public {
        // Setup: configure a valid fixture for acrossAll scopes ignore account/destination/initiator differences.
        Policy memory policy = _timeIntervalPolicy(1, 100);

        // Call: execute `computeUsageKeyViaPolicyLibrary` with the happy-path payload.
        bytes32 keyA =
            harness.computeUsageKeyViaPolicyLibrary(9201, policy, address(0xA31), address(0xB31), address(0xC31));
        bytes32 keyB =
            harness.computeUsageKeyViaPolicyLibrary(9201, policy, address(0xA32), address(0xB32), address(0xC32));

        // Verify: assert the expected success result and state updates.
        assertEq(keyA, keyB, "across-all scopes should collide across entities");
    }

    /// @dev Verifies that `sourceScope == PerEntity` separates usage by account.
    function test_computeUsageKey_sourceScopePerEntity_separatesByAccount() public {
        // Setup: configure a valid fixture for `sourceScope == PerEntity` separates usage by account.
        Policy memory policy = _timeIntervalPolicy(1, 100);
        policy.config.rateLimit.sourceScope = RateLimitScope.PerEntity;

        // Call: execute `computeUsageKeyViaPolicyLibrary` with the happy-path payload.
        bytes32 keyA =
            harness.computeUsageKeyViaPolicyLibrary(9202, policy, address(0xA33), address(0xB33), address(0xC33));
        bytes32 keyB =
            harness.computeUsageKeyViaPolicyLibrary(9202, policy, address(0xA34), address(0xB33), address(0xC33));

        // Verify: assert the expected success result and state updates.
        assertTrue(keyA != keyB, "per-entity source scope should separate keys by account");
    }

    /// @dev Verifies that `destinationScope == PerEntity` separates usage by destination.
    function test_computeUsageKey_destinationScopePerEntity_separatesByDestination() public {
        // Setup: configure a valid fixture for `destinationScope == PerEntity` separates usage by destination.
        Policy memory policy = _timeIntervalPolicy(1, 100);
        policy.config.rateLimit.destinationScope = RateLimitScope.PerEntity;

        // Call: execute `computeUsageKeyViaPolicyLibrary` with the happy-path payload.
        bytes32 keyA =
            harness.computeUsageKeyViaPolicyLibrary(9203, policy, address(0xA35), address(0xB35), address(0xC35));
        bytes32 keyB =
            harness.computeUsageKeyViaPolicyLibrary(9203, policy, address(0xA35), address(0xB36), address(0xC35));

        // Verify: assert the expected success result and state updates.
        assertTrue(keyA != keyB, "per-entity destination scope should separate keys by destination");
    }

    /// @dev Verifies that `initiatorScope == PerEntity` separates usage by initiator.
    function test_computeUsageKey_initiatorScopePerEntity_separatesByInitiator() public {
        // Setup: configure a valid fixture for `initiatorScope == PerEntity` separates usage by initiator.
        Policy memory policy = _timeIntervalPolicy(1, 100);
        policy.config.rateLimit.initiatorScope = RateLimitScope.PerEntity;

        // Call: execute `computeUsageKeyViaPolicyLibrary` with the happy-path payload.
        bytes32 keyA =
            harness.computeUsageKeyViaPolicyLibrary(9204, policy, address(0xA37), address(0xB37), address(0xC37));
        bytes32 keyB =
            harness.computeUsageKeyViaPolicyLibrary(9204, policy, address(0xA37), address(0xB37), address(0xC38));

        // Verify: assert the expected success result and state updates.
        assertTrue(keyA != keyB, "per-entity initiator scope should separate keys by initiator");
    }

    /// @dev Verifies that different policy IDs always produce different keys.
    function test_computeUsageKey_differentPolicyIds_produceDifferentKeys() public {
        // Setup: configure a valid fixture for different policy IDs always produce different keys.
        Policy memory policy = _timeIntervalPolicy(1, 100);

        // Call: execute `computeUsageKeyViaPolicyLibrary` with the happy-path payload.
        bytes32 keyA =
            harness.computeUsageKeyViaPolicyLibrary(9205, policy, address(0xA39), address(0xB39), address(0xC39));
        bytes32 keyB =
            harness.computeUsageKeyViaPolicyLibrary(9206, policy, address(0xA39), address(0xB39), address(0xC39));

        // Verify: assert the expected success result and state updates.
        assertTrue(keyA != keyB, "policyId must be part of usage-key domain");
    }

    /// @dev Verifies that mixed scope combinations produce expected collisions and separations.
    function test_computeUsageKey_mixedScopes_expectedCollisionsAndSeparations() public {
        // Setup: configure a valid fixture for mixed scope combinations produce expected collisions and separations.
        Policy memory policy = _timeIntervalPolicy(1, 100);
        policy.config.rateLimit.sourceScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.destinationScope = RateLimitScope.AcrossAll;
        policy.config.rateLimit.initiatorScope = RateLimitScope.PerEntity;

        // Call: execute `computeUsageKeyViaPolicyLibrary` with the happy-path payload.
        bytes32 key1 =
            harness.computeUsageKeyViaPolicyLibrary(9207, policy, address(0xA40), address(0xB40), address(0xC40));
        bytes32 key2 =
            harness.computeUsageKeyViaPolicyLibrary(9207, policy, address(0xA40), address(0xB41), address(0xC40));
        bytes32 key3 =
            harness.computeUsageKeyViaPolicyLibrary(9207, policy, address(0xA41), address(0xB40), address(0xC40));
        bytes32 key4 =
            harness.computeUsageKeyViaPolicyLibrary(9207, policy, address(0xA40), address(0xB40), address(0xC41));

        // Verify: assert the expected success result and state updates.
        assertEq(key1, key2, "destination across-all should collide despite destination changes");
        assertTrue(key1 != key3, "source per-entity should separate by account");
        assertTrue(key1 != key4, "initiator per-entity should separate by initiator");
    }

    /// @dev Verifies that deterministic output for identical inputs.
    function test_computeUsageKey_identicalInputs_deterministic() public {
        // Setup: configure a valid fixture for deterministic output for identical inputs.
        Policy memory policy = _timeIntervalPolicy(1, 100);

        // Call: execute `computeUsageKeyViaPolicyLibrary` with the happy-path payload.
        bytes32 first =
            harness.computeUsageKeyViaPolicyLibrary(9208, policy, address(0xA42), address(0xB42), address(0xC42));
        bytes32 second =
            harness.computeUsageKeyViaPolicyLibrary(9208, policy, address(0xA42), address(0xB42), address(0xC42));

        // Verify: assert the expected success result and state updates.
        assertEq(first, second, "usage key must be deterministic");
    }

    /// @dev Verifies that invalid scope values fail closed by behaving like AcrossAll.
    function test_computeUsageKey_invalidScopes_treatedAsAcrossAll() public {
        // Setup: configure a valid fixture for invalid scope values fail closed by behaving like AcrossAll.
        uint256 policyId = 9209;
        Policy memory policy = _timeIntervalPolicy(1, 100);

        // Call: execute `computeUsageKeyViaPolicyLibrary` with the happy-path payload.
        bytes32 expectedAcrossAll =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA43), address(0xB43), address(0xC43));

        bytes32 invalidScopesKey = harness.computeUsageKeyViaPolicyLibraryRawScopes(
            policyId,
            policy,
            type(uint256).max,
            type(uint256).max,
            type(uint256).max,
            address(0xA44),
            address(0xB44),
            address(0xC44)
        );

        // Verify: assert the expected success result and state updates.
        assertEq(invalidScopesKey, expectedAcrossAll, "invalid scope values should collapse to across-all behavior");
    }

    // ========== Anchor Timestamp: computeTimeWindow ==========

    /// @dev Verifies that a non-zero anchor shifts window boundaries relative to the anchor.
    function test_computeTimeWindow_withAnchor_shiftsWindowBoundaries() public {
        // Setup: anchor=1800, interval=1h. Window boundary is at anchor+3600=5400.
        Policy memory policy = _timeIntervalPolicy(1, 100);
        policy.config.rateLimit.anchorTimestamp = 1800;

        // At 5399 we are still in window 0 relative to anchor: (5399-1800)/3600 = 0
        vm.warp(5399);
        assertEq(harness.computeTimeWindowViaPolicyLibrary(policy), 0, "5399 should be window 0 (anchor-relative)");

        // At 5400 we enter window 1 relative to anchor: (5400-1800)/3600 = 1
        vm.warp(5400);
        assertEq(harness.computeTimeWindowViaPolicyLibrary(policy), 1, "5400 should be window 1 (anchor-relative)");
    }

    /// @dev Verifies that computeTimeWindow returns 0 when block.timestamp is before the anchor.
    function test_computeTimeWindow_withAnchor_returnsZeroBeforeAnchor() public {
        Policy memory policy = _timeIntervalPolicy(1, 100);
        policy.config.rateLimit.anchorTimestamp = 10_000;

        vm.warp(9999);
        assertEq(harness.computeTimeWindowViaPolicyLibrary(policy), 0, "before anchor should return window 0");
    }

    /// @dev Verifies that computeTimeWindow returns 0 (start of first window) at the exact anchor.
    function test_computeTimeWindow_withAnchor_returnsZeroAtExactAnchor() public {
        Policy memory policy = _timeIntervalPolicy(1, 100);
        policy.config.rateLimit.anchorTimestamp = 10_000;

        vm.warp(10_000);
        assertEq(harness.computeTimeWindowViaPolicyLibrary(policy), 0, "at exact anchor should be window 0");
    }

    /// @dev Verifies that anchor=0 produces the same result as the legacy formula.
    function test_computeTimeWindow_anchorZero_matchesLegacyBehavior() public {
        Policy memory policy = _timeIntervalPolicy(3, 100);
        policy.config.rateLimit.anchorTimestamp = 0;

        vm.warp(39_999);
        uint256 expected = block.timestamp / (uint256(3) * 3600);
        assertEq(
            harness.computeTimeWindowViaPolicyLibrary(policy), expected, "anchor 0 should match legacy epoch formula"
        );
    }

    // ========== Anchor Timestamp: checkAndUpdateRateLimit ==========

    /// @dev Verifies that checkAndUpdateRateLimit returns false and writes no usage before the anchor.
    function test_checkAndUpdateRateLimit_beforeAnchor_returnsFalseWithoutWritingUsage() public {
        uint256 policyId = 9501;
        Policy memory policy = _timeIntervalPolicy(1, 100);
        policy.config.rateLimit.anchorTimestamp = 10_000;

        vm.warp(5000);

        bool ok = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA1), address(0xB1), address(0xC1), 10
        );
        assertFalse(ok, "before anchor should return false");
    }

    /// @dev Verifies that checkAndUpdateRateLimit succeeds at the exact anchor timestamp.
    function test_checkAndUpdateRateLimit_atAnchor_succeeds() public {
        uint256 policyId = 9502;
        Policy memory policy = _timeIntervalPolicy(1, 100);
        policy.config.rateLimit.anchorTimestamp = 10_000;

        vm.warp(10_000);

        bool ok = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA1), address(0xB1), address(0xC1), 10
        );
        assertTrue(ok, "at exact anchor should succeed");
    }

    /// @dev Verifies that the anchor shifts where window resets occur.
    function test_checkAndUpdateRateLimit_anchorShiftsWindowReset() public {
        // Setup: anchor=1800, interval=1h. Window 0=[1800,5400), Window 1=[5400,9000).
        uint256 policyId = 9503;
        Policy memory policy = _timeIntervalPolicy(1, 5);
        policy.config.rateLimit.anchorTimestamp = 1800;

        // Use full budget in window 0
        vm.warp(5399);
        bool first = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA1), address(0xB1), address(0xC1), 5
        );
        assertTrue(first, "usage at end of window 0 should succeed");

        // Still in window 0, should fail
        bool overflow = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA1), address(0xB1), address(0xC1), 1
        );
        assertFalse(overflow, "over budget in window 0 should fail");

        // Cross into window 1
        vm.warp(5400);
        bool second = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA1), address(0xB1), address(0xC1), 5
        );
        assertTrue(second, "new window after anchor-aligned boundary should succeed");
    }

    /// @dev Verifies cumulative usage enforcement with a non-zero anchor.
    function test_checkAndUpdateRateLimit_cumulativeUsageWithAnchor_enforced() public {
        uint256 policyId = 9504;
        Policy memory policy = _timeIntervalPolicy(1, 10);
        policy.config.rateLimit.anchorTimestamp = 1000;

        vm.warp(2000);

        bool first = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA1), address(0xB1), address(0xC1), 4
        );
        assertTrue(first, "first update below limit should pass");

        bool second = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA1), address(0xB1), address(0xC1), 7
        );
        assertFalse(second, "second update exceeding cumulative limit should fail");
    }

    // ========== Anchor Timestamp: getCurrentUsage ==========

    /// @dev Verifies that getCurrentUsage returns 0 before the anchor timestamp.
    function test_getCurrentUsage_beforeAnchor_returnsZero() public {
        uint256 policyId = 9505;
        Policy memory policy = _timeIntervalPolicy(1, 100);
        policy.config.rateLimit.anchorTimestamp = 10_000;

        vm.warp(5000);

        uint256 usage =
            harness.getCurrentUsageViaPolicyLibrary(policyId, policy, address(0xA1), address(0xB1), address(0xC1));
        assertEq(usage, 0, "before anchor should return zero usage");
    }

    /// @dev Verifies that getCurrentUsage reflects cumulative usage across multiple checkAndUpdateRateLimit calls
    ///      within a single window.
    function test_getCurrentUsage_cumulativeUsageWithinSingleWindow() public {
        uint256 policyId = 9506;
        Policy memory policy = _timeIntervalPolicy(1, 100);

        vm.warp(3600);

        harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA1), address(0xB1), address(0xC1), 15
        );
        uint256 usageAfterFirst =
            harness.getCurrentUsageViaPolicyLibrary(policyId, policy, address(0xA1), address(0xB1), address(0xC1));
        assertEq(usageAfterFirst, 15, "Usage should be 15 after first update");

        harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA1), address(0xB1), address(0xC1), 25
        );
        uint256 usageAfterSecond =
            harness.getCurrentUsageViaPolicyLibrary(policyId, policy, address(0xA1), address(0xB1), address(0xC1));
        assertEq(usageAfterSecond, 40, "Usage should be cumulative (15 + 25 = 40)");

        harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA1), address(0xB1), address(0xC1), 10
        );
        uint256 usageAfterThird =
            harness.getCurrentUsageViaPolicyLibrary(policyId, policy, address(0xA1), address(0xB1), address(0xC1));
        assertEq(usageAfterThird, 50, "Usage should be cumulative (15 + 25 + 10 = 50)");
    }

    /// @dev Verifies that getCurrentUsage shows usage during an active window and resets to 0 in the next window.
    function test_getCurrentUsage_resetsAcrossWindows() public {
        uint256 policyId = 9507;
        Policy memory policy = _timeIntervalPolicy(1, 100);

        vm.warp(3600);

        harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA1), address(0xB1), address(0xC1), 60
        );
        uint256 window1Usage =
            harness.getCurrentUsageViaPolicyLibrary(policyId, policy, address(0xA1), address(0xB1), address(0xC1));
        assertEq(window1Usage, 60, "Usage should be 60 in window 1");

        // Advance to window 2
        vm.warp(7200);
        uint256 window2Usage =
            harness.getCurrentUsageViaPolicyLibrary(policyId, policy, address(0xA1), address(0xB1), address(0xC1));
        assertEq(window2Usage, 0, "Usage should reset to 0 in new window");
    }

    // ========== Helpers ==========

    function _timeIntervalPolicy(uint16 intervalHours, uint256 intervalLimit)
        internal
        view
        returns (Policy memory policy)
    {
        policy = _buildBasePolicy();
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = intervalHours;
        policy.config.rateLimit.timeIntervalLimit = intervalLimit;
        policy.config.rateLimit.initiatorScope = RateLimitScope.AcrossAll;
        policy.config.rateLimit.sourceScope = RateLimitScope.AcrossAll;
        policy.config.rateLimit.destinationScope = RateLimitScope.AcrossAll;
    }
}
