// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {LibOrganizationPolicyStorage} from "organization/libraries/storage/LibOrganizationPolicyStorage.sol";
import {Policy, PolicyLimitation, TimeIntervalScope} from "types/PolicyTypes.sol";

/**
 * @title Lib Policy Time Based Limits
 * @dev Library for time-based policy limit tracking and validation
 * @dev Handles checking and updating time-based usage limits for policies.
 *      Time windows are calculated as fixed intervals based on block.timestamp.
 * @author Den Technologies Inc
 */
library LibPolicyTimeBasedLimits {
    /// @dev Number of seconds in one hour, used for time window calculations
    uint256 private constant SECONDS_PER_HOUR = 3600;

    /**
     * @dev Checks and updates time-based usage limits
     * @dev Checks if the usage amount would exceed the limit for the current time window.
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
    function checkAndUpdateTimeBasedLimit(
        uint256 policyId,
        Policy memory policy,
        address account,
        address destination,
        address initiator,
        uint256 usageAmount
    ) internal returns (bool withinLimit) {
        // Skip check if no time-based limitation
        if (policy.config.timeLimit.limitation != PolicyLimitation.TimeInterval) return true;

        // Skip if time interval is not configured (0 hours)
        if (policy.config.timeLimit.timeIntervalHours == 0) return true;

        LibOrganizationPolicyStorage.Layout storage policyLayout = LibOrganizationPolicyStorage.layout();

        bytes32 usageKey = computeUsageKey({
            policyId: policyId, policy: policy, account: account, destination: destination, initiator: initiator
        });
        uint256 timeWindow = computeTimeWindow(policy);

        uint256 currentUsage = policyLayout.policyUsage[usageKey][timeWindow];

        // Check if adding usageAmount would exceed the limit
        if (currentUsage + usageAmount > policy.config.timeLimit.timeIntervalLimit) return false;

        // Update usage
        policyLayout.policyUsage[usageKey][timeWindow] = currentUsage + usageAmount;

        return true;
    }

    /**
     * @dev Computes the current time window for a policy
     * @dev Time windows are calculated as: block.timestamp / (timeIntervalHours * 3600)
     * @param policy The policy data
     * @return The current time window, or 0 if timeIntervalHours is 0
     */
    function computeTimeWindow(Policy memory policy) internal view returns (uint256) {
        // Uses fixed time windows based on timeIntervalHours
        uint16 hours_ = policy.config.timeLimit.timeIntervalHours;

        // Avoid division by zero
        if (hours_ == 0) return 0;

        return block.timestamp / (uint256(hours_) * SECONDS_PER_HOUR);
    }

    /**
     * @dev Gets the current usage for a time-based policy
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
        // Return 0 if no time-based limitation
        if (policy.config.timeLimit.limitation != PolicyLimitation.TimeInterval) return 0;

        // Return 0 if time interval is not configured
        if (policy.config.timeLimit.timeIntervalHours == 0) return 0;

        LibOrganizationPolicyStorage.Layout storage policyLayout = LibOrganizationPolicyStorage.layout();

        bytes32 usageKey = computeUsageKey({
            policyId: policyId, policy: policy, account: account, destination: destination, initiator: initiator
        });
        uint256 timeWindow = computeTimeWindow(policy);

        return policyLayout.policyUsage[usageKey][timeWindow];
    }

    /**
     * @dev Computes the usage key for time-based limit tracking
     * @dev The usage key is a hash of the policy ID and scoped entities.
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
        address scopedAccount =
            policy.config.timeLimit.sourceScope == TimeIntervalScope.PerEntity ? account : address(0);

        address scopedDestination =
            policy.config.timeLimit.destinationScope == TimeIntervalScope.PerEntity ? destination : address(0);

        address scopedInitiator =
            policy.config.timeLimit.initiatorScope == TimeIntervalScope.PerEntity ? initiator : address(0);

        return keccak256(abi.encode(policyId, scopedAccount, scopedDestination, scopedInitiator));
    }
}
