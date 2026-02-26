// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationGroups} from "interfaces/organization/IOrganizationGroups.sol";
import {IOrganizationPolicy} from "interfaces/organization/IOrganizationPolicy.sol";
import {SignatureUtils} from "libraries/SignatureUtils.sol";
import {LibOrganizationPolicy} from "organization/libraries/LibOrganizationPolicy.sol";
import {
    LibOrganizationPolicySuiteBase
} from "test/organization/libraries/LibOrganizationPolicy/LibOrganizationPolicySuiteBase.sol";
import {ApproverType, Policy, RateLimitType} from "types/PolicyTypes.sol";

/**
 * @dev Unit tests for `LibOrganizationPolicy` wrapper passthrough behavior.
 */
contract LibOrganizationPolicyWrappersTest is LibOrganizationPolicySuiteBase {
    /// @dev Verifies that wrapper entry points return delegated-library results for representative success cases.
    function test_wrapperFunctions_delegateAndReturnSameResults() public {
        // Setup: configure a valid fixture for wrapper entry points return delegated-library results for representative success cases.
        Policy memory policy = _buildBasePolicy();
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 24;
        policy.config.rateLimit.timeIntervalLimit = 100;
        policy.config.initiator.anyInitiator = false;
        policy.config.initiator.initiatorMember = initiator1;
        policy.config.approval.approverType = ApproverType.Member;
        policy.config.approval.approverMember = reviewer1;

        policyStateHarness.setMemberStatus(initiator1, true);
        policyStateHarness.setMemberStatus(reviewer1, true);

        bytes32 messageHash = keccak256("lop-wrap-1-message");
        bytes memory signature = _signHash(REVIEWER_PK_1, messageHash);

        // Verify: assert the expected success result and state updates.
        assertEq(
        // Call: execute `areApprovalsValidViaLibrary` with the happy-path payload.
            harness.areApprovalsValidViaLibrary(policy, signature, messageHash),
            harness.areApprovalsValidViaPolicyLibrary(policy, signature, messageHash),
            "approval wrapper mismatch"
        );
        assertEq(
            harness.computeTimeWindowViaLibrary(policy),
            harness.computeTimeWindowViaPolicyLibrary(policy),
            "time-window wrapper mismatch"
        );
        assertEq(
            harness.isInitiatorAuthorizedViaLibrary(policy, initiator1),
            harness.isInitiatorAuthorizedViaPolicyLibrary(policy, initiator1),
            "initiator wrapper mismatch"
        );
        assertEq(
            harness.getRequiredApprovalsViaLibrary(policy),
            harness.getRequiredApprovalsViaPolicyLibrary(policy),
            "required-approvals wrapper mismatch"
        );

        bytes memory transfer = _encodeERC20Transfer(address(0xBEEF), 11);
        assertEq(
            harness.getActualDestinationViaLibrary(address(0xCAFE), transfer, 0),
            harness.getActualDestinationViaPolicyLibrary(address(0xCAFE), transfer, 0),
            "destination wrapper mismatch"
        );

        bytes32 keyViaWrapper = harness.computeUsageKeyViaLibrary(4001, policy, address(0x1), address(0x2), initiator1);
        bytes32 keyViaPolicyLib =
            harness.computeUsageKeyViaPolicyLibrary(4001, policy, address(0x1), address(0x2), initiator1);
        assertEq(keyViaWrapper, keyViaPolicyLib, "usage-key wrapper mismatch");

        uint256 currentWindow = harness.computeTimeWindowViaLibrary(policy);
        harness.setPolicyUsage(keyViaWrapper, currentWindow, 33);
        assertEq(
            harness.getCurrentUsageViaLibrary(4001, policy, address(0x1), address(0x2), initiator1),
            harness.getCurrentUsageViaPolicyLibrary(4001, policy, address(0x1), address(0x2), initiator1),
            "current-usage wrapper mismatch"
        );
    }

    /// @dev Verifies that wrapper bubbles delegated custom errors unchanged.
    function test_wrapperApprovals_bubblesDelegatedCustomErrors() public {
        // Setup: assemble inputs expected to hit the guarded failure path for wrapper bubbles delegated custom errors unchanged.
        bytes32 messageHash = keccak256("lop-wrap-2-message");

        // Unauthorized signer path.
        Policy memory memberPolicy = _buildBasePolicy();
        memberPolicy.config.approval.approverType = ApproverType.Member;
        memberPolicy.config.approval.approverMember = reviewer1;
        policyStateHarness.setMemberStatus(reviewer1, true);
        policyStateHarness.setMemberStatus(reviewer2, true);

        bytes memory unauthorizedSignature = _signHash(REVIEWER_PK_2, messageHash);
        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationPolicy.UnauthorizedApprovalSigner.selector, reviewer2));
        // Call: invoke `areApprovalsValidViaLibrary` with the failing payload to exercise the revert branch.
        harness.areApprovalsValidViaLibrary(memberPolicy, unauthorizedSignature, messageHash);

        // Group-does-not-exist path.
        Policy memory groupPolicy = _buildBasePolicy();
        groupPolicy.config.approval.approverType = ApproverType.Group;
        groupPolicy.config.approval.approverGroupId = 99_123;
        groupPolicy.config.approval.approvalThreshold = 1;
        vm.expectRevert(abi.encodeWithSelector(IOrganizationGroups.GroupDoesNotExist.selector, 99_123));
        harness.areApprovalsValidViaLibrary(groupPolicy, _signHash(REVIEWER_PK_1, messageHash), messageHash);
    }

    /// @dev Verifies that wrapper bubbles delegated signature-decoding errors unchanged.
    function test_wrapperApprovals_bubblesSignatureRecoveryErrorsUnchanged() public {
        // Setup: assemble inputs expected to hit the guarded failure path for wrapper bubbles delegated signature-decoding errors unchanged.
        Policy memory policy = _buildBasePolicy();
        policy.config.approval.approverType = ApproverType.Member;
        policy.config.approval.approverMember = reviewer1;
        policyStateHarness.setMemberStatus(reviewer1, true);

        bytes memory malformedSignatures = hex"01";
        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert(SignatureUtils.SignatureRecoveryFailed.selector);
        // Call: invoke `areApprovalsValidViaLibrary` with the failing payload to exercise the revert branch.
        harness.areApprovalsValidViaLibrary(policy, malformedSignatures, keccak256("lop-wrap-3"));
    }

    /// @dev Verifies that `checkAndUpdateRateLimit` mutates usage only when delegated result is true.
    function test_wrapperCheckAndUpdateRateLimit_mutatesOnlyOnSuccess() public {
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for `checkAndUpdateRateLimit` mutates usage only when delegated result is true.
        Policy memory policy = _buildBasePolicy();
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 24;
        policy.config.rateLimit.timeIntervalLimit = 10;

        uint256 policyId = 4002;
        address account = address(0xB001);
        address destination = address(0xB002);
        address initiator = address(0xB003);
        bytes32 usageKey = LibOrganizationPolicy.computeUsageKey(policyId, policy, account, destination, initiator);
        uint256 window = LibOrganizationPolicy.computeTimeWindow(policy);

        // Call: run `checkAndUpdateRateLimitViaLibrary` across the prepared variants.
        bool first = harness.checkAndUpdateRateLimitViaLibrary(policyId, policy, account, destination, initiator, 7);
        // Verify: assert each variant returns the expected branch outcome.
        assertTrue(first, "first update should be within limit");
        assertEq(harness.getPolicyUsage(usageKey, window), 7, "usage should update on success");

        bool second = harness.checkAndUpdateRateLimitViaLibrary(policyId, policy, account, destination, initiator, 5);
        assertFalse(second, "second update should exceed limit");
        assertEq(harness.getPolicyUsage(usageKey, window), 7, "usage should remain unchanged on failure");
    }
}
