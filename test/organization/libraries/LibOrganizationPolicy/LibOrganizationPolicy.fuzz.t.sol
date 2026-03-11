// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibOrganizationPolicySuiteBase
} from "test/organization/libraries/LibOrganizationPolicy/LibOrganizationPolicySuiteBase.sol";
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

    /**
     * @dev Verifies `_computePolicyLeaf` is deterministic, double-hashed, and sensitive to every policy field.
     * @param rawPolicyId Raw policy id used to derive a bounded non-zero policy id
     * @param approverMember Address used to seed the approval-member field
     * @param initiatorMember Address used to seed the initiator-member field
     * @param tokenAddress Address used to seed the token filter field
     * @param sourceAccountsRoot Root used to seed the source-accounts merkle root
     * @param customDestinationsRoot Root used to seed the custom-destinations merkle root
     * @param allowedFunctionsRoot Root used to seed the allowed-functions merkle root
     * @param timeIntervalHoursRaw Raw value used to derive a bounded non-zero interval length
     * @param timeIntervalLimitRaw Raw value used to derive a bounded non-zero rate-limit ceiling
     * @param amountThresholdRaw Raw value used to derive a bounded non-zero token amount threshold
     */
    function testFuzz_FLOP_PLEAF_62_computePolicyLeaf_isDeterministicDoubleHashedAndSensitiveToEveryField(
        uint256 rawPolicyId,
        address approverMember,
        address initiatorMember,
        address tokenAddress,
        bytes32 sourceAccountsRoot,
        bytes32 customDestinationsRoot,
        bytes32 allowedFunctionsRoot,
        uint16 timeIntervalHoursRaw,
        uint96 timeIntervalLimitRaw,
        uint256 amountThresholdRaw
    ) public view {
        // Setup: build one non-trivial policy that assigns explicit values to every field in the policy struct.
        vm.assume(approverMember != address(0));
        vm.assume(initiatorMember != address(0));
        vm.assume(tokenAddress != address(0));

        uint256 policyId = bound(rawPolicyId, 1, type(uint96).max - 1);
        uint16 timeIntervalHours = uint16(bound(uint256(timeIntervalHoursRaw), 1, type(uint16).max - 1));
        uint256 timeIntervalLimit = bound(uint256(timeIntervalLimitRaw), 1, type(uint96).max - 1);
        uint256 amountThreshold = bound(amountThresholdRaw, 1, type(uint96).max - 1);

        Policy memory policy = _buildBasePolicy();
        policy.config.transactionType = TransactionType.ContractInteractions;
        policy.config.anySourceAccount = false;
        policy.config.anyFunction = false;
        policy.config.destinationType = DestinationType.CustomList;
        policy.config.approval.policyType = PolicyType.RequireManualApproval;
        policy.config.approval.approverType = ApproverType.Group;
        policy.config.approval.approverMember = approverMember;
        policy.config.approval.approverGroupId = 11;
        policy.config.approval.approvalThreshold = 2;
        policy.config.initiator.anyInitiator = false;
        policy.config.initiator.initiatorType = ApproverType.Group;
        policy.config.initiator.initiatorMember = initiatorMember;
        policy.config.initiator.initiatorGroupId = 22;
        policy.config.token.anyToken = false;
        policy.config.token.tokenAddress = tokenAddress;
        policy.config.token.hasAmountThreshold = true;
        policy.config.token.amountThreshold = amountThreshold;
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = timeIntervalHours;
        policy.config.rateLimit.timeIntervalLimit = timeIntervalLimit;
        policy.config.rateLimit.initiatorScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.sourceScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.destinationScope = RateLimitScope.PerEntity;
        policy.roots.sourceAccountsRoot = sourceAccountsRoot;
        policy.roots.customDestinationsRoot = customDestinationsRoot;
        policy.roots.allowedFunctionsRoot = allowedFunctionsRoot;

        bytes32 baseLeaf = harness.computePolicyLeafViaLibrary(policyId, policy);

        // Verify: identical inputs should remain deterministic and match the required double-hash construction.
        assertEq(baseLeaf, harness.computePolicyLeafViaLibrary(policyId, policy), "policy leaf should be deterministic");
        assertEq(
            baseLeaf,
            keccak256(bytes.concat(keccak256(abi.encode(policyId, policy)))),
            "policy leaf should use the double-hash construction"
        );
        assertTrue(baseLeaf != keccak256(abi.encode(policyId, policy)), "policy leaf should not use single hashing");

        Policy memory mutated = policy;

        // Verify: changing any single leaf input should change the resulting policy leaf.
        assertTrue(
            harness.computePolicyLeafViaLibrary(policyId + 1, policy) != baseLeaf,
            "policy leaf should bind the policy id"
        );

        mutated.config.transactionType = TransactionType.Any;
        _assertMutatedLeafDiffers(policyId, mutated, baseLeaf, "transactionType should affect the leaf");

        mutated = policy;
        mutated.config.anySourceAccount = true;
        _assertMutatedLeafDiffers(policyId, mutated, baseLeaf, "anySourceAccount should affect the leaf");

        mutated = policy;
        mutated.config.anyFunction = true;
        _assertMutatedLeafDiffers(policyId, mutated, baseLeaf, "anyFunction should affect the leaf");

        mutated = policy;
        mutated.config.destinationType = DestinationType.Any;
        _assertMutatedLeafDiffers(policyId, mutated, baseLeaf, "destinationType should affect the leaf");

        mutated = policy;
        mutated.config.approval.policyType = PolicyType.AutoApprove;
        _assertMutatedLeafDiffers(policyId, mutated, baseLeaf, "approval.policyType should affect the leaf");

        mutated = policy;
        mutated.config.approval.approverType = ApproverType.Member;
        _assertMutatedLeafDiffers(policyId, mutated, baseLeaf, "approval.approverType should affect the leaf");

        mutated = policy;
        mutated.config.approval.approverMember = address(uint160(approverMember) ^ uint160(1));
        _assertMutatedLeafDiffers(policyId, mutated, baseLeaf, "approval.approverMember should affect the leaf");

        mutated = policy;
        mutated.config.approval.approverGroupId = 12;
        _assertMutatedLeafDiffers(policyId, mutated, baseLeaf, "approval.approverGroupId should affect the leaf");

        mutated = policy;
        mutated.config.approval.approvalThreshold = 3;
        _assertMutatedLeafDiffers(policyId, mutated, baseLeaf, "approval.approvalThreshold should affect the leaf");

        mutated = policy;
        mutated.config.initiator.anyInitiator = true;
        _assertMutatedLeafDiffers(policyId, mutated, baseLeaf, "initiator.anyInitiator should affect the leaf");

        mutated = policy;
        mutated.config.initiator.initiatorType = ApproverType.Member;
        _assertMutatedLeafDiffers(policyId, mutated, baseLeaf, "initiator.initiatorType should affect the leaf");

        mutated = policy;
        mutated.config.initiator.initiatorMember = address(uint160(initiatorMember) ^ uint160(1));
        _assertMutatedLeafDiffers(policyId, mutated, baseLeaf, "initiator.initiatorMember should affect the leaf");

        mutated = policy;
        mutated.config.initiator.initiatorGroupId = 23;
        _assertMutatedLeafDiffers(policyId, mutated, baseLeaf, "initiator.initiatorGroupId should affect the leaf");

        mutated = policy;
        mutated.config.token.anyToken = true;
        _assertMutatedLeafDiffers(policyId, mutated, baseLeaf, "token.anyToken should affect the leaf");

        mutated = policy;
        mutated.config.token.tokenAddress = address(uint160(tokenAddress) ^ uint160(1));
        _assertMutatedLeafDiffers(policyId, mutated, baseLeaf, "token.tokenAddress should affect the leaf");

        mutated = policy;
        mutated.config.token.hasAmountThreshold = false;
        _assertMutatedLeafDiffers(policyId, mutated, baseLeaf, "token.hasAmountThreshold should affect the leaf");

        mutated = policy;
        mutated.config.token.amountThreshold = amountThreshold + 1;
        _assertMutatedLeafDiffers(policyId, mutated, baseLeaf, "token.amountThreshold should affect the leaf");

        mutated = policy;
        mutated.config.rateLimit.limitType = RateLimitType.None;
        _assertMutatedLeafDiffers(policyId, mutated, baseLeaf, "rateLimit.limitType should affect the leaf");

        mutated = policy;
        mutated.config.rateLimit.timeIntervalHours = timeIntervalHours + 1;
        _assertMutatedLeafDiffers(policyId, mutated, baseLeaf, "rateLimit.timeIntervalHours should affect the leaf");

        mutated = policy;
        mutated.config.rateLimit.timeIntervalLimit = timeIntervalLimit + 1;
        _assertMutatedLeafDiffers(policyId, mutated, baseLeaf, "rateLimit.timeIntervalLimit should affect the leaf");

        mutated = policy;
        mutated.config.rateLimit.initiatorScope = RateLimitScope.AcrossAll;
        _assertMutatedLeafDiffers(policyId, mutated, baseLeaf, "rateLimit.initiatorScope should affect the leaf");

        mutated = policy;
        mutated.config.rateLimit.sourceScope = RateLimitScope.AcrossAll;
        _assertMutatedLeafDiffers(policyId, mutated, baseLeaf, "rateLimit.sourceScope should affect the leaf");

        mutated = policy;
        mutated.config.rateLimit.destinationScope = RateLimitScope.AcrossAll;
        _assertMutatedLeafDiffers(policyId, mutated, baseLeaf, "rateLimit.destinationScope should affect the leaf");

        mutated = policy;
        mutated.roots.sourceAccountsRoot = sourceAccountsRoot ^ bytes32(uint256(1));
        _assertMutatedLeafDiffers(policyId, mutated, baseLeaf, "roots.sourceAccountsRoot should affect the leaf");

        mutated = policy;
        mutated.roots.customDestinationsRoot = customDestinationsRoot ^ bytes32(uint256(1));
        _assertMutatedLeafDiffers(policyId, mutated, baseLeaf, "roots.customDestinationsRoot should affect the leaf");

        mutated = policy;
        mutated.roots.allowedFunctionsRoot = allowedFunctionsRoot ^ bytes32(uint256(1));
        _assertMutatedLeafDiffers(policyId, mutated, baseLeaf, "roots.allowedFunctionsRoot should affect the leaf");
    }

    /**
     * @dev Asserts that one mutated `(policyId, policy)` tuple produces a different policy leaf than the baseline.
     * @param policyId Policy id associated with the mutated policy
     * @param mutatedPolicy Mutated policy struct whose leaf should differ from the baseline
     * @param baseLeaf Baseline policy leaf used for comparison
     * @param reason Message used when the mutated leaf does not differ as expected
     */
    function _assertMutatedLeafDiffers(
        uint256 policyId,
        Policy memory mutatedPolicy,
        bytes32 baseLeaf,
        string memory reason
    ) internal view {
        // Verify: each single-field mutation should change the resulting policy leaf.
        assertTrue(harness.computePolicyLeafViaLibrary(policyId, mutatedPolicy) != baseLeaf, reason);
    }
}
