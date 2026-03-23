// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationPolicy} from "interfaces/organization/IOrganizationPolicy.sol";
import {
    OrganizationPolicyBaseSuiteBase
} from "test/organization/base/OrganizationPolicyBase/OrganizationPolicyBaseSuiteBase.sol";
import {Policy, RateLimitScope, RateLimitType} from "types/PolicyTypes.sol";

/**
 * @dev Unit tests for `OrganizationPolicyBase.getPolicyUsage` behavior.
 */
contract OrganizationPolicyBaseGetPolicyUsageTest is OrganizationPolicyBaseSuiteBase {
    /// @dev Builds a one-policy root, stores it, and returns the matching proof.
    function _setSinglePolicyRoot(uint256 policyId, Policy memory policy) internal returns (bytes32[] memory proof) {
        // Murky's helper does not generate roots for single-leaf trees.
        // Use a deterministic companion leaf so all non-single-leaf tests can build proofs reliably.
        Policy memory companionPolicy = _buildBasePolicy();
        companionPolicy.config.anyFunction = !policy.config.anyFunction;

        Policy[] memory policies = new Policy[](2);
        policies[0] = policy;
        policies[1] = companionPolicy;

        uint256[] memory policyIds = buildUint256Array(policyId, policyId + 1);
        (bytes32 root, bytes32[] memory builtProof) = _buildPolicyRootAndProof(policyIds, policies, 0);
        policyStateHarness.setPoliciesRoot(root);
        return builtProof;
    }

    /// @dev Computes the same usage-key derivation used by rate-limit helpers.
    function _computeUsageKey(
        uint256 policyId,
        Policy memory policy,
        address account,
        address destination,
        address initiator
    ) internal pure returns (bytes32) {
        address scopedAccount = policy.config.rateLimit.sourceScope == RateLimitScope.PerEntity ? account : address(0);
        address scopedDestination =
            policy.config.rateLimit.destinationScope == RateLimitScope.PerEntity ? destination : address(0);
        address scopedInitiator =
            policy.config.rateLimit.initiatorScope == RateLimitScope.PerEntity ? initiator : address(0);

        return keccak256(
            abi.encode(
                policyId,
                policy.config.rateLimit.anchorTimestamp,
                policy.config.rateLimit.timeIntervalHours,
                policy.config.rateLimit.sourceScope,
                scopedAccount,
                policy.config.rateLimit.destinationScope,
                scopedDestination,
                policy.config.rateLimit.initiatorScope,
                scopedInitiator
            )
        );
    }

    /// @dev Builds a baseline time-interval-limited policy.
    function _buildTimeIntervalPolicy() internal view returns (Policy memory policy) {
        policy = _buildBasePolicy();
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = 1_000_000;
    }

    /// @dev Verifies that valid proof returns current usage from rate-limit storage.
    function test_getPolicyUsage_validProof_returnsCurrentRateLimitUsage() public {
        // Setup: configure a valid fixture for valid proof returns current usage from rate-limit storage.
        uint256 policyId = 3001;
        Policy memory policy = _buildTimeIntervalPolicy();
        bytes32[] memory policyProof = _setSinglePolicyRoot(policyId, policy);

        address account = address(0xA1001);
        address destination = address(0xD1001);
        address initiator = address(0xC1001);
        bytes32 usageKey = _computeUsageKey(policyId, policy, account, destination, initiator);
        uint256 timeWindow = block.timestamp / 3600;

        policyStateHarness.setPolicyUsage(usageKey, timeWindow, 77);

        // Call: execute `getPolicyUsage` with the happy-path payload.
        uint256 actualUsage = harness.getPolicyUsage({
            policyId: policyId,
            policy: policy,
            account: account,
            destination: destination,
            initiator: initiator,
            policyProof: policyProof
        });

        // Verify: assert the expected success result and state updates.
        assertEq(actualUsage, 77, "usage should match seeded storage value");
    }

    /// @dev Verifies that invalid policy proof reverts `PolicyVerificationFailed(policyId)`.
    function test_getPolicyUsage_invalidProof_revertsPolicyVerificationFailed() public {
        // Setup: assemble inputs expected to hit the guarded failure path for invalid policy proof reverts
        // `PolicyVerificationFailed(policyId)`.
        uint256 policyId = 3002;
        Policy memory policy = _buildBasePolicy();
        _setSinglePolicyRoot(policyId, policy);

        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = keccak256("invalid-proof-node");

        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationPolicy.PolicyVerificationFailed.selector, policyId));
        // Call: invoke `getPolicyUsage` with the failing payload to exercise the revert branch.
        harness.getPolicyUsage({
            policyId: policyId,
            policy: policy,
            account: address(0xA1002),
            destination: address(0xD1002),
            initiator: address(0xC1002),
            policyProof: invalidProof
        });
    }

    /// @dev Verifies that wrong `policyId` for an otherwise-valid proof reverts `PolicyVerificationFailed`.
    function test_getPolicyUsage_wrongPolicyIdForValidProof_revertsPolicyVerificationFailed() public {
        // Setup: assemble inputs expected to hit the guarded failure path for wrong `policyId` for an otherwise-valid
        // proof reverts `PolicyVerificationFailed`.
        uint256 signedPolicyId = 3003;
        uint256 queriedPolicyId = 3004;
        Policy memory policy = _buildBasePolicy();
        bytes32[] memory proof = _setSinglePolicyRoot(signedPolicyId, policy);

        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationPolicy.PolicyVerificationFailed.selector, queriedPolicyId));
        // Call: invoke `getPolicyUsage` with the failing payload to exercise the revert branch.
        harness.getPolicyUsage({
            policyId: queriedPolicyId,
            policy: policy,
            account: address(0xA1003),
            destination: address(0xD1003),
            initiator: address(0xC1003),
            policyProof: proof
        });
    }

    /// @dev Verifies that non-empty policy is rejected when `policiesRoot == 0`.
    function test_getPolicyUsage_zeroPoliciesRoot_rejectsPolicy() public {
        // Setup: assemble inputs expected to hit the guarded failure path for non-empty policy is rejected when
        // `policiesRoot == 0`.
        uint256 policyId = 3005;
        Policy memory policy = _buildBasePolicy();
        bytes32[] memory emptyProof = new bytes32[](0);

        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationPolicy.PolicyVerificationFailed.selector, policyId));
        // Call: invoke `getPolicyUsage` with the failing payload to exercise the revert branch.
        harness.getPolicyUsage({
            policyId: policyId,
            policy: policy,
            account: address(0xA1004),
            destination: address(0xD1004),
            initiator: address(0xC1004),
            policyProof: emptyProof
        });
    }

    /// @dev Verifies that policy without active rate limit returns zero usage.
    function test_getPolicyUsage_policyWithoutActiveRateLimit_returnsZero() public {
        // Setup: configure a valid fixture for policy without active rate limit returns zero usage.
        uint256 policyId = 3006;
        Policy memory policy = _buildBasePolicy();
        bytes32[] memory proof = _setSinglePolicyRoot(policyId, policy);

        // Call: execute `getPolicyUsage` with the happy-path payload.
        uint256 usage = harness.getPolicyUsage({
            policyId: policyId,
            policy: policy,
            account: address(0xA1005),
            destination: address(0xD1005),
            initiator: address(0xC1005),
            policyProof: proof
        });

        // Verify: assert the expected success result and state updates.
        assertEq(usage, 0, "usage should be zero when rate limit is disabled");
    }

    /// @dev Verifies that usage is scoped by account/destination/initiator configuration.
    function test_getPolicyUsage_usageKey_scopedByAccountDestinationAndInitiator() public {
        // Setup: configure a valid fixture for usage is scoped by account/destination/initiator configuration.
        uint256 policyId = 3007;
        Policy memory policy = _buildTimeIntervalPolicy();
        policy.config.rateLimit.sourceScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.destinationScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.initiatorScope = RateLimitScope.PerEntity;

        bytes32[] memory proof = _setSinglePolicyRoot(policyId, policy);

        address account = address(0xA1006);
        address destination = address(0xD1006);
        address initiator = address(0xC1006);

        bytes32 usageKey = _computeUsageKey(policyId, policy, account, destination, initiator);
        uint256 timeWindow = block.timestamp / 3600;
        policyStateHarness.setPolicyUsage(usageKey, timeWindow, 91);

        // Call: execute `getPolicyUsage` with the happy-path payload.
        uint256 exactTupleUsage = harness.getPolicyUsage({
            policyId: policyId,
            policy: policy,
            account: account,
            destination: destination,
            initiator: initiator,
            policyProof: proof
        });
        // Verify: assert the expected success result and state updates.
        assertEq(exactTupleUsage, 91, "exact tuple should read the seeded usage");

        uint256 accountShiftedUsage = harness.getPolicyUsage({
            policyId: policyId,
            policy: policy,
            account: address(0xA1007),
            destination: destination,
            initiator: initiator,
            policyProof: proof
        });
        assertEq(accountShiftedUsage, 0, "different account should map to a different usage key");

        uint256 destinationShiftedUsage = harness.getPolicyUsage({
            policyId: policyId,
            policy: policy,
            account: account,
            destination: address(0xD1007),
            initiator: initiator,
            policyProof: proof
        });
        assertEq(destinationShiftedUsage, 0, "different destination should map to a different usage key");

        uint256 initiatorShiftedUsage = harness.getPolicyUsage({
            policyId: policyId,
            policy: policy,
            account: account,
            destination: destination,
            initiator: address(0xC1007),
            policyProof: proof
        });
        assertEq(initiatorShiftedUsage, 0, "different initiator should map to a different usage key");
    }

    /// @dev Verifies that usage from the prior window is not counted in the current window.
    function test_getPolicyUsage_windowRollover_oldWindowUsageNotCounted() public {
        // Setup: configure a valid fixture for usage from the prior window is not counted in the current window.
        vm.warp(100 hours);

        uint256 policyId = 3008;
        Policy memory policy = _buildTimeIntervalPolicy();
        bytes32[] memory proof = _setSinglePolicyRoot(policyId, policy);

        address account = address(0xA1008);
        address destination = address(0xD1008);
        address initiator = address(0xC1008);
        bytes32 usageKey = _computeUsageKey(policyId, policy, account, destination, initiator);

        uint256 currentWindow = block.timestamp / 3600;
        policyStateHarness.setPolicyUsage(usageKey, currentWindow - 1, 123);

        // Call: execute `getPolicyUsage` with the happy-path payload.
        uint256 currentUsage = harness.getPolicyUsage({
            policyId: policyId,
            policy: policy,
            account: account,
            destination: destination,
            initiator: initiator,
            policyProof: proof
        });

        // Verify: assert the expected success result and state updates.
        assertEq(currentUsage, 0, "old window usage should not be counted in the current window");
    }

    /// @dev Verifies that `getPolicyUsage` is view-only and does not mutate usage storage.
    function test_getPolicyUsage_viewCall_doesNotMutateUsageStorage() public {
        // Setup: configure a valid fixture for `getPolicyUsage` is view-only and does not mutate usage storage.
        uint256 policyId = 3009;
        Policy memory policy = _buildTimeIntervalPolicy();
        bytes32[] memory proof = _setSinglePolicyRoot(policyId, policy);

        address account = address(0xA1009);
        address destination = address(0xD1009);
        address initiator = address(0xC1009);
        bytes32 usageKey = _computeUsageKey(policyId, policy, account, destination, initiator);
        uint256 timeWindow = block.timestamp / 3600;

        policyStateHarness.setPolicyUsage(usageKey, timeWindow, 33);
        uint256 usageBefore = policyStateHarness.getPolicyUsage(usageKey, timeWindow);

        // Call: execute `getPolicyUsage` with the happy-path payload.
        uint256 viewedUsage = harness.getPolicyUsage({
            policyId: policyId,
            policy: policy,
            account: account,
            destination: destination,
            initiator: initiator,
            policyProof: proof
        });
        uint256 usageAfter = policyStateHarness.getPolicyUsage(usageKey, timeWindow);

        // Verify: assert the expected success result and state updates.
        assertEq(viewedUsage, 33, "view should read seeded usage");
        assertEq(usageAfter, usageBefore, "view call must not mutate usage storage");
    }

    /// @dev Verifies that root-rotation guard: stale proof fails after root update, fresh proof succeeds.
    function test_getPolicyUsage_rootRotation_staleProofRejectedFreshProofAccepted() public {
        // Setup: assemble inputs expected to hit the guarded failure path for root-rotation guard: stale proof fails
        // after root update, fresh proof succeeds.
        uint256 policyId = 3010;

        Policy memory policyR1 = _buildBasePolicy();
        bytes32[] memory proofR1 = _setSinglePolicyRoot(policyId, policyR1);
        bytes32 rootR1 = policyStateHarness.getPoliciesRoot();

        Policy memory policyR2 = _buildBasePolicy();
        policyR2.config.anyFunction = false;
        bytes32[] memory proofR2 = _setSinglePolicyRoot(policyId, policyR2);
        bytes32 rootR2 = policyStateHarness.getPoliciesRoot();

        policyStateHarness.setPoliciesRoot(rootR1);

        // Call: invoke `getPolicyUsage` with the failing payload to exercise the revert branch.
        uint256 usageWithR1 = harness.getPolicyUsage({
            policyId: policyId,
            policy: policyR1,
            account: address(0xA1010),
            destination: address(0xD1010),
            initiator: address(0xC1010),
            policyProof: proofR1
        });
        // Verify: assert that the revert reason matches the policy guard under test.
        assertEq(usageWithR1, 0, "proof should succeed under root R1");

        policyStateHarness.setPoliciesRoot(rootR2);

        vm.expectRevert(abi.encodeWithSelector(IOrganizationPolicy.PolicyVerificationFailed.selector, policyId));
        harness.getPolicyUsage({
            policyId: policyId,
            policy: policyR1,
            account: address(0xA1010),
            destination: address(0xD1010),
            initiator: address(0xC1010),
            policyProof: proofR1
        });

        uint256 usageWithR2 = harness.getPolicyUsage({
            policyId: policyId,
            policy: policyR2,
            account: address(0xA1010),
            destination: address(0xD1010),
            initiator: address(0xC1010),
            policyProof: proofR2
        });
        assertEq(usageWithR2, 0, "fresh proof should succeed under root R2");
    }
}
