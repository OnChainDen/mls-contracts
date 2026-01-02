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
        uint256 actualWindow = LibOrganizationPolicy.computeTimeWindowMemory(policy);
        assertEq(actualWindow, expectedWindow, "Time window calculation incorrect");
    }

    function test_computeTimeWindow_zeroHoursReturnsZero() public view {
        Policies.Policy memory policy = _createPolicy(0, 1000, Policies.PolicyLimitation.TimeInterval);

        uint256 actualWindow = LibOrganizationPolicy.computeTimeWindowMemory(policy);
        assertEq(actualWindow, 0, "Zero hours should return 0 window");
    }

    function test_computeTimeWindow_changesWithTime() public {
        Policies.Policy memory policy = _createPolicy(1, 1000, Policies.PolicyLimitation.TimeInterval);

        uint256 window1 = LibOrganizationPolicy.computeTimeWindowMemory(policy);

        vm.warp(block.timestamp + 3600);

        uint256 window2 = LibOrganizationPolicy.computeTimeWindowMemory(policy);
        assertEq(window2, window1 + 1, "Time window should increment after 1 hour");
    }

    // ================================
    // computeUsageKey Tests
    // ================================

    function test_computeUsageKey_allAcrossAllScopes() public pure {
        Policies.Policy memory policy = _createPolicy(24, 1000, Policies.PolicyLimitation.TimeInterval);
        // Default is AcrossAll for all scopes

        bytes32 key1 =
            LibOrganizationPolicy.computeUsageKeyMemory(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);
        bytes32 key2 =
            LibOrganizationPolicy.computeUsageKeyMemory(POLICY_ID, policy, ACCOUNT_2, DESTINATION_2, INITIATOR_2);

        assertEq(key1, key2, "Keys should be equal when all scopes are AcrossAll");
    }

    function test_computeUsageKey_perAccountScope() public pure {
        Policies.Policy memory policy = _createPolicyWithSourceScope();

        bytes32 key1 =
            LibOrganizationPolicy.computeUsageKeyMemory(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);
        bytes32 key2 =
            LibOrganizationPolicy.computeUsageKeyMemory(POLICY_ID, policy, ACCOUNT_2, DESTINATION_1, INITIATOR_1);

        assertTrue(key1 != key2, "Keys should be different for different accounts when PerEntity");
    }

    function test_computeUsageKey_perDestinationScope() public pure {
        Policies.Policy memory policy = _createPolicyWithDestScope();

        bytes32 key1 =
            LibOrganizationPolicy.computeUsageKeyMemory(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);
        bytes32 key2 =
            LibOrganizationPolicy.computeUsageKeyMemory(POLICY_ID, policy, ACCOUNT_1, DESTINATION_2, INITIATOR_1);

        assertTrue(key1 != key2, "Keys should be different for different destinations when PerEntity");
    }

    function test_computeUsageKey_perInitiatorScope() public pure {
        Policies.Policy memory policy = _createPolicyWithInitiatorScope();

        bytes32 key1 =
            LibOrganizationPolicy.computeUsageKeyMemory(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);
        bytes32 key2 =
            LibOrganizationPolicy.computeUsageKeyMemory(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_2);

        assertTrue(key1 != key2, "Keys should be different for different initiators when PerEntity");
    }

    function test_computeUsageKey_differentPolicyIds() public pure {
        Policies.Policy memory policy = _createPolicy(24, 1000, Policies.PolicyLimitation.TimeInterval);

        bytes32 key1 = LibOrganizationPolicy.computeUsageKeyMemory(1, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);
        bytes32 key2 = LibOrganizationPolicy.computeUsageKeyMemory(2, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);

        assertTrue(key1 != key2, "Keys should be different for different policy IDs");
    }

    // ================================
    // checkAndUpdateTimeBasedLimit Tests
    // ================================

    function test_checkAndUpdateTimeBasedLimit_skipIfNoLimitation() public {
        Policies.Policy memory policy = _createPolicy(24, 1000, Policies.PolicyLimitation.None);

        bool withinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimitMemory(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1000
        );

        assertTrue(withinLimit, "Should return true when no limitation");
    }

    function test_checkAndUpdateTimeBasedLimit_skipIfSingleTransactionLimitation() public {
        Policies.Policy memory policy = _createPolicy(24, 1000, Policies.PolicyLimitation.SingleTransaction);

        bool withinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimitMemory(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1000
        );

        assertTrue(withinLimit, "Should return true when SingleTransaction limitation");
    }

    function test_checkAndUpdateTimeBasedLimit_skipIfZeroHours() public {
        Policies.Policy memory policy = _createPolicy(0, 1000, Policies.PolicyLimitation.TimeInterval);

        bool withinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimitMemory(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1000
        );

        assertTrue(withinLimit, "Should return true when timeIntervalHours is 0");
    }

    function test_checkAndUpdateTimeBasedLimit_withinLimit() public {
        Policies.Policy memory policy = _createPolicy(24, 1000, Policies.PolicyLimitation.TimeInterval);

        bool withinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimitMemory(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 500
        );

        assertTrue(withinLimit, "Should return true when usage is within limit");
    }

    function test_checkAndUpdateTimeBasedLimit_exactlyAtLimit() public {
        Policies.Policy memory policy = _createPolicy(24, 1000, Policies.PolicyLimitation.TimeInterval);

        bool withinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimitMemory(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1000
        );

        assertTrue(withinLimit, "Should return true when usage exactly equals limit");
    }

    function test_checkAndUpdateTimeBasedLimit_exceedsLimit() public {
        Policies.Policy memory policy = _createPolicy(24, 1000, Policies.PolicyLimitation.TimeInterval);

        bool withinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimitMemory(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1001
        );

        assertFalse(withinLimit, "Should return false when usage exceeds limit");
    }

    function test_checkAndUpdateTimeBasedLimit_cumulativeUsage() public {
        Policies.Policy memory policy = _createPolicy(24, 1000, Policies.PolicyLimitation.TimeInterval);

        bool firstWithinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimitMemory(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 500
        );
        assertTrue(firstWithinLimit, "First transaction should be within limit");

        bool secondWithinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimitMemory(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 400
        );
        assertTrue(secondWithinLimit, "Second transaction should be within limit");

        bool thirdWithinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimitMemory(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 200
        );
        assertFalse(thirdWithinLimit, "Third transaction should exceed limit");
    }

    function test_checkAndUpdateTimeBasedLimit_resetsInNewWindow() public {
        Policies.Policy memory policy = _createPolicy(1, 1000, Policies.PolicyLimitation.TimeInterval);

        bool firstWithinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimitMemory(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1000
        );
        assertTrue(firstWithinLimit, "First transaction should be within limit");

        bool secondWithinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimitMemory(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1
        );
        assertFalse(secondWithinLimit, "Second transaction should exceed limit in same window");

        vm.warp(block.timestamp + 3600);

        bool thirdWithinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimitMemory(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 500
        );
        assertTrue(thirdWithinLimit, "Third transaction should be within limit in new window");
    }

    function test_checkAndUpdateTimeBasedLimit_perAccountIndependent() public {
        Policies.Policy memory policy = _createPolicyWithSourceScope();

        bool account1First = LibOrganizationPolicy.checkAndUpdateTimeBasedLimitMemory(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1000
        );
        assertTrue(account1First, "Account 1 first transaction should be within limit");

        bool account1Second = LibOrganizationPolicy.checkAndUpdateTimeBasedLimitMemory(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 1
        );
        assertFalse(account1Second, "Account 1 second transaction should exceed limit");

        bool account2First = LibOrganizationPolicy.checkAndUpdateTimeBasedLimitMemory(
            POLICY_ID, policy, ACCOUNT_2, DESTINATION_1, INITIATOR_1, 1000
        );
        assertTrue(account2First, "Account 2 first transaction should be within limit");
    }

    // ================================
    // getCurrentUsage Tests
    // ================================

    function test_getCurrentUsage_returnsZeroForNoLimitation() public view {
        Policies.Policy memory policy = _createPolicy(24, 1000, Policies.PolicyLimitation.None);

        uint256 usage =
            LibOrganizationPolicy.getCurrentUsageMemory(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);

        assertEq(usage, 0, "Should return 0 when no time-based limitation");
    }

    function test_getCurrentUsage_returnsZeroForZeroHours() public view {
        Policies.Policy memory policy = _createPolicy(0, 1000, Policies.PolicyLimitation.TimeInterval);

        uint256 usage =
            LibOrganizationPolicy.getCurrentUsageMemory(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);

        assertEq(usage, 0, "Should return 0 when timeIntervalHours is 0");
    }

    function test_getCurrentUsage_tracksUsageCorrectly() public {
        Policies.Policy memory policy = _createPolicy(24, 1000, Policies.PolicyLimitation.TimeInterval);

        uint256 initialUsage =
            LibOrganizationPolicy.getCurrentUsageMemory(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);
        assertEq(initialUsage, 0, "Initial usage should be 0");

        LibOrganizationPolicy.checkAndUpdateTimeBasedLimitMemory(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 500
        );

        uint256 afterFirstUsage =
            LibOrganizationPolicy.getCurrentUsageMemory(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);
        assertEq(afterFirstUsage, 500, "Usage should be 500 after first transaction");

        LibOrganizationPolicy.checkAndUpdateTimeBasedLimitMemory(
            POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1, 300
        );

        uint256 afterSecondUsage =
            LibOrganizationPolicy.getCurrentUsageMemory(POLICY_ID, policy, ACCOUNT_1, DESTINATION_1, INITIATOR_1);
        assertEq(afterSecondUsage, 800, "Usage should be 800 after second transaction");
    }

    // ================================
    // Helper Functions - Build packed directly without using packConfig
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
        policy.config.packed = _buildPacked(hours_, limitationType, 0, 0, 0); // all AcrossAll
        policy.config.timeIntervalLimit = limit;
        policy.config.tokenAddress = address(0);
        policy.config.amountThreshold = 0;
        policy.roots.sourceAccountsRoot = bytes32(0);
        policy.roots.customDestinationsRoot = bytes32(0);
        policy.roots.allowedFunctionsRoot = bytes32(0);
    }

    function _createPolicyWithSourceScope() internal pure returns (Policies.Policy memory policy) {
        // Source scope = PerEntity (1), others AcrossAll (0)
        policy.config.packed = _buildPacked(24, Policies.PolicyLimitation.TimeInterval, 0, 1, 0);
        policy.config.timeIntervalLimit = 1000;
        policy.config.tokenAddress = address(0);
        policy.config.amountThreshold = 0;
        policy.roots.sourceAccountsRoot = bytes32(0);
        policy.roots.customDestinationsRoot = bytes32(0);
        policy.roots.allowedFunctionsRoot = bytes32(0);
    }

    function _createPolicyWithDestScope() internal pure returns (Policies.Policy memory policy) {
        // Dest scope = PerEntity (1), others AcrossAll (0)
        policy.config.packed = _buildPacked(24, Policies.PolicyLimitation.TimeInterval, 0, 0, 1);
        policy.config.timeIntervalLimit = 1000;
        policy.config.tokenAddress = address(0);
        policy.config.amountThreshold = 0;
        policy.roots.sourceAccountsRoot = bytes32(0);
        policy.roots.customDestinationsRoot = bytes32(0);
        policy.roots.allowedFunctionsRoot = bytes32(0);
    }

    function _createPolicyWithInitiatorScope() internal pure returns (Policies.Policy memory policy) {
        // Initiator scope = PerEntity (1), others AcrossAll (0)
        policy.config.packed = _buildPacked(24, Policies.PolicyLimitation.TimeInterval, 1, 0, 0);
        policy.config.timeIntervalLimit = 1000;
        policy.config.tokenAddress = address(0);
        policy.config.amountThreshold = 0;
        policy.roots.sourceAccountsRoot = bytes32(0);
        policy.roots.customDestinationsRoot = bytes32(0);
        policy.roots.allowedFunctionsRoot = bytes32(0);
    }

    /// @notice Build the packed config directly without calling packConfig
    /// @param hours_ Time interval hours
    /// @param limitationType The policy limitation type
    /// @param initiatorScope 0 = AcrossAll, 1 = PerEntity
    /// @param sourceScope 0 = AcrossAll, 1 = PerEntity
    /// @param destScope 0 = AcrossAll, 1 = PerEntity
    function _buildPacked(
        uint16 hours_,
        Policies.PolicyLimitation limitationType,
        uint256 initiatorScope,
        uint256 sourceScope,
        uint256 destScope
    )
        private
        pure
        returns (uint256 packed)
    {
        // Flags: all true (anySourceAccount, anyInitiator, anyToken, anyFunction)
        packed = Policies.FLAG_ANY_SOURCE_ACCOUNT | Policies.FLAG_ANY_INITIATOR | Policies.FLAG_ANY_TOKEN
            | Policies.FLAG_ANY_FUNCTION;

        // PolicyType.AutoApprove = 0, so no shift needed
        // ApproverType.Member = 1, but Member is defined as second (index 1), Group is 0
        // Actually looking at enum: Group=0, Member=1
        packed |= uint256(1) << Policies.SHIFT_APPROVER_TYPE; // Member
        packed |= uint256(1) << Policies.SHIFT_INITIATOR_TYPE; // Member
        // DestinationType.Any = 0, no shift needed
        packed |= uint256(limitationType) << Policies.SHIFT_LIMITATION;
        packed |= uint256(1) << Policies.SHIFT_TX_TYPE; // TokenTransfers = 1
        packed |= uint256(1) << Policies.SHIFT_APPROVER_ID; // approverId = 1
        packed |= uint256(1) << Policies.SHIFT_APPROVAL_THRESHOLD; // threshold = 1
        // initiatorId = 0, no shift needed
        packed |= uint256(hours_) << Policies.SHIFT_TIME_HOURS;

        // Pack scopes: initiator (bits 0-1), source (bits 2-3), dest (bits 4-5)
        uint256 scopes = initiatorScope | (sourceScope << 2) | (destScope << 4);
        packed |= scopes << Policies.SHIFT_TIME_SCOPES;
    }
}
