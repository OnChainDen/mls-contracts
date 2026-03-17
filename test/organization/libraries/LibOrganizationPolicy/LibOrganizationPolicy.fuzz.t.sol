// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibOrganizationPolicySuiteBase
} from "test/organization/libraries/LibOrganizationPolicy/LibOrganizationPolicySuiteBase.sol";
import {Policy, RateLimitScope, RateLimitType} from "types/PolicyTypes.sol";

/**
 * @dev Fuzz tests for `LibOrganizationPolicy`.
 */
contract LibOrganizationPolicyFuzzTest is LibOrganizationPolicySuiteBase {
    /**
     * @dev Verifies the policies root changes only through explicit `setPolicies` calls and remains unchanged across
     *      other policy-library helper activity.
     * @param initialRoot Initial root written through `setPolicies`
     * @param nextRoot Replacement root written through the second `setPolicies` call
     * @param usageAmountRaw Raw usage amount used to derive a bounded rate-limit update
     * @param account Source account used for the rate-limit helper call
     * @param destination Destination used for the rate-limit helper call
     * @param initiator Initiator used for the rate-limit helper call
     */
    function testFuzz_FLOP_SET_55_setPolicies_rootChangesOnlyThroughExplicitSetPoliciesCalls(
        bytes32 initialRoot,
        bytes32 nextRoot,
        uint96 usageAmountRaw,
        address account,
        address destination,
        address initiator
    ) public {
        // Setup: seed one rate-limited policy helper call and two distinct policy roots.
        vm.assume(initialRoot != nextRoot);

        Policy memory policy = _buildBasePolicy();
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = type(uint256).max;
        policy.config.rateLimit.sourceScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.destinationScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.initiatorScope = RateLimitScope.PerEntity;

        uint256 usageAmount = bound(uint256(usageAmountRaw), 1, type(uint96).max);
        bytes32[] memory emptyProof = new bytes32[](0);

        // Call: write the initial root, exercise non-root helper paths, then write the replacement root explicitly.
        harness.setPoliciesViaLibrary(initialRoot, "ipfs://floa-set-55-initial");
        harness.checkAndUpdateRateLimitViaLibrary(55, policy, account, destination, initiator, usageAmount);
        harness.isPolicyInOrgViaLibrary(55, policy, emptyProof);
        harness.computePolicyLeafViaLibrary(55, policy);

        // Verify: non-root helpers should not mutate the stored policies root.
        assertEq(harness.getPoliciesRoot(), initialRoot, "non-root helpers should not mutate the policies root");

        // Call: replace the stored root through the explicit root-setting entry point.
        harness.setPoliciesViaLibrary(nextRoot, "ipfs://floa-set-55-next");
        harness.checkAndUpdateRateLimitViaLibrary(56, policy, account, destination, initiator, usageAmount);

        // Verify: the stored policies root should change only on explicit `setPolicies` calls and stay stable
        // afterwards.
        assertEq(harness.getPoliciesRoot(), nextRoot, "explicit setPolicies should replace the stored root exactly");
    }
}
