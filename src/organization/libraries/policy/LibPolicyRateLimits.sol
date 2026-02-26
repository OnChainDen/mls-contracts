// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {LibOrganizationPolicyStorage} from "organization/libraries/storage/LibOrganizationPolicyStorage.sol";
import {Policy, RateLimitScope, RateLimitType} from "types/PolicyTypes.sol";

/**
 * @title Lib Policy Rate Limits
 * @dev Library for policy rate limit tracking and validation.
 *      Handles checking and updating usage limits for policies.
 *      Time windows are calculated as fixed intervals based on block.timestamp.
 * @author Den Technologies Inc
 */
library LibPolicyRateLimits {
    /// @dev Number of seconds in one hour, used for time window calculations
    uint256 private constant SECONDS_PER_HOUR = 3600;

    /**
     * @dev Checks and updates rate limit usage.
     *      Checks if the usage amount would exceed the limit for the current time window.
     *      If within limit, updates the usage and returns true.
     *      If exceeding limit, returns false without updating.
     * @param policyId The policy ID
     * @param policy The policy data
     * @param account The source account address
     * @param destination The destination address
     * @param initiator The initiator address
     * @param usageAmount The amount to add to usage (transfer amount or 1 for non-transfers)
     * @return withinLimit True if within limit (and usage was updated), false otherwise
     */
    function checkAndUpdateRateLimit(
        uint256 policyId,
        Policy memory policy,
        address account,
        address destination,
        address initiator,
        uint256 usageAmount
    ) internal returns (bool withinLimit) {
        // Case: Rate limiting is explicitly disabled by policy.
        if (policy.config.rateLimit.limitType == RateLimitType.None) return true;

        // Case: Unknown rate-limit enum values fail closed.
        if (policy.config.rateLimit.limitType != RateLimitType.TimeInterval) return false;

        // Skip if time interval is not configured (0 hours)
        if (policy.config.rateLimit.timeIntervalHours == 0) return true;

        LibOrganizationPolicyStorage.Layout storage policyLayout = LibOrganizationPolicyStorage.layout();

        bytes32 usageKey = computeUsageKey({
            policyId: policyId, policy: policy, account: account, destination: destination, initiator: initiator
        });
        uint256 timeWindow = computeTimeWindow(policy);

        uint256 currentUsage = policyLayout.policyUsage[usageKey][timeWindow];

        // Fail closed on arithmetic overflow in usage accumulation.
        if (usageAmount > type(uint256).max - currentUsage) return false;

        uint256 nextUsage = currentUsage + usageAmount;

        // Check if adding usageAmount would exceed the limit
        if (nextUsage > policy.config.rateLimit.timeIntervalLimit) return false;

        // Update usage
        policyLayout.policyUsage[usageKey][timeWindow] = nextUsage;

        return true;
    }

    /**
     * @dev Computes the current time window for a policy.
     *      Time windows are calculated as: block.timestamp / (timeIntervalHours * 3600)
     * @param policy The policy data
     * @return The current time window, or 0 if timeIntervalHours is 0
     */
    function computeTimeWindow(Policy memory policy) internal view returns (uint256) {
        // Uses fixed time windows based on timeIntervalHours
        uint16 hours_ = policy.config.rateLimit.timeIntervalHours;

        // Avoid division by zero
        if (hours_ == 0) return 0;

        return block.timestamp / (uint256(hours_) * SECONDS_PER_HOUR);
    }

    /**
     * @dev Gets the current usage for a rate-limited policy
     * @param policyId The policy ID
     * @param policy The policy data
     * @param account The source account address
     * @param destination The destination address
     * @param initiator The initiator address
     * @return The current usage amount within the current time window
     */
    function getCurrentUsage(
        uint256 policyId,
        Policy memory policy,
        address account,
        address destination,
        address initiator
    ) internal view returns (uint256) {
        // Return 0 if no rate limit configured
        if (policy.config.rateLimit.limitType != RateLimitType.TimeInterval) return 0;

        // Return 0 if time interval is not configured
        if (policy.config.rateLimit.timeIntervalHours == 0) return 0;

        LibOrganizationPolicyStorage.Layout storage policyLayout = LibOrganizationPolicyStorage.layout();

        bytes32 usageKey = computeUsageKey({
            policyId: policyId, policy: policy, account: account, destination: destination, initiator: initiator
        });
        uint256 timeWindow = computeTimeWindow(policy);

        return policyLayout.policyUsage[usageKey][timeWindow];
    }

    /**
     * @dev Computes the usage key for rate limit tracking.
     *      The usage key is a hash of the policy ID and scoped entities.
     *      If a scope is AcrossAll, address(0) is used for that component.
     *      If a scope is PerEntity, the actual address is used.
     * @param policyId The policy ID
     * @param policy The policy data
     * @param account The source account address
     * @param destination The destination address
     * @param initiator The initiator address
     * @return The computed usage key
     */
    function computeUsageKey(
        uint256 policyId,
        Policy memory policy,
        address account,
        address destination,
        address initiator
    ) internal pure returns (bytes32) {
        // Determine scoped values based on policy configuration
        // When scope is AcrossAll, address(0) is used for that entity.
        // When scope is PerEntity, the actual address is used.
        address scopedAccount = policy.config.rateLimit.sourceScope == RateLimitScope.PerEntity ? account : address(0);

        address scopedDestination =
            policy.config.rateLimit.destinationScope == RateLimitScope.PerEntity ? destination : address(0);

        address scopedInitiator =
            policy.config.rateLimit.initiatorScope == RateLimitScope.PerEntity ? initiator : address(0);

        return keccak256(abi.encode(policyId, scopedAccount, scopedDestination, scopedInitiator));
    }
}
