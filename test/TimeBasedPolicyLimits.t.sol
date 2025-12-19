// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { LibOrganizationPolicy } from "../src/organization/libraries/LibOrganizationPolicy.sol";
import { LibOrganizationPolicyStorage } from "../src/organization/libraries/storage/LibOrganizationPolicyStorage.sol";
import { Policies } from "../src/libraries/Policies.sol";

/**
 * @title Time-Based Policy Limits Test
 * @notice Tests for time-based policy limit functionality
 * @dev Tests the computeUsageKey, computeTimeWindow, checkAndUpdateTimeBasedLimit, and getCurrentUsage functions
 */
contract TimeBasedPolicyLimitsTest is Test {
    // Test addresses
    address constant ACCOUNT_1 = address(0x1);
    address constant ACCOUNT_2 = address(0x2);
    address constant DESTINATION_1 = address(0x3);
    address constant DESTINATION_2 = address(0x4);
    address constant INITIATOR_1 = address(0x5);
    address constant INITIATOR_2 = address(0x6);

    // Test policy ID
    uint256 constant POLICY_ID = 1;

    function setUp() public {
        // Set block timestamp to a known value
        vm.warp(1_000_000);
    }

    // ================================
    // computeTimeWindow Tests
    // ================================

    function test_computeTimeWindow_basicCalculation() public {
        Policies.Policy memory policy = _createBasicTimeBasedPolicy();
        policy.timeIntervalHours = 24; // 24 hours = 86400 seconds

        // At timestamp 1000000, window should be 1000000 / 86400 = 11 (integer division)
        uint256 expectedWindow = uint256(1_000_000) / (uint256(24) * uint256(3600));
        uint256 actualWindow = LibOrganizationPolicy.computeTimeWindow(policy);
        assertEq(actualWindow, expectedWindow, "Time window calculation incorrect");
    }

    function test_computeTimeWindow_zeroHoursReturnsZero() public {
        Policies.Policy memory policy = _createBasicTimeBasedPolicy();
        policy.timeIntervalHours = 0;

        uint256 actualWindow = LibOrganizationPolicy.computeTimeWindow(policy);
        assertEq(actualWindow, 0, "Zero hours should return 0 window");
    }

    function test_computeTimeWindow_changesWithTime() public {
        Policies.Policy memory policy = _createBasicTimeBasedPolicy();
        policy.timeIntervalHours = 1; // 1 hour = 3600 seconds

        uint256 window1 = LibOrganizationPolicy.computeTimeWindow(policy);

        // Advance time by 1 hour
        vm.warp(block.timestamp + 3600);

        uint256 window2 = LibOrganizationPolicy.computeTimeWindow(policy);
        assertEq(window2, window1 + 1, "Time window should increment after 1 hour");
    }

    // ================================
    // computeUsageKey Tests
    // ================================

    function test_computeUsageKey_allAcrossAllScopes() public {
        Policies.Policy memory policy = _createBasicTimeBasedPolicy();
        policy.timeIntervalSourceScope = Policies.TimeIntervalScope.AcrossAll;
        policy.timeIntervalDestinationScope = Policies.TimeIntervalScope.AcrossAll;
        policy.timeIntervalInitiatorScope = Policies.TimeIntervalScope.AcrossAll;

        // When all scopes are AcrossAll, different accounts/destinations/initiators should have same key
        bytes32 key1 = LibOrganizationPolicy.computeUsageKey(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);
        bytes32 key2 = LibOrganizationPolicy.computeUsageKey(POLICY_ID, policy, ACCOUNT_2, DESTINATION_2, INITIATOR_2);

        assertEq(key1, key2, "Keys should be equal when all scopes are AcrossAll");
    }

    function test_computeUsageKey_perAccountScope() public {
        Policies.Policy memory policy = _createBasicTimeBasedPolicy();
        policy.timeIntervalSourceScope = Policies.TimeIntervalScope.PerEntity;
        policy.timeIntervalDestinationScope = Policies.TimeIntervalScope.AcrossAll;
        policy.timeIntervalInitiatorScope = Policies.TimeIntervalScope.AcrossAll;

        bytes32 key1 = LibOrganizationPolicy.computeUsageKey(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);
        bytes32 key2 = LibOrganizationPolicy.computeUsageKey(POLICY_ID, policy, ACCOUNT_2, DESTINATION_1, INITIATOR_1);

        assertTrue(key1 != key2, "Keys should be different for different accounts when PerEntity");
    }

    function test_computeUsageKey_perDestinationScope() public {
        Policies.Policy memory policy = _createBasicTimeBasedPolicy();
        policy.timeIntervalSourceScope = Policies.TimeIntervalScope.AcrossAll;
        policy.timeIntervalDestinationScope = Policies.TimeIntervalScope.PerEntity;
        policy.timeIntervalInitiatorScope = Policies.TimeIntervalScope.AcrossAll;

        bytes32 key1 = LibOrganizationPolicy.computeUsageKey(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);
        bytes32 key2 = LibOrganizationPolicy.computeUsageKey(POLICY_ID, policy, ACCOUNT_1, DESTINATION_2, INITIATOR_1);

        assertTrue(key1 != key2, "Keys should be different for different destinations when PerEntity");
    }

    function test_computeUsageKey_perInitiatorScope() public {
        Policies.Policy memory policy = _createBasicTimeBasedPolicy();
        policy.timeIntervalSourceScope = Policies.TimeIntervalScope.AcrossAll;
        policy.timeIntervalDestinationScope = Policies.TimeIntervalScope.AcrossAll;
        policy.timeIntervalInitiatorScope = Policies.TimeIntervalScope.PerEntity;

        bytes32 key1 = LibOrganizationPolicy.computeUsageKey(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);
        bytes32 key2 = LibOrganizationPolicy.computeUsageKey(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_2);

        assertTrue(key1 != key2, "Keys should be different for different initiators when PerEntity");
    }

    function test_computeUsageKey_differentPolicyIds() public {
        Policies.Policy memory policy = _createBasicTimeBasedPolicy();

        bytes32 key1 = LibOrganizationPolicy.computeUsageKey(1, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);
        bytes32 key2 = LibOrganizationPolicy.computeUsageKey(2, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);

        assertTrue(key1 != key2, "Keys should be different for different policy IDs");
    }

    // ================================
    // checkAndUpdateTimeBasedLimit Tests
    // ================================

    function test_checkAndUpdateTimeBasedLimit_skipIfNoLimitation() public {
        Policies.Policy memory policy = _createBasicTimeBasedPolicy();
        policy.limitation = Policies.PolicyLimitation.None;

        bool withinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1000
        );

        assertTrue(withinLimit, "Should return true when no limitation");
    }

    function test_checkAndUpdateTimeBasedLimit_skipIfSingleTransactionLimitation() public {
        Policies.Policy memory policy = _createBasicTimeBasedPolicy();
        policy.limitation = Policies.PolicyLimitation.SingleTransaction;

        bool withinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1000
        );

        assertTrue(withinLimit, "Should return true when SingleTransaction limitation");
    }

    function test_checkAndUpdateTimeBasedLimit_skipIfZeroHours() public {
        Policies.Policy memory policy = _createBasicTimeBasedPolicy();
        policy.timeIntervalHours = 0;

        bool withinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1000
        );

        assertTrue(withinLimit, "Should return true when timeIntervalHours is 0");
    }

    function test_checkAndUpdateTimeBasedLimit_withinLimit() public {
        Policies.Policy memory policy = _createBasicTimeBasedPolicy();
        policy.timeIntervalLimit = 1000;

        bool withinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 500
        );

        assertTrue(withinLimit, "Should return true when usage is within limit");
    }

    function test_checkAndUpdateTimeBasedLimit_exactlyAtLimit() public {
        Policies.Policy memory policy = _createBasicTimeBasedPolicy();
        policy.timeIntervalLimit = 1000;

        bool withinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1000
        );

        assertTrue(withinLimit, "Should return true when usage exactly equals limit");
    }

    function test_checkAndUpdateTimeBasedLimit_exceedsLimit() public {
        Policies.Policy memory policy = _createBasicTimeBasedPolicy();
        policy.timeIntervalLimit = 1000;

        bool withinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1001
        );

        assertFalse(withinLimit, "Should return false when usage exceeds limit");
    }

    function test_checkAndUpdateTimeBasedLimit_cumulativeUsage() public {
        Policies.Policy memory policy = _createBasicTimeBasedPolicy();
        policy.timeIntervalLimit = 1000;

        // First transaction: 500
        bool firstWithinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 500
        );
        assertTrue(firstWithinLimit, "First transaction should be within limit");

        // Second transaction: 400 (cumulative: 900)
        bool secondWithinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 400
        );
        assertTrue(secondWithinLimit, "Second transaction should be within limit");

        // Third transaction: 200 (would be 1100, exceeds 1000)
        bool thirdWithinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 200
        );
        assertFalse(thirdWithinLimit, "Third transaction should exceed limit");
    }

    function test_checkAndUpdateTimeBasedLimit_resetsInNewWindow() public {
        Policies.Policy memory policy = _createBasicTimeBasedPolicy();
        policy.timeIntervalLimit = 1000;
        policy.timeIntervalHours = 1; // 1 hour window

        // Use up the limit
        bool firstWithinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1000
        );
        assertTrue(firstWithinLimit, "First transaction should be within limit");

        // Try to use more in same window - should fail
        bool secondWithinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1
        );
        assertFalse(secondWithinLimit, "Second transaction should exceed limit in same window");

        // Advance time to new window
        vm.warp(block.timestamp + 3600);

        // Should be able to use again in new window
        bool thirdWithinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 500
        );
        assertTrue(thirdWithinLimit, "Third transaction should be within limit in new window");
    }

    function test_checkAndUpdateTimeBasedLimit_perAccountIndependent() public {
        Policies.Policy memory policy = _createBasicTimeBasedPolicy();
        policy.timeIntervalLimit = 1000;
        policy.timeIntervalSourceScope = Policies.TimeIntervalScope.PerEntity;

        // Account 1 uses up limit
        bool account1First = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1000
        );
        assertTrue(account1First, "Account 1 first transaction should be within limit");

        // Account 1 can't use more
        bool account1Second = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1
        );
        assertFalse(account1Second, "Account 1 second transaction should exceed limit");

        // Account 2 should still be able to use (independent tracking)
        bool account2First = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_2, DESTINATION_1, INITIATOR_1, 1000
        );
        assertTrue(account2First, "Account 2 first transaction should be within limit");
    }

    // ================================
    // getCurrentUsage Tests
    // ================================

    function test_getCurrentUsage_returnsZeroForNoLimitation() public {
        Policies.Policy memory policy = _createBasicTimeBasedPolicy();
        policy.limitation = Policies.PolicyLimitation.None;

        // Store policy in storage
        _storePolicy(POLICY_ID, policy);

        uint256 usage = LibOrganizationPolicy.getCurrentUsage(POLICY_ID, ACCOUNT_1, DESTINATION_1, INITIATOR_1);

        assertEq(usage, 0, "Should return 0 when no time-based limitation");
    }

    function test_getCurrentUsage_returnsZeroForZeroHours() public {
        Policies.Policy memory policy = _createBasicTimeBasedPolicy();
        policy.timeIntervalHours = 0;

        // Store policy in storage
        _storePolicy(POLICY_ID, policy);

        uint256 usage = LibOrganizationPolicy.getCurrentUsage(POLICY_ID, ACCOUNT_1, DESTINATION_1, INITIATOR_1);

        assertEq(usage, 0, "Should return 0 when timeIntervalHours is 0");
    }

    function test_getCurrentUsage_tracksUsageCorrectly() public {
        Policies.Policy memory policy = _createBasicTimeBasedPolicy();
        policy.timeIntervalLimit = 1000;

        // Store policy in storage
        _storePolicy(POLICY_ID, policy);

        // Initial usage should be 0
        uint256 initialUsage = LibOrganizationPolicy.getCurrentUsage(POLICY_ID, ACCOUNT_1, DESTINATION_1, INITIATOR_1);
        assertEq(initialUsage, 0, "Initial usage should be 0");

        // Use 500
        LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 500
        );

        // Check usage is now 500
        uint256 afterFirstUsage =
            LibOrganizationPolicy.getCurrentUsage(POLICY_ID, ACCOUNT_1, DESTINATION_1, INITIATOR_1);
        assertEq(afterFirstUsage, 500, "Usage should be 500 after first transaction");

        // Use 300 more
        LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 300
        );

        // Check usage is now 800
        uint256 afterSecondUsage =
            LibOrganizationPolicy.getCurrentUsage(POLICY_ID, ACCOUNT_1, DESTINATION_1, INITIATOR_1);
        assertEq(afterSecondUsage, 800, "Usage should be 800 after second transaction");
    }

    // ================================
    // Helper Functions
    // ================================

    function _createBasicTimeBasedPolicy() internal pure returns (Policies.Policy memory policy) {
        policy.policyType = Policies.PolicyType.AutoApprove;
        policy.approverType = Policies.ApproverType.Member;
        policy.approverId = 1;
        policy.approvalThreshold = 1;
        policy.anySourceAccount = true;
        policy.anyInitiator = true;
        policy.transactionType = Policies.TransactionType.TokenTransfers;
        policy.anyToken = true;
        policy.hasAmountThreshold = false;
        policy.destinationType = Policies.DestinationType.Any;
        policy.anyFunction = true;
        policy.limitation = Policies.PolicyLimitation.TimeInterval;
        policy.timeIntervalHours = 24;
        policy.timeIntervalInitiatorScope = Policies.TimeIntervalScope.AcrossAll;
        policy.timeIntervalSourceScope = Policies.TimeIntervalScope.AcrossAll;
        policy.timeIntervalDestinationScope = Policies.TimeIntervalScope.AcrossAll;
        policy.timeIntervalLimit = 1000;
    }

    function _storePolicy(uint256 policyId, Policies.Policy memory policy) internal {
        LibOrganizationPolicyStorage.Layout storage policyLayout = LibOrganizationPolicyStorage.layout();
        policyLayout.policies[policyId] = policy;
        policyLayout.policyExists[policyId] = true;
    }
}
