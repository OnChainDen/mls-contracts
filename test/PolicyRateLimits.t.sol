// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {LibOrganizationPolicy} from "organization/libraries/LibOrganizationPolicy.sol";
import {
    ApproverType,
    DestinationType,
    Policy,
    PolicyType,
    RateLimitScope,
    RateLimitType,
    TransactionType
} from "types/PolicyTypes.sol";

/**
 * @dev Policy Rate Limits Test
 *      Tests for policy rate limit functionality
 */
contract PolicyRateLimitsTest is Test {
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
        Policy memory policy = _createPolicy(24, 1000, RateLimitType.TimeInterval);

        uint256 expectedWindow = uint256(1_000_000) / (uint256(24) * uint256(3600));
        uint256 actualWindow = LibOrganizationPolicy.computeTimeWindow(policy);
        assertEq(actualWindow, expectedWindow, "Time window calculation incorrect");
    }

    function test_computeTimeWindow_zeroHoursReturnsZero() public view {
        Policy memory policy = _createPolicy(0, 1000, RateLimitType.TimeInterval);

        uint256 actualWindow = LibOrganizationPolicy.computeTimeWindow(policy);
        assertEq(actualWindow, 0, "Zero hours should return 0 window");
    }

    function test_computeTimeWindow_changesWithTime() public {
        Policy memory policy = _createPolicy(1, 1000, RateLimitType.TimeInterval);

        uint256 window1 = LibOrganizationPolicy.computeTimeWindow(policy);

        vm.warp(block.timestamp + 3600);

        uint256 window2 = LibOrganizationPolicy.computeTimeWindow(policy);
        assertEq(window2, window1 + 1, "Time window should increment after 1 hour");
    }

    // ================================
    // computeUsageKey Tests
    // ================================

    function test_computeUsageKey_allAcrossAllScopes() public pure {
        Policy memory policy = _createPolicy(24, 1000, RateLimitType.TimeInterval);
        // Default is AcrossAll for all scopes

        bytes32 key1 = LibOrganizationPolicy.computeUsageKey(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);
        bytes32 key2 = LibOrganizationPolicy.computeUsageKey(POLICY_ID, policy, ACCOUNT_2, DESTINATION_2, INITIATOR_2);

        assertEq(key1, key2, "Keys should be equal when all scopes are AcrossAll");
    }

    function test_computeUsageKey_perAccountScope() public pure {
        Policy memory policy = _createPolicyWithSourceScope();

        bytes32 key1 = LibOrganizationPolicy.computeUsageKey(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);
        bytes32 key2 = LibOrganizationPolicy.computeUsageKey(POLICY_ID, policy, ACCOUNT_2, DESTINATION_1, INITIATOR_1);

        assertTrue(key1 != key2, "Keys should be different for different accounts when PerEntity");
    }

    function test_computeUsageKey_perDestinationScope() public pure {
        Policy memory policy = _createPolicyWithDestScope();

        bytes32 key1 = LibOrganizationPolicy.computeUsageKey(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);
        bytes32 key2 = LibOrganizationPolicy.computeUsageKey(POLICY_ID, policy, ACCOUNT_1, DESTINATION_2, INITIATOR_1);

        assertTrue(key1 != key2, "Keys should be different for different destinations when PerEntity");
    }

    function test_computeUsageKey_perInitiatorScope() public pure {
        Policy memory policy = _createPolicyWithInitiatorScope();

        bytes32 key1 = LibOrganizationPolicy.computeUsageKey(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);
        bytes32 key2 = LibOrganizationPolicy.computeUsageKey(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_2);

        assertTrue(key1 != key2, "Keys should be different for different initiators when PerEntity");
    }

    function test_computeUsageKey_differentPolicyIds() public pure {
        Policy memory policy = _createPolicy(24, 1000, RateLimitType.TimeInterval);

        bytes32 key1 = LibOrganizationPolicy.computeUsageKey(1, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);
        bytes32 key2 = LibOrganizationPolicy.computeUsageKey(2, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);

        assertTrue(key1 != key2, "Keys should be different for different policy IDs");
    }

    // ================================
    // checkAndUpdateRateLimit Tests
    // ================================

    function test_checkAndUpdateRateLimit_skipIfNoLimitation() public {
        Policy memory policy = _createPolicy(24, 1000, RateLimitType.None);

        bool withinLimit = LibOrganizationPolicy.checkAndUpdateRateLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1000
        );

        assertTrue(withinLimit, "Should return true when no limitation");
    }

    function test_checkAndUpdateRateLimit_zeroHours_returnsFalseWithoutWritingUsage() public {
        Policy memory policy = _createPolicy(0, 1000, RateLimitType.TimeInterval);

        bool withinLimit = LibOrganizationPolicy.checkAndUpdateRateLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1000
        );
        uint256 usage = LibOrganizationPolicy.getCurrentUsage(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);

        assertFalse(withinLimit, "Should return false when timeIntervalHours is 0");
        assertEq(usage, 0, "Zero-hour configuration should not write usage");
    }

    function test_checkAndUpdateRateLimit_withinLimit() public {
        Policy memory policy = _createPolicy(24, 1000, RateLimitType.TimeInterval);

        bool withinLimit = LibOrganizationPolicy.checkAndUpdateRateLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 500
        );

        assertTrue(withinLimit, "Should return true when usage is within limit");
    }

    function test_checkAndUpdateRateLimit_exactlyAtLimit() public {
        Policy memory policy = _createPolicy(24, 1000, RateLimitType.TimeInterval);

        bool withinLimit = LibOrganizationPolicy.checkAndUpdateRateLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1000
        );

        assertTrue(withinLimit, "Should return true when usage exactly equals limit");
    }

    function test_checkAndUpdateRateLimit_exceedsLimit() public {
        Policy memory policy = _createPolicy(24, 1000, RateLimitType.TimeInterval);

        bool withinLimit = LibOrganizationPolicy.checkAndUpdateRateLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1001
        );

        assertFalse(withinLimit, "Should return false when usage exceeds limit");
    }

    function test_checkAndUpdateRateLimit_cumulativeUsage() public {
        Policy memory policy = _createPolicy(24, 1000, RateLimitType.TimeInterval);

        bool firstWithinLimit = LibOrganizationPolicy.checkAndUpdateRateLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 500
        );
        assertTrue(firstWithinLimit, "First transaction should be within limit");

        bool secondWithinLimit = LibOrganizationPolicy.checkAndUpdateRateLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 400
        );
        assertTrue(secondWithinLimit, "Second transaction should be within limit");

        bool thirdWithinLimit = LibOrganizationPolicy.checkAndUpdateRateLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 200
        );
        assertFalse(thirdWithinLimit, "Third transaction should exceed limit");
    }

    function test_checkAndUpdateRateLimit_resetsInNewWindow() public {
        Policy memory policy = _createPolicy(1, 1000, RateLimitType.TimeInterval);

        bool firstWithinLimit = LibOrganizationPolicy.checkAndUpdateRateLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1000
        );
        assertTrue(firstWithinLimit, "First transaction should be within limit");

        bool secondWithinLimit =
            LibOrganizationPolicy.checkAndUpdateRateLimit(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1);
        assertFalse(secondWithinLimit, "Second transaction should exceed limit in same window");

        vm.warp(block.timestamp + 3600);

        bool thirdWithinLimit = LibOrganizationPolicy.checkAndUpdateRateLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 500
        );
        assertTrue(thirdWithinLimit, "Third transaction should be within limit in new window");
    }

    function test_checkAndUpdateRateLimit_perAccountIndependent() public {
        Policy memory policy = _createPolicyWithSourceScope();

        bool account1First = LibOrganizationPolicy.checkAndUpdateRateLimit(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1000
        );
        assertTrue(account1First, "Account 1 first transaction should be within limit");

        bool account1Second =
            LibOrganizationPolicy.checkAndUpdateRateLimit(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1);
        assertFalse(account1Second, "Account 1 second transaction should exceed limit");

        bool account2First = LibOrganizationPolicy.checkAndUpdateRateLimit(
            POLICY_ID, policy, ACCOUNT_2, DESTINATION_1, INITIATOR_1, 1000
        );
        assertTrue(account2First, "Account 2 first transaction should be within limit");
    }

    // ================================
    // getCurrentUsage Tests
    // ================================

    function test_getCurrentUsage_returnsZeroForNoLimitation() public view {
        Policy memory policy = _createPolicy(24, 1000, RateLimitType.None);

        uint256 usage = LibOrganizationPolicy.getCurrentUsage(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);

        assertEq(usage, 0, "Should return 0 when no rate limit configured");
    }

    function test_getCurrentUsage_returnsZeroForZeroHours() public view {
        Policy memory policy = _createPolicy(0, 1000, RateLimitType.TimeInterval);

        uint256 usage = LibOrganizationPolicy.getCurrentUsage(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);

        assertEq(usage, 0, "Should return 0 when timeIntervalHours is 0");
    }

    function test_getCurrentUsage_tracksUsageCorrectly() public {
        Policy memory policy = _createPolicy(24, 1000, RateLimitType.TimeInterval);

        uint256 initialUsage =
            LibOrganizationPolicy.getCurrentUsage(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);
        assertEq(initialUsage, 0, "Initial usage should be 0");

        LibOrganizationPolicy.checkAndUpdateRateLimit(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 500);

        uint256 afterFirstUsage =
            LibOrganizationPolicy.getCurrentUsage(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);
        assertEq(afterFirstUsage, 500, "Usage should be 500 after first transaction");

        LibOrganizationPolicy.checkAndUpdateRateLimit(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 300);

        uint256 afterSecondUsage =
            LibOrganizationPolicy.getCurrentUsage(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);
        assertEq(afterSecondUsage, 800, "Usage should be 800 after second transaction");
    }

    // ================================
    // Helper Functions - Create policies using new struct format with Merkle-based members
    // ================================

    /**
     * @dev Creates a base policy with the specified rate limit configuration
     *      Creates a policy with anySourceAccount, anyFunction, and anyDestination enabled.
     *      Uses AutoApprove policy type with anyInitiator.
     * @param hours_ The time interval in hours for the limit window
     * @param limit The maximum usage allowed within the time interval
     * @param limitType The type of rate limit (None or TimeInterval)
     * @return policy The constructed policy struct
     */
    function _createPolicy(uint16 hours_, uint256 limit, RateLimitType limitType)
        internal
        pure
        returns (Policy memory policy)
    {
        // Set up PolicyConfig
        policy.config.transactionType = TransactionType.TokenTransfers;
        policy.config.anySourceAccount = true;
        policy.config.anyFunction = true;
        policy.config.destinationType = DestinationType.Any;

        // Set up ApprovalConfig (using new Merkle-based format with address/groupId)
        policy.config.approval.policyType = PolicyType.AutoApprove;
        policy.config.approval.approverType = ApproverType.Member;
        policy.config.approval.approverMember = APPROVER_MEMBER;
        policy.config.approval.approverGroupId = 0;
        policy.config.approval.approvalThreshold = 1;

        // Set up InitiatorConfig (using new Merkle-based format with address/groupId)
        policy.config.initiator.anyInitiator = true;
        policy.config.initiator.initiatorType = ApproverType.Member;
        policy.config.initiator.initiatorMember = address(0);
        policy.config.initiator.initiatorGroupId = 0;

        // Set up TokenFilter
        policy.config.token.anyToken = true;
        policy.config.token.tokenAddress = address(0);
        policy.config.token.hasAmountThreshold = false;
        policy.config.token.amountThreshold = 0;

        // Set up RateLimitConfig
        policy.config.rateLimit.limitType = limitType;
        policy.config.rateLimit.timeIntervalHours = hours_;
        policy.config.rateLimit.timeIntervalLimit = limit;
        policy.config.rateLimit.initiatorScope = RateLimitScope.AcrossAll;
        policy.config.rateLimit.sourceScope = RateLimitScope.AcrossAll;
        policy.config.rateLimit.destinationScope = RateLimitScope.AcrossAll;

        // Set up PolicyRoots (empty for this test)
        policy.roots.sourceAccountsRoot = bytes32(0);
        policy.roots.customDestinationsRoot = bytes32(0);
        policy.roots.allowedFunctionsRoot = bytes32(0);
    }

    /**
     * @dev Creates a policy with PerEntity source account scope
     *      Limits are tracked separately per source account
     * @return policy The constructed policy struct with source scope set to PerEntity
     */
    function _createPolicyWithSourceScope() internal pure returns (Policy memory policy) {
        policy = _createPolicy(24, 1000, RateLimitType.TimeInterval);
        policy.config.rateLimit.sourceScope = RateLimitScope.PerEntity;
    }

    /**
     * @dev Creates a policy with PerEntity destination scope
     *      Limits are tracked separately per destination address
     * @return policy The constructed policy struct with destination scope set to PerEntity
     */
    function _createPolicyWithDestScope() internal pure returns (Policy memory policy) {
        policy = _createPolicy(24, 1000, RateLimitType.TimeInterval);
        policy.config.rateLimit.destinationScope = RateLimitScope.PerEntity;
    }

    /**
     * @dev Creates a policy with PerEntity initiator scope
     *      Limits are tracked separately per initiator address
     * @return policy The constructed policy struct with initiator scope set to PerEntity
     */
    function _createPolicyWithInitiatorScope() internal pure returns (Policy memory policy) {
        policy = _createPolicy(24, 1000, RateLimitType.TimeInterval);
        policy.config.rateLimit.initiatorScope = RateLimitScope.PerEntity;
    }
}
