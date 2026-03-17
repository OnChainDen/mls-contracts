// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

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
        // Setup: configure a valid fixture for wrapper entry points return delegated-library results for representative
        // success cases.
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

        bytes memory transfer = _encodeErc20Transfer(address(0xBEEF), 11);
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

    /// @dev Verifies that wrapper approval checks fail closed for unauthorized signers and missing groups.
    function test_wrapperApprovals_failClosedOnUnauthorizedSignerAndMissingGroup_returnsFalse() public {
        // Setup: build member-approver fixture where signature is from a different org member.
        bytes32 messageHash = keccak256("lop-wrap-2-message");

        Policy memory memberPolicy = _buildBasePolicy();
        memberPolicy.config.approval.approverType = ApproverType.Member;
        memberPolicy.config.approval.approverMember = reviewer1;
        policyStateHarness.setMemberStatus(reviewer1, true);
        policyStateHarness.setMemberStatus(reviewer2, true);

        bytes memory unauthorizedSignature = _signHash(REVIEWER_PK_2, messageHash);
        // Call: evaluate approval validity for unauthorized signer payload.
        bool unauthorizedSignerValid =
            harness.areApprovalsValidViaLibrary(memberPolicy, unauthorizedSignature, messageHash);
        // Verify: assert unauthorized member signatures fail closed.
        assertFalse(unauthorizedSignerValid, "unauthorized signer should fail closed");

        // Setup: build group-approver fixture that points to a non-existent group id.
        Policy memory groupPolicy = _buildBasePolicy();
        groupPolicy.config.approval.approverType = ApproverType.Group;
        groupPolicy.config.approval.approverGroupId = 99_123;
        groupPolicy.config.approval.approvalThreshold = 1;
        bytes memory reviewerSignature = _signHash(REVIEWER_PK_1, messageHash);

        // Call: evaluate approval validity for non-existent approver group payload.
        bool missingGroupValid = harness.areApprovalsValidViaLibrary(groupPolicy, reviewerSignature, messageHash);
        // Verify: assert missing groups fail closed.
        assertFalse(missingGroupValid, "missing approver group should fail closed");
    }

    /// @dev Verifies that wrapper approval checks fail closed on duplicate or out-of-order signers.
    function test_wrapperApprovals_duplicateOrOutOfOrderSigners_returnsFalse() public {
        // Setup: configure a group-approval policy and prepare duplicate signatures from the same authorized signer.
        uint256 approverGroupId = 99_124;
        Policy memory policy = _buildBasePolicy();
        policy.config.approval.approverType = ApproverType.Group;
        policy.config.approval.approverGroupId = approverGroupId;
        policy.config.approval.approvalThreshold = 2;

        policyStateHarness.setGroupStatus(approverGroupId, true);
        policyStateHarness.setMemberStatus(reviewer1, true);
        policyStateHarness.setGroupMemberStatus(approverGroupId, reviewer1, true);

        bytes32 messageHash = keccak256("lop-wrap-2b-message");
        bytes memory signerSignature = _signHash(REVIEWER_PK_1, messageHash);
        bytes memory duplicateSignatures = abi.encodePacked(signerSignature, signerSignature);

        // Call: evaluate approval validity for duplicate-signer payload.
        bool approvalsValid = harness.areApprovalsValidViaLibrary(policy, duplicateSignatures, messageHash);
        // Verify: assert duplicate signer ordering fails closed.
        assertFalse(approvalsValid, "duplicate/out-of-order signers should fail closed");
    }

    /// @dev Verifies that wrapper approval checks fail closed on malformed signature payloads.
    function test_wrapperApprovals_malformedSignatures_returnsFalse() public {
        // Setup: build member-approver fixture with malformed packed signature bytes.
        Policy memory policy = _buildBasePolicy();
        policy.config.approval.approverType = ApproverType.Member;
        policy.config.approval.approverMember = reviewer1;
        policyStateHarness.setMemberStatus(reviewer1, true);

        bytes memory malformedSignatures = hex"01";
        bytes32 messageHash = keccak256("lop-wrap-3");
        // Call: evaluate approval validity for malformed signature bytes.
        bool approvalsValid = harness.areApprovalsValidViaLibrary(policy, malformedSignatures, messageHash);
        // Verify: assert malformed signature payloads fail closed.
        assertFalse(approvalsValid, "malformed signatures should fail closed");
    }

    /// @dev Verifies that `isInitiatorAuthorized` wrapper preserves delegated revert payloads.
    function test_wrapperIsInitiatorAuthorized_invalidInitiatorEnum_bubblesRevertData() public {
        // Setup: prepare invalid-enum calldata for wrapper and delegated-library paths.
        Policy memory policy = _buildBasePolicy();
        policy.config.initiator.anyInitiator = false;
        policyStateHarness.setMemberStatus(initiator1, true);

        bytes memory wrapperCallData = abi.encodeCall(harness.isInitiatorAuthorizedViaLibrary, (policy, initiator1));
        _setWord(wrapperCallData, 4 + 10 * 32, 2);

        bytes memory delegatedCallData =
            abi.encodeCall(harness.isInitiatorAuthorizedViaPolicyLibrary, (policy, initiator1));
        _setWord(delegatedCallData, 4 + 10 * 32, 2);

        // Call: execute low-level calls to capture revert payloads.
        (bool wrapperSuccess, bytes memory wrapperRevertData) = address(harness).call(wrapperCallData);
        (bool delegatedSuccess, bytes memory delegatedRevertData) = address(harness).call(delegatedCallData);

        // Verify: wrapper should revert and surface the same revert payload as the delegated path.
        assertFalse(wrapperSuccess, "wrapper call should revert for invalid initiator enum");
        assertFalse(delegatedSuccess, "delegated call should revert for invalid initiator enum");
        assertEq(wrapperRevertData, delegatedRevertData, "wrapper should bubble delegated revert data");
    }

    /// @dev Verifies that `getRequiredApprovals` wrapper preserves delegated revert payloads.
    function test_wrapperGetRequiredApprovals_invalidApproverEnum_bubblesRevertData() public {
        // Setup: prepare invalid-enum calldata for wrapper and delegated-library paths.
        Policy memory policy = _buildBasePolicy();

        bytes memory wrapperCallData = abi.encodeCall(harness.getRequiredApprovalsViaLibrary, (policy));
        _setWord(wrapperCallData, 4 + 5 * 32, 2);

        bytes memory delegatedCallData = abi.encodeCall(harness.getRequiredApprovalsViaPolicyLibrary, (policy));
        _setWord(delegatedCallData, 4 + 5 * 32, 2);

        // Call: execute low-level calls to capture revert payloads.
        (bool wrapperSuccess, bytes memory wrapperRevertData) = address(harness).call(wrapperCallData);
        (bool delegatedSuccess, bytes memory delegatedRevertData) = address(harness).call(delegatedCallData);

        // Verify: wrapper should revert and surface the same revert payload as the delegated path.
        assertFalse(wrapperSuccess, "wrapper call should revert for invalid approver enum");
        assertFalse(delegatedSuccess, "delegated call should revert for invalid approver enum");
        assertEq(wrapperRevertData, delegatedRevertData, "wrapper should bubble delegated revert data");
    }

    /// @dev Verifies that `checkAndUpdateRateLimit` wrapper preserves delegated revert payloads.
    function test_wrapperCheckAndUpdateRateLimit_invalidRateLimitEnum_bubblesRevertData() public {
        // Setup: prepare invalid-enum calldata for wrapper and delegated-library paths.
        uint256 policyId = 4003;
        Policy memory policy = _buildBasePolicy();
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 24;
        policy.config.rateLimit.timeIntervalLimit = 10;

        bytes memory wrapperCallData = abi.encodeCall(
            harness.checkAndUpdateRateLimitViaLibrary,
            (policyId, policy, address(0xB101), address(0xB102), address(0xB103), 1)
        );
        _setWord(wrapperCallData, 4 + 32 + 17 * 32, 2);

        bytes memory delegatedCallData = abi.encodeCall(
            harness.checkAndUpdateRateLimitViaPolicyLibrary,
            (policyId, policy, address(0xB101), address(0xB102), address(0xB103), 1)
        );
        _setWord(delegatedCallData, 4 + 32 + 17 * 32, 2);

        // Call: execute low-level calls to capture revert payloads.
        (bool wrapperSuccess, bytes memory wrapperRevertData) = address(harness).call(wrapperCallData);
        (bool delegatedSuccess, bytes memory delegatedRevertData) = address(harness).call(delegatedCallData);

        // Verify: wrapper should revert and surface the same revert payload as the delegated path.
        assertFalse(wrapperSuccess, "wrapper call should revert for invalid rate-limit enum");
        assertFalse(delegatedSuccess, "delegated call should revert for invalid rate-limit enum");
        assertEq(wrapperRevertData, delegatedRevertData, "wrapper should bubble delegated revert data");
    }

    /// @dev Verifies that `checkAndUpdateRateLimit` mutates usage only when delegated result is true.
    function test_wrapperCheckAndUpdateRateLimit_mutatesOnlyOnSuccess() public {
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for `checkAndUpdateRateLimit`
        // mutates usage only when delegated result is true.
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
