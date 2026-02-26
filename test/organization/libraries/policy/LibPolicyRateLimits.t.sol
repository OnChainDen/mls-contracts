// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {PolicyLibrariesSuiteBase} from "test/organization/libraries/policy/PolicyLibrariesSuiteBase.sol";
import {Policy, RateLimitScope, RateLimitType} from "types/PolicyTypes.sol";

/**
 * @dev Unit tests for `LibPolicyRateLimits` wrappers.
 */
contract LibPolicyRateLimitsTest is PolicyLibrariesSuiteBase {
    /// @dev [LPRL-UPD-1] `limitType == None` returns true and does not write usage.
    function test_checkAndUpdateRateLimit_limitTypeNone_returnsTrueAndDoesNotWriteUsage() public {
        uint256 policyId = 9001;
        Policy memory policy = _buildBasePolicy();
        policy.config.rateLimit.limitType = RateLimitType.None;
        policy.config.rateLimit.timeIntervalHours = 24;
        policy.config.rateLimit.timeIntervalLimit = 100;

        bytes32 key =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA1), address(0xB1), address(0xC1));
        uint256 window = harness.computeTimeWindowViaPolicyLibrary(policy);

        bool ok = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA1), address(0xB1), address(0xC1), 10
        );
        uint256 usage = policyStateHarness.getPolicyUsage(key, window);

        assertTrue(ok, "limitType None should always succeed");
        assertEq(usage, 0, "limitType None should not write usage");
    }

    /// @dev [LPRL-UPD-2] `timeIntervalHours == 0` returns true and does not write usage.
    function test_checkAndUpdateRateLimit_zeroIntervalHours_returnsTrueAndDoesNotWriteUsage() public {
        uint256 policyId = 9002;
        Policy memory policy = _timeIntervalPolicy(0, 100);

        bytes32 key =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA2), address(0xB2), address(0xC2));

        bool ok = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA2), address(0xB2), address(0xC2), 10
        );
        uint256 usage = policyStateHarness.getPolicyUsage(key, 0);

        assertTrue(ok, "zero interval-hours should bypass rate limit");
        assertEq(usage, 0, "zero interval-hours should not write usage");
    }

    /// @dev [LPRL-UPD-3] Usage below limit returns true and writes updated usage.
    function test_checkAndUpdateRateLimit_usageBelowLimit_returnsTrueAndWritesUsage() public {
        uint256 policyId = 9003;
        Policy memory policy = _timeIntervalPolicy(1, 10);

        bytes32 key =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA3), address(0xB3), address(0xC3));
        uint256 window = harness.computeTimeWindowViaPolicyLibrary(policy);

        bool ok = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA3), address(0xB3), address(0xC3), 3
        );
        uint256 usage = policyStateHarness.getPolicyUsage(key, window);

        assertTrue(ok, "usage below limit should succeed");
        assertEq(usage, 3, "usage should be written");
    }

    /// @dev [LPRL-UPD-4] Usage exactly at limit returns true and writes updated usage.
    function test_checkAndUpdateRateLimit_usageExactlyAtLimit_returnsTrueAndWritesUsage() public {
        uint256 policyId = 9004;
        Policy memory policy = _timeIntervalPolicy(1, 10);

        bytes32 key =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA4), address(0xB4), address(0xC4));
        uint256 window = harness.computeTimeWindowViaPolicyLibrary(policy);

        bool ok = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA4), address(0xB4), address(0xC4), 10
        );
        uint256 usage = policyStateHarness.getPolicyUsage(key, window);

        assertTrue(ok, "usage exactly at limit should succeed");
        assertEq(usage, 10, "usage should be updated to limit");
    }

    /// @dev [LPRL-UPD-5] Usage above limit returns false and does not update usage.
    function test_checkAndUpdateRateLimit_usageAboveLimit_returnsFalseAndDoesNotWriteUsage() public {
        uint256 policyId = 9005;
        Policy memory policy = _timeIntervalPolicy(1, 10);

        bytes32 key =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA5), address(0xB5), address(0xC5));
        uint256 window = harness.computeTimeWindowViaPolicyLibrary(policy);
        policyStateHarness.setPolicyUsage(key, window, 9);

        bool ok = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA5), address(0xB5), address(0xC5), 2
        );
        uint256 usage = policyStateHarness.getPolicyUsage(key, window);

        assertFalse(ok, "usage above limit should fail");
        assertEq(usage, 9, "usage must remain unchanged when over limit");
    }

    /// @dev [LPRL-UPD-6] Cumulative usage in the same window is enforced.
    function test_checkAndUpdateRateLimit_cumulativeUsageInSameWindow_enforced() public {
        uint256 policyId = 9006;
        Policy memory policy = _timeIntervalPolicy(1, 10);

        bytes32 key =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA6), address(0xB6), address(0xC6));
        uint256 window = harness.computeTimeWindowViaPolicyLibrary(policy);

        bool first = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA6), address(0xB6), address(0xC6), 4
        );
        bool second = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA6), address(0xB6), address(0xC6), 7
        );
        uint256 usage = policyStateHarness.getPolicyUsage(key, window);

        assertTrue(first, "first update below limit should pass");
        assertFalse(second, "second update exceeding cumulative limit should fail");
        assertEq(usage, 4, "failed second update must not mutate usage");
    }

    /// @dev [LPRL-UPD-7] New time window resets effective usage budget.
    function test_checkAndUpdateRateLimit_newWindowResetsUsageBudget() public {
        uint256 policyId = 9007;
        Policy memory policy = _timeIntervalPolicy(1, 5);
        bytes32 key =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA7), address(0xB7), address(0xC7));

        vm.warp(10_001);
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

        assertTrue(first, "first-window usage should pass");
        assertTrue(second, "new-window usage should pass independently");
        assertEq(secondWindow, firstWindow + 1, "window should increment on interval boundary");
        assertEq(usageFirstWindow, 5, "first window usage should remain tracked");
        assertEq(usageSecondWindow, 5, "second window usage should be independent");
    }

    /// @dev [LPRL-UPD-8] Per-entity scope isolates usage across entities.
    function test_checkAndUpdateRateLimit_perEntityScope_isolatesUsageAcrossEntities() public {
        uint256 policyId = 9008;
        Policy memory policy = _timeIntervalPolicy(1, 5);
        policy.config.rateLimit.sourceScope = RateLimitScope.PerEntity;

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

        assertTrue(first, "first entity should pass");
        assertTrue(second, "second entity should pass with independent budget");
        assertTrue(keyA != keyB, "per-entity scoped key should differ per source account");
        assertEq(policyStateHarness.getPolicyUsage(keyA, window), 5, "entity A usage should be tracked separately");
        assertEq(policyStateHarness.getPolicyUsage(keyB, window), 5, "entity B usage should be tracked separately");
    }

    /// @dev [LPRL-UPD-9] `usageAmount == 0` is a no-op success.
    function test_checkAndUpdateRateLimit_zeroUsageAmount_noOpSuccess() public {
        uint256 policyId = 9009;
        Policy memory policy = _timeIntervalPolicy(1, 10);

        bytes32 key =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA10), address(0xB10), address(0xC10));
        uint256 window = harness.computeTimeWindowViaPolicyLibrary(policy);
        policyStateHarness.setPolicyUsage(key, window, 3);

        bool ok = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA10), address(0xB10), address(0xC10), 0
        );
        uint256 usage = policyStateHarness.getPolicyUsage(key, window);

        assertTrue(ok, "zero usage increment should succeed");
        assertEq(usage, 3, "zero usage increment should not change tracked usage");
    }

    /// @dev [LPRL-UPD-10] Desired behavior: usage overflow fails closed (`false`) rather than reverting.
    function test_checkAndUpdateRateLimit_additionOverflow_failsClosed_desired() public {
        uint256 policyId = 9010;
        Policy memory policy = _timeIntervalPolicy(1, type(uint256).max);

        bytes32 key =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA11), address(0xB11), address(0xC11));
        uint256 window = harness.computeTimeWindowViaPolicyLibrary(policy);
        policyStateHarness.setPolicyUsage(key, window, type(uint256).max);

        bool ok = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA11), address(0xB11), address(0xC11), 1
        );
        assertFalse(ok, "desired behavior: overflow should fail closed");
    }

    /// @dev [LPRL-UPD-11] `timeIntervalLimit == 0` and `usageAmount == 0` succeeds and usage stays unchanged.
    function test_checkAndUpdateRateLimit_zeroLimitAndZeroUsage_succeedsWithoutMutation() public {
        uint256 policyId = 9011;
        Policy memory policy = _timeIntervalPolicy(1, 0);

        bytes32 key =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA12), address(0xB12), address(0xC12));
        uint256 window = harness.computeTimeWindowViaPolicyLibrary(policy);

        bool ok = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA12), address(0xB12), address(0xC12), 0
        );
        uint256 usage = policyStateHarness.getPolicyUsage(key, window);

        assertTrue(ok, "zero limit with zero usage should succeed");
        assertEq(usage, 0, "usage should remain unchanged");
    }

    /// @dev [LPRL-UPD-12] `timeIntervalLimit == 0` and positive usage returns false and does not mutate.
    function test_checkAndUpdateRateLimit_zeroLimitAndPositiveUsage_returnsFalseWithoutMutation() public {
        uint256 policyId = 9012;
        Policy memory policy = _timeIntervalPolicy(1, 0);

        bytes32 key =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA13), address(0xB13), address(0xC13));
        uint256 window = harness.computeTimeWindowViaPolicyLibrary(policy);

        bool ok = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            policyId, policy, address(0xA13), address(0xB13), address(0xC13), 1
        );
        uint256 usage = policyStateHarness.getPolicyUsage(key, window);

        assertFalse(ok, "positive usage with zero limit should fail");
        assertEq(usage, 0, "failed update should not mutate usage");
    }

    /// @dev [LPRL-UPD-13] Desired behavior: invalid `RateLimitType` fails closed and does not write usage.
    function test_checkAndUpdateRateLimit_invalidRateLimitType_failsClosed_desired() public {
        uint256 policyId = 9013;
        Policy memory policy = _timeIntervalPolicy(1, 10);

        bytes32 key =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA14), address(0xB14), address(0xC14));
        uint256 window = harness.computeTimeWindowViaPolicyLibrary(policy);

        bool ok = harness.checkAndUpdateRateLimitViaPolicyLibraryRawLimitType(
            policyId, policy, type(uint256).max, address(0xA14), address(0xB14), address(0xC14), 1
        );

        uint256 usage = policyStateHarness.getPolicyUsage(key, window);
        assertFalse(ok, "desired behavior: invalid rate-limit enum should fail closed");
        assertEq(usage, 0, "invalid enum must not mutate usage");
    }

    /// @dev [LPRL-WIN-1] `timeIntervalHours == 0` returns window 0.
    function test_computeTimeWindow_zeroHours_returnsZero() public {
        Policy memory policy = _timeIntervalPolicy(0, 100);
        uint256 window = harness.computeTimeWindowViaPolicyLibrary(policy);
        assertEq(window, 0, "zero interval hours should return window 0");
    }

    /// @dev [LPRL-WIN-2] Computes `block.timestamp / (hours * 3600)` exactly.
    function test_computeTimeWindow_matchesExactFormula() public {
        Policy memory policy = _timeIntervalPolicy(3, 100);
        vm.warp(39_999);

        uint256 expected = block.timestamp / (uint256(3) * 3600);
        uint256 actual = harness.computeTimeWindowViaPolicyLibrary(policy);

        assertEq(actual, expected, "window formula should match exact integer division");
    }

    /// @dev [LPRL-WIN-3] Window increments exactly on boundary timestamp.
    function test_computeTimeWindow_incrementsExactlyOnBoundary() public {
        Policy memory policy = _timeIntervalPolicy(2, 100);

        vm.warp(7199);
        uint256 beforeBoundary = harness.computeTimeWindowViaPolicyLibrary(policy);

        vm.warp(7200);
        uint256 atBoundary = harness.computeTimeWindowViaPolicyLibrary(policy);

        assertEq(beforeBoundary, 0, "before boundary should still be window 0");
        assertEq(atBoundary, 1, "boundary timestamp should enter next window");
    }

    /// @dev [LPRL-WIN-4] Max uint16 interval hours is supported without arithmetic issues.
    function test_computeTimeWindow_maxUint16Hours_supported() public {
        uint16 hours_ = type(uint16).max;
        Policy memory policy = _timeIntervalPolicy(hours_, 100);

        vm.warp(uint256(hours_) * 3600 * 3 + 17);

        uint256 expected = block.timestamp / (uint256(hours_) * 3600);
        uint256 actual = harness.computeTimeWindowViaPolicyLibrary(policy);

        assertEq(actual, expected, "max uint16 interval-hours should compute correctly");
    }

    /// @dev [LPRL-GET-1] Returns 0 when no active time-interval limit.
    function test_getCurrentUsage_noActiveTimeIntervalLimit_returnsZero() public {
        uint256 policyId = 9101;
        Policy memory policy = _buildBasePolicy();
        policy.config.rateLimit.limitType = RateLimitType.None;
        policy.config.rateLimit.timeIntervalHours = 1;

        bytes32 key =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA21), address(0xB21), address(0xC21));
        uint256 window = harness.computeTimeWindowViaPolicyLibrary(_timeIntervalPolicy(1, 100));
        policyStateHarness.setPolicyUsage(key, window, 77);

        uint256 usage =
            harness.getCurrentUsageViaPolicyLibrary(policyId, policy, address(0xA21), address(0xB21), address(0xC21));
        assertEq(usage, 0, "non-time-interval limit should always report zero usage");
    }

    /// @dev [LPRL-GET-2] Returns tracked usage for the current window/key.
    function test_getCurrentUsage_returnsTrackedUsageForCurrentWindowAndKey() public {
        uint256 policyId = 9102;
        Policy memory policy = _timeIntervalPolicy(1, 100);

        bytes32 key =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA22), address(0xB22), address(0xC22));
        uint256 window = harness.computeTimeWindowViaPolicyLibrary(policy);
        policyStateHarness.setPolicyUsage(key, window, 7);

        uint256 usage =
            harness.getCurrentUsageViaPolicyLibrary(policyId, policy, address(0xA22), address(0xB22), address(0xC22));
        assertEq(usage, 7, "current usage should match stored usage for current key/window");
    }

    /// @dev [LPRL-GET-3] Usage from other windows is not returned.
    function test_getCurrentUsage_usageFromOtherWindows_notReturned() public {
        uint256 policyId = 9103;
        Policy memory policy = _timeIntervalPolicy(1, 100);

        vm.warp(7200);
        bytes32 key =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA23), address(0xB23), address(0xC23));
        uint256 currentWindow = harness.computeTimeWindowViaPolicyLibrary(policy);

        policyStateHarness.setPolicyUsage(key, currentWindow - 1, 99);

        uint256 usage =
            harness.getCurrentUsageViaPolicyLibrary(policyId, policy, address(0xA23), address(0xB23), address(0xC23));
        assertEq(usage, 0, "usage from prior window should not be returned");
    }

    /// @dev [LPRL-GET-4] Usage from other scoped keys is not returned.
    function test_getCurrentUsage_usageFromOtherScopedKeys_notReturned() public {
        uint256 policyId = 9104;
        Policy memory policy = _timeIntervalPolicy(1, 100);
        policy.config.rateLimit.sourceScope = RateLimitScope.PerEntity;

        bytes32 keyA =
            harness.computeUsageKeyViaPolicyLibrary(policyId, policy, address(0xA24), address(0xB24), address(0xC24));
        uint256 window = harness.computeTimeWindowViaPolicyLibrary(policy);
        policyStateHarness.setPolicyUsage(keyA, window, 44);

        uint256 usage =
            harness.getCurrentUsageViaPolicyLibrary(policyId, policy, address(0xA25), address(0xB24), address(0xC24));
        assertEq(usage, 0, "different scoped key should not see other entity usage");
    }

    /// @dev [LPRL-KEY-1] AcrossAll scopes ignore account/destination/initiator differences.
    function test_computeUsageKey_allAcrossAllScopes_ignoresEntityDifferences() public {
        Policy memory policy = _timeIntervalPolicy(1, 100);

        bytes32 keyA =
            harness.computeUsageKeyViaPolicyLibrary(9201, policy, address(0xA31), address(0xB31), address(0xC31));
        bytes32 keyB =
            harness.computeUsageKeyViaPolicyLibrary(9201, policy, address(0xA32), address(0xB32), address(0xC32));

        assertEq(keyA, keyB, "across-all scopes should collide across entities");
    }

    /// @dev [LPRL-KEY-2] `sourceScope == PerEntity` separates usage by account.
    function test_computeUsageKey_sourceScopePerEntity_separatesByAccount() public {
        Policy memory policy = _timeIntervalPolicy(1, 100);
        policy.config.rateLimit.sourceScope = RateLimitScope.PerEntity;

        bytes32 keyA =
            harness.computeUsageKeyViaPolicyLibrary(9202, policy, address(0xA33), address(0xB33), address(0xC33));
        bytes32 keyB =
            harness.computeUsageKeyViaPolicyLibrary(9202, policy, address(0xA34), address(0xB33), address(0xC33));

        assertTrue(keyA != keyB, "per-entity source scope should separate keys by account");
    }

    /// @dev [LPRL-KEY-3] `destinationScope == PerEntity` separates usage by destination.
    function test_computeUsageKey_destinationScopePerEntity_separatesByDestination() public {
        Policy memory policy = _timeIntervalPolicy(1, 100);
        policy.config.rateLimit.destinationScope = RateLimitScope.PerEntity;

        bytes32 keyA =
            harness.computeUsageKeyViaPolicyLibrary(9203, policy, address(0xA35), address(0xB35), address(0xC35));
        bytes32 keyB =
            harness.computeUsageKeyViaPolicyLibrary(9203, policy, address(0xA35), address(0xB36), address(0xC35));

        assertTrue(keyA != keyB, "per-entity destination scope should separate keys by destination");
    }

    /// @dev [LPRL-KEY-4] `initiatorScope == PerEntity` separates usage by initiator.
    function test_computeUsageKey_initiatorScopePerEntity_separatesByInitiator() public {
        Policy memory policy = _timeIntervalPolicy(1, 100);
        policy.config.rateLimit.initiatorScope = RateLimitScope.PerEntity;

        bytes32 keyA =
            harness.computeUsageKeyViaPolicyLibrary(9204, policy, address(0xA37), address(0xB37), address(0xC37));
        bytes32 keyB =
            harness.computeUsageKeyViaPolicyLibrary(9204, policy, address(0xA37), address(0xB37), address(0xC38));

        assertTrue(keyA != keyB, "per-entity initiator scope should separate keys by initiator");
    }

    /// @dev [LPRL-KEY-5] Different policy IDs always produce different keys.
    function test_computeUsageKey_differentPolicyIds_produceDifferentKeys() public {
        Policy memory policy = _timeIntervalPolicy(1, 100);

        bytes32 keyA =
            harness.computeUsageKeyViaPolicyLibrary(9205, policy, address(0xA39), address(0xB39), address(0xC39));
        bytes32 keyB =
            harness.computeUsageKeyViaPolicyLibrary(9206, policy, address(0xA39), address(0xB39), address(0xC39));

        assertTrue(keyA != keyB, "policyId must be part of usage-key domain");
    }

    /// @dev [LPRL-KEY-6] Mixed scope combinations produce expected collisions and separations.
    function test_computeUsageKey_mixedScopes_expectedCollisionsAndSeparations() public {
        Policy memory policy = _timeIntervalPolicy(1, 100);
        policy.config.rateLimit.sourceScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.destinationScope = RateLimitScope.AcrossAll;
        policy.config.rateLimit.initiatorScope = RateLimitScope.PerEntity;

        bytes32 key1 =
            harness.computeUsageKeyViaPolicyLibrary(9207, policy, address(0xA40), address(0xB40), address(0xC40));
        bytes32 key2 =
            harness.computeUsageKeyViaPolicyLibrary(9207, policy, address(0xA40), address(0xB41), address(0xC40));
        bytes32 key3 =
            harness.computeUsageKeyViaPolicyLibrary(9207, policy, address(0xA41), address(0xB40), address(0xC40));
        bytes32 key4 =
            harness.computeUsageKeyViaPolicyLibrary(9207, policy, address(0xA40), address(0xB40), address(0xC41));

        assertEq(key1, key2, "destination across-all should collide despite destination changes");
        assertTrue(key1 != key3, "source per-entity should separate by account");
        assertTrue(key1 != key4, "initiator per-entity should separate by initiator");
    }

    /// @dev [LPRL-KEY-7] Deterministic output for identical inputs.
    function test_computeUsageKey_identicalInputs_deterministic() public {
        Policy memory policy = _timeIntervalPolicy(1, 100);

        bytes32 first =
            harness.computeUsageKeyViaPolicyLibrary(9208, policy, address(0xA42), address(0xB42), address(0xC42));
        bytes32 second =
            harness.computeUsageKeyViaPolicyLibrary(9208, policy, address(0xA42), address(0xB42), address(0xC42));

        assertEq(first, second, "usage key must be deterministic");
    }

    /// @dev [LPRL-KEY-8] Invalid scope values fail closed by behaving like AcrossAll.
    function test_computeUsageKey_invalidScopes_treatedAsAcrossAll() public {
        uint256 policyId = 9209;
        Policy memory policy = _timeIntervalPolicy(1, 100);

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

        assertEq(invalidScopesKey, expectedAcrossAll, "invalid scope values should collapse to across-all behavior");
    }

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
