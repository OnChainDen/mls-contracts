// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibOrganizationPolicyHarness
} from "test/organization/libraries/LibOrganizationPolicy/LibOrganizationPolicyHarness.sol";
import {
    ApprovalConfig,
    ApproverType,
    DestinationType,
    InitiatorConfig,
    Policy,
    PolicyConfig,
    PolicyRoots,
    PolicyType,
    RateLimitConfig,
    RateLimitScope,
    RateLimitType,
    TokenFilter,
    TransactionType
} from "types/PolicyTypes.sol";

/**
 * @dev Stateful invariant handler for cross-file policy invariants.
 *      Tracks root and rate-limit mutation behavior across fuzzed operation sequences.
 */
contract OrganizationPolicyInvariantHandler {
    /// @dev Harness under invariant testing.
    LibOrganizationPolicyHarness public immutable harness;

    /// @dev Model root updated only via handler `setPolicies` operations.
    bytes32 public modelPoliciesRoot;

    /// @dev Violation flag for monotonic usage growth on successful updates.
    bool public usageMonotonicViolation;

    /// @dev Violation flag for usage mutation when an update is out-of-limit.
    bool public exceededLimitMutationViolation;

    uint256 internal constant TRACKED_POLICY_ID = 8901;
    address internal constant TRACKED_ACCOUNT = address(0xA901);
    address internal constant TRACKED_DESTINATION = address(0xB901);
    address internal constant TRACKED_INITIATOR = address(0xC901);

    constructor(LibOrganizationPolicyHarness harness_) {
        harness = harness_;
        modelPoliciesRoot = harness.getPoliciesRoot();
    }

    /**
     * @dev Stateful operation: update policy root through the library path.
     */
    function setPolicies(uint256 seed) external {
        bytes32 newRoot = keccak256(abi.encode(seed, address(this)));
        harness.setPoliciesViaLibrary(newRoot, "policy-invariant-root");
        modelPoliciesRoot = newRoot;
    }

    /**
     * @dev Stateful operation: exercise rate-limit updates and track monotonicity properties.
     */
    function exerciseRateLimit(uint96 usageRaw, uint96 limitRaw) external {
        uint256 usageAmount = uint256(usageRaw % 1000) + 1;
        uint256 intervalLimit = uint256(limitRaw % 1000) + 1;

        Policy memory policy = _buildRateLimitedPolicy(intervalLimit);

        bytes32 usageKey = harness.computeUsageKeyViaPolicyLibrary(
            TRACKED_POLICY_ID, policy, TRACKED_ACCOUNT, TRACKED_DESTINATION, TRACKED_INITIATOR
        );
        uint256 timeWindow = harness.computeTimeWindowViaPolicyLibrary(policy);
        uint256 beforeUsage = harness.getPolicyUsage(usageKey, timeWindow);

        bool withinLimit = harness.checkAndUpdateRateLimitViaPolicyLibrary(
            TRACKED_POLICY_ID, policy, TRACKED_ACCOUNT, TRACKED_DESTINATION, TRACKED_INITIATOR, usageAmount
        );

        uint256 afterUsage = harness.getPolicyUsage(usageKey, timeWindow);

        if (withinLimit && afterUsage < beforeUsage) {
            usageMonotonicViolation = true;
        }

        if (!withinLimit && afterUsage != beforeUsage) {
            exceededLimitMutationViolation = true;
        }
    }

    /**
     * @dev Builds a deterministic rate-limited policy for handler operations.
     */
    function _buildRateLimitedPolicy(uint256 intervalLimit) internal pure returns (Policy memory policy) {
        policy = Policy({
            config: PolicyConfig({
                transactionType: TransactionType.Any,
                anySourceAccount: true,
                anyFunction: true,
                destinationType: DestinationType.Any,
                approval: ApprovalConfig({
                    policyType: PolicyType.AutoApprove,
                    approverType: ApproverType.Member,
                    approverMember: address(0),
                    approverGroupId: 0,
                    approvalThreshold: 1
                }),
                initiator: InitiatorConfig({
                    anyInitiator: true,
                    initiatorType: ApproverType.Member,
                    initiatorMember: address(0),
                    initiatorGroupId: 0
                }),
                token: TokenFilter({
                    anyToken: true, tokenAddress: address(0), hasAmountThreshold: false, amountThreshold: 0
                }),
                rateLimit: RateLimitConfig({
                    limitType: RateLimitType.TimeInterval,
                    timeIntervalHours: 1,
                    timeIntervalLimit: intervalLimit,
                    initiatorScope: RateLimitScope.PerEntity,
                    sourceScope: RateLimitScope.PerEntity,
                    destinationScope: RateLimitScope.PerEntity
                })
            }),
            roots: PolicyRoots({
                sourceAccountsRoot: bytes32(0), customDestinationsRoot: bytes32(0), allowedFunctionsRoot: bytes32(0)
            })
        });
    }
}
