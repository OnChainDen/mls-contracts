// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { LibOrganizationPolicy } from "../src/organization/libraries/LibOrganizationPolicy.sol";
import { Policies } from "../src/libraries/Policies.sol";

/**
 * @title Time-Based Policy Limits Test
 * @notice Tests for time-based policy limit functionality
 */
contract TimeBasedPolicyLimitsTest is Test {
    address constant ACCOUNT_1 = address(0x1);
    address constant ACCOUNT_2 = address(0x2);
    address constant DESTINATION_1 = address(0x3);
    address constant DESTINATION_2 = address(0x4);
    address constant INITIATOR_1 = address(0x5);
    address constant INITIATOR_2 = address(0x6);
    address constant APPROVER_MEMBER = address(0x7);

    uint256 constant POLICY_ID = 1;

    function setUp() public {
        vm.warp(1_000_000);
    }

    // ================================
    // computeTimeWindow Tests
    // ================================

    function test_computeTimeWindow_basicCalculation() public view {
        Policies.Policy memory policy = _createPolicy(24, 1000, Policies.PolicyLimitation.TimeInterval);

        uint256 expectedWindow = uint256(1_000_000) / (uint256(24) * uint256(3600));
        uint256 actualWindow = LibOrganizationPolicy.computeTimeWindow(policy);
        assertEq(actualWindow, expectedWindow, "Time window calculation incorrect");
    }

    function test_computeTimeWindow_zeroHoursReturnsZero() public view {
        Policies.Policy memory policy = _createPolicy(0, 1000, Policies.PolicyLimitation.TimeInterval);

        uint256 actualWindow = LibOrganizationPolicy.computeTimeWindow(policy);
        assertEq(actualWindow, 0, "Zero hours should return 0 window");
    }

    function test_computeTimeWindow_changesWithTime() public {
        Policies.Policy memory policy = _createPolicy(1, 1000, Policies.PolicyLimitation.TimeInterval);

        uint256 window1 = LibOrganizationPolicy.computeTimeWindow(policy);

        vm.warp(block.timestamp + 3600);

        uint256 window2 = LibOrganizationPolicy.computeTimeWindow(policy);
        assertEq(window2, window1 + 1, "Time window should increment after 1 hour");
    }

    // ================================
    // computeUsageKey Tests
    // ================================

    function test_computeUsageKey_allAcrossAllScopes() public pure {
        Policies.Policy memory policy = _createPolicy(24, 1000, Policies.PolicyLimitation.TimeInterval);
        // Default is AcrossAll for all scopes

        bytes32 key1 = LibOrganizationPolicy.computeUsageKey(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);
        bytes32 key2 = LibOrganizationPolicy.computeUsageKey(POLICY_ID, policy, ACCOUNT_2, DESTINATION_2, INITIATOR_2);

        assertEq(key1, key2, "Keys should be equal when all scopes are AcrossAll");
    }

    function test_computeUsageKey_perAccountScope() public pure {
        Policies.Policy memory policy = _createPolicyWithSourceScope();

        bytes32 key1 = LibOrganizationPolicy.computeUsageKey(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);
        bytes32 key2 = LibOrganizationPolicy.computeUsageKey(POLICY_ID, policy, ACCOUNT_2, DESTINATION_1, INITIATOR_1);

        assertTrue(key1 != key2, "Keys should be different for different accounts when PerEntity");
    }

    function test_computeUsageKey_perDestinationScope() public pure {
        Policies.Policy memory policy = _createPolicyWithDestScope();

        bytes32 key1 = LibOrganizationPolicy.computeUsageKey(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);
        bytes32 key2 = LibOrganizationPolicy.computeUsageKey(POLICY_ID, policy, ACCOUNT_1, DESTINATION_2, INITIATOR_1);

        assertTrue(key1 != key2, "Keys should be different for different destinations when PerEntity");
    }

    function test_computeUsageKey_perInitiatorScope() public pure {
        Policies.Policy memory policy = _createPolicyWithInitiatorScope();

        bytes32 key1 = LibOrganizationPolicy.computeUsageKey(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);
        bytes32 key2 = LibOrganizationPolicy.computeUsageKey(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_2);

        assertTrue(key1 != key2, "Keys should be different for different initiators when PerEntity");
    }

    function test_computeUsageKey_differentPolicyIds() public pure {
        Policies.Policy memory policy = _createPolicy(24, 1000, Policies.PolicyLimitation.TimeInterval);

        bytes32 key1 = LibOrganizationPolicy.computeUsageKey(1, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);
        bytes32 key2 = LibOrganizationPolicy.computeUsageKey(2, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);

        assertTrue(key1 != key2, "Keys should be different for different policy IDs");
    }

    // ================================
    // checkAndUpdateTimeBasedLimit Tests
    // ================================

    function test_checkAndUpdateTimeBasedLimit_skipIfNoLimitation() public {
        Policies.Policy memory policy = _createPolicy(24, 1000, Policies.PolicyLimitation.None);

        bool withinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1000
        );

        assertTrue(withinLimit, "Should return true when no limitation");
    }

    function test_checkAndUpdateTimeBasedLimit_skipIfSingleTransactionLimitation() public {
        Policies.Policy memory policy = _createPolicy(24, 1000, Policies.PolicyLimitation.SingleTransaction);

        bool withinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1000
        );

        assertTrue(withinLimit, "Should return true when SingleTransaction limitation");
    }

    function test_checkAndUpdateTimeBasedLimit_skipIfZeroHours() public {
        Policies.Policy memory policy = _createPolicy(0, 1000, Policies.PolicyLimitation.TimeInterval);

        bool withinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1000
        );

        assertTrue(withinLimit, "Should return true when timeIntervalHours is 0");
    }

    function test_checkAndUpdateTimeBasedLimit_withinLimit() public {
        Policies.Policy memory policy = _createPolicy(24, 1000, Policies.PolicyLimitation.TimeInterval);

        bool withinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 500
        );

        assertTrue(withinLimit, "Should return true when usage is within limit");
    }

    function test_checkAndUpdateTimeBasedLimit_exactlyAtLimit() public {
        Policies.Policy memory policy = _createPolicy(24, 1000, Policies.PolicyLimitation.TimeInterval);

        bool withinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1000
        );

        assertTrue(withinLimit, "Should return true when usage exactly equals limit");
    }

    function test_checkAndUpdateTimeBasedLimit_exceedsLimit() public {
        Policies.Policy memory policy = _createPolicy(24, 1000, Policies.PolicyLimitation.TimeInterval);

        bool withinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1001
        );

        assertFalse(withinLimit, "Should return false when usage exceeds limit");
    }

    function test_checkAndUpdateTimeBasedLimit_cumulativeUsage() public {
        Policies.Policy memory policy = _createPolicy(24, 1000, Policies.PolicyLimitation.TimeInterval);

        bool firstWithinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 500
        );
        assertTrue(firstWithinLimit, "First transaction should be within limit");

        bool secondWithinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 400
        );
        assertTrue(secondWithinLimit, "Second transaction should be within limit");

        bool thirdWithinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 200
        );
        assertFalse(thirdWithinLimit, "Third transaction should exceed limit");
    }

    function test_checkAndUpdateTimeBasedLimit_resetsInNewWindow() public {
        Policies.Policy memory policy = _createPolicy(1, 1000, Policies.PolicyLimitation.TimeInterval);

        bool firstWithinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1000
        );
        assertTrue(firstWithinLimit, "First transaction should be within limit");

        bool secondWithinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1
        );
        assertFalse(secondWithinLimit, "Second transaction should exceed limit in same window");

        vm.warp(block.timestamp + 3600);

        bool thirdWithinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 500
        );
        assertTrue(thirdWithinLimit, "Third transaction should be within limit in new window");
    }

    function test_checkAndUpdateTimeBasedLimit_perAccountIndependent() public {
        Policies.Policy memory policy = _createPolicyWithSourceScope();

        bool account1First = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1000
        );
        assertTrue(account1First, "Account 1 first transaction should be within limit");

        bool account1Second = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1
        );
        assertFalse(account1Second, "Account 1 second transaction should exceed limit");

        bool account2First = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_2, DESTINATION_1, INITIATOR_1, 1000
        );
        assertTrue(account2First, "Account 2 first transaction should be within limit");
    }

    // ================================
    // getCurrentUsage Tests
    // ================================

    function test_getCurrentUsage_returnsZeroForNoLimitation() public view {
        Policies.Policy memory policy = _createPolicy(24, 1000, Policies.PolicyLimitation.None);

        uint256 usage = LibOrganizationPolicy.getCurrentUsage(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);

        assertEq(usage, 0, "Should return 0 when no time-based limitation");
    }

    function test_getCurrentUsage_returnsZeroForZeroHours() public view {
        Policies.Policy memory policy = _createPolicy(0, 1000, Policies.PolicyLimitation.TimeInterval);

        uint256 usage = LibOrganizationPolicy.getCurrentUsage(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);

        assertEq(usage, 0, "Should return 0 when timeIntervalHours is 0");
    }

    function test_getCurrentUsage_tracksUsageCorrectly() public {
        Policies.Policy memory policy = _createPolicy(24, 1000, Policies.PolicyLimitation.TimeInterval);

        uint256 initialUsage =
            LibOrganizationPolicy.getCurrentUsage(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);
        assertEq(initialUsage, 0, "Initial usage should be 0");

        LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 500
        );

        uint256 afterFirstUsage =
            LibOrganizationPolicy.getCurrentUsage(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);
        assertEq(afterFirstUsage, 500, "Usage should be 500 after first transaction");

        LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 300
        );

        uint256 afterSecondUsage =
            LibOrganizationPolicy.getCurrentUsage(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);
        assertEq(afterSecondUsage, 800, "Usage should be 800 after second transaction");
    }

    // ================================
    // Helper Functions - Create policies using new struct format with Merkle-based members
    // ================================

    function _createPolicy(
        uint16 hours_,
        uint256 limit,
        Policies.PolicyLimitation limitationType
    )
        internal
        pure
        returns (Policies.Policy memory policy)
    {
        // Set up PolicyConfig
        policy.config.transactionType = Policies.TransactionType.TokenTransfers;
        policy.config.anySourceAccount = true;
        policy.config.anyFunction = true;
        policy.config.destinationType = Policies.DestinationType.Any;

        // Set up ApprovalConfig (using new Merkle-based format with address/groupId)
        policy.config.approval.policyType = Policies.PolicyType.AutoApprove;
        policy.config.approval.approverType = Policies.ApproverType.Member;
        policy.config.approval.approverMember = APPROVER_MEMBER;
        policy.config.approval.approverGroupId = bytes32(0);
        policy.config.approval.approvalThreshold = 1;

        // Set up InitiatorConfig (using new Merkle-based format with address/groupId)
        policy.config.initiator.anyInitiator = true;
        policy.config.initiator.initiatorType = Policies.ApproverType.Member;
        policy.config.initiator.initiatorMember = address(0);
        policy.config.initiator.initiatorGroupId = bytes32(0);

        // Set up TokenFilter
        policy.config.token.anyToken = true;
        policy.config.token.tokenAddress = address(0);
        policy.config.token.hasAmountThreshold = false;
        policy.config.token.amountThreshold = 0;

        // Set up TimeLimitConfig
        policy.config.timeLimit.limitation = limitationType;
        policy.config.timeLimit.timeIntervalHours = hours_;
        policy.config.timeLimit.timeIntervalLimit = limit;
        policy.config.timeLimit.initiatorScope = Policies.TimeIntervalScope.AcrossAll;
        policy.config.timeLimit.sourceScope = Policies.TimeIntervalScope.AcrossAll;
        policy.config.timeLimit.destinationScope = Policies.TimeIntervalScope.AcrossAll;

        // Set up PolicyRoots (empty for this test)
        policy.roots.sourceAccountsRoot = bytes32(0);
        policy.roots.customDestinationsRoot = bytes32(0);
        policy.roots.allowedFunctionsRoot = bytes32(0);
    }

    function _createPolicyWithSourceScope() internal pure returns (Policies.Policy memory policy) {
        policy = _createPolicy(24, 1000, Policies.PolicyLimitation.TimeInterval);
        policy.config.timeLimit.sourceScope = Policies.TimeIntervalScope.PerEntity;
    }

    function _createPolicyWithDestScope() internal pure returns (Policies.Policy memory policy) {
        policy = _createPolicy(24, 1000, Policies.PolicyLimitation.TimeInterval);
        policy.config.timeLimit.destinationScope = Policies.TimeIntervalScope.PerEntity;
    }

    function _createPolicyWithInitiatorScope() internal pure returns (Policies.Policy memory policy) {
        policy = _createPolicy(24, 1000, Policies.PolicyLimitation.TimeInterval);
        policy.config.timeLimit.initiatorScope = Policies.TimeIntervalScope.PerEntity;
    }
}
