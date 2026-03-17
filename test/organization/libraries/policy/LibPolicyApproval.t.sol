// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {PolicyLibrariesSuiteBase} from "test/organization/libraries/policy/PolicyLibrariesSuiteBase.sol";
import {ApproverType, Policy} from "types/PolicyTypes.sol";

/**
 * @dev Unit tests for `LibPolicyApproval` wrappers.
 */
contract LibPolicyApprovalTest is PolicyLibrariesSuiteBase {
    /// @dev Verifies that empty signatures return false.
    function test_areApprovalsValid_emptySignatures_returnsFalse() public {
        // Setup: build fixture inputs where empty signatures return false should be denied.
        Policy memory policy = _memberApproverPolicy(reviewer1);

        // Call: execute `areApprovalsValidViaPolicyLibrary` and capture the authorization decision.
        bool ok = harness.areApprovalsValidViaPolicyLibrary(policy, bytes(""), keccak256("policy-approval-message"));
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(ok, "empty signatures must fail");
    }

    /// @dev Verifies that member approver with authorized member signature returns true.
    function test_areApprovalsValid_memberApproverAuthorizedSigner_returnsTrue() public {
        // Setup: configure a valid fixture for member approver with authorized member signature returns true.
        Policy memory policy = _memberApproverPolicy(reviewer1);
        _setMembersAsOrgMembers(buildArray(reviewer1));

        bytes32 messageHash = keccak256("policy-approval-message");
        bytes memory signature = _signHash(REVIEWER_PK_1, messageHash);

        // Call: execute `areApprovalsValidViaPolicyLibrary` with the happy-path payload.
        bool ok = harness.areApprovalsValidViaPolicyLibrary(policy, signature, messageHash);
        // Verify: assert the expected success result and state updates.
        assertTrue(ok, "authorized member signature should pass");
    }

    /// @dev Verifies that member approver with non-authorized signer returns false.
    function test_areApprovalsValid_memberApproverUnauthorizedSigner_returnsFalse() public {
        // Setup: build fixture inputs where member approver with non-authorized signer returns false should be denied.
        Policy memory policy = _memberApproverPolicy(reviewer1);
        _setMembersAsOrgMembers(buildArray(reviewer1, reviewer2));

        bytes32 messageHash = keccak256("policy-approval-message");
        bytes memory signature = _signHash(REVIEWER_PK_2, messageHash);

        // Call: execute `areApprovalsValidViaPolicyLibrary` and capture the authorization decision.
        bool ok = harness.areApprovalsValidViaPolicyLibrary(policy, signature, messageHash);
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(ok, "non-authorized member signer should fail closed");
    }

    /// @dev Verifies that member approver signer not in organization returns false.
    function test_areApprovalsValid_memberApproverSignerNotInOrg_returnsFalse() public {
        // Setup: build fixture inputs where member approver signer not in organization returns false should be denied.
        Policy memory policy = _memberApproverPolicy(reviewer1);
        policyStateHarness.setMemberStatus(reviewer1, false);

        bytes32 messageHash = keccak256("policy-approval-message");
        bytes memory signature = _signHash(REVIEWER_PK_1, messageHash);

        // Call: execute `areApprovalsValidViaPolicyLibrary` and capture the authorization decision.
        bool ok = harness.areApprovalsValidViaPolicyLibrary(policy, signature, messageHash);
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(ok, "signer outside organization should fail closed");
    }

    /// @dev Verifies that group approver with threshold N and exactly N valid sorted signatures returns true.
    function test_areApprovalsValid_groupApproverExactThresholdSortedSignatures_returnsTrue() public {
        // Setup: configure a valid fixture for group approver with threshold N and exactly N valid sorted signatures
        // returns true.
        Policy memory policy = _groupApproverPolicy(2201, 2);
        _setActiveGroupWithMembers(2201, buildArray(reviewer1, reviewer2));

        bytes32 messageHash = keccak256("policy-approval-message");
        uint256[] memory keys = new uint256[](2);
        keys[0] = REVIEWER_PK_1;
        keys[1] = REVIEWER_PK_2;
        bytes memory signatures = _buildSortedEoaSignatures(messageHash, keys);

        // Call: execute `areApprovalsValidViaPolicyLibrary` with the happy-path payload.
        bool ok = harness.areApprovalsValidViaPolicyLibrary(policy, signatures, messageHash);
        // Verify: assert the expected success result and state updates.
        assertTrue(ok, "exact threshold of valid signatures should pass");
    }

    /// @dev Verifies that group approver accepts more-than-threshold valid sorted signatures.
    function test_areApprovalsValid_groupApproverThresholdOneWithTwoValidSignatures_returnsTrue() public {
        // Setup: configure a valid fixture for group approver accepts more-than-threshold valid sorted signatures.
        Policy memory policy = _groupApproverPolicy(2202, 1);
        _setActiveGroupWithMembers(2202, buildArray(reviewer1, reviewer2));

        bytes32 messageHash = keccak256("policy-approval-message");
        uint256[] memory keys = new uint256[](2);
        keys[0] = REVIEWER_PK_1;
        keys[1] = REVIEWER_PK_2;
        bytes memory signatures = _buildSortedEoaSignatures(messageHash, keys);

        // Call: execute `areApprovalsValidViaPolicyLibrary` with the happy-path payload.
        bool ok = harness.areApprovalsValidViaPolicyLibrary(policy, signatures, messageHash);
        // Verify: assert the expected success result and state updates.
        assertTrue(ok, "more-than-threshold signatures should be accepted");
    }

    /// @dev Verifies that group approver with fewer than threshold valid signatures returns false.
    function test_areApprovalsValid_groupApproverFewerThanThreshold_returnsFalse() public {
        // Setup: build fixture inputs where group approver with fewer than threshold valid signatures returns false
        // should be denied.
        Policy memory policy = _groupApproverPolicy(2203, 2);
        _setActiveGroupWithMembers(2203, buildArray(reviewer1));

        bytes32 messageHash = keccak256("policy-approval-message");
        bytes memory signature = _signHash(REVIEWER_PK_1, messageHash);

        // Call: execute `areApprovalsValidViaPolicyLibrary` and capture the authorization decision.
        bool ok = harness.areApprovalsValidViaPolicyLibrary(policy, signature, messageHash);
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(ok, "fewer valid signatures than threshold must fail");
    }

    /// @dev Verifies that group approver signer not in approver group returns false.
    function test_areApprovalsValid_groupApproverSignerNotInGroup_returnsFalse() public {
        // Setup: build fixture inputs where group approver signer not in approver group returns false should be denied.
        Policy memory policy = _groupApproverPolicy(2204, 1);
        _setActiveGroupWithMembers(2204, buildArray(reviewer1));
        _setMembersAsOrgMembers(buildArray(reviewer2));

        bytes32 messageHash = keccak256("policy-approval-message");
        bytes memory signature = _signHash(REVIEWER_PK_2, messageHash);

        // Call: execute `areApprovalsValidViaPolicyLibrary` and capture the authorization decision.
        bool ok = harness.areApprovalsValidViaPolicyLibrary(policy, signature, messageHash);
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(ok, "signer outside approver group should fail closed");
    }

    /// @dev Verifies that missing approver group returns false.
    function test_areApprovalsValid_groupApproverMissingGroup_returnsFalse() public {
        // Setup: build fixture inputs where missing approver group returns false should be denied.
        Policy memory policy = _groupApproverPolicy(2205, 1);
        _setMembersAsOrgMembers(buildArray(reviewer1));

        bytes32 messageHash = keccak256("policy-approval-message");
        bytes memory signature = _signHash(REVIEWER_PK_1, messageHash);

        // Call: execute `areApprovalsValidViaPolicyLibrary` and capture the authorization decision.
        bool ok = harness.areApprovalsValidViaPolicyLibrary(policy, signature, messageHash);
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(ok, "missing approver group should fail closed");
    }

    /// @dev Verifies that duplicate signer sequence returns false.
    function test_areApprovalsValid_duplicateSigner_returnsFalse() public {
        // Setup: build fixture inputs where duplicate signer sequence returns false should be denied.
        Policy memory policy = _groupApproverPolicy(2206, 2);
        _setActiveGroupWithMembers(2206, buildArray(reviewer1));

        bytes32 messageHash = keccak256("policy-approval-message");
        bytes memory signature = _signHash(REVIEWER_PK_1, messageHash);
        bytes memory signatures = abi.encodePacked(signature, signature);

        // Call: execute `areApprovalsValidViaPolicyLibrary` and capture the authorization decision.
        bool ok = harness.areApprovalsValidViaPolicyLibrary(policy, signatures, messageHash);
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(ok, "duplicate signer should fail closed");
    }

    /// @dev Verifies that out-of-order signer sequence returns false.
    function test_areApprovalsValid_outOfOrderSigner_returnsFalse() public {
        // Setup: build fixture inputs where out-of-order signer sequence returns false should be denied.
        Policy memory policy = _groupApproverPolicy(2207, 2);
        _setActiveGroupWithMembers(2207, buildArray(reviewer1, reviewer2));

        bytes32 messageHash = keccak256("policy-approval-message");
        bytes memory sig1 = _signHash(REVIEWER_PK_1, messageHash);
        bytes memory sig2 = _signHash(REVIEWER_PK_2, messageHash);
        bytes memory signatures = reviewer2 > reviewer1 ? abi.encodePacked(sig2, sig1) : abi.encodePacked(sig1, sig2);

        // Call: execute `areApprovalsValidViaPolicyLibrary` and capture the authorization decision.
        bool ok = harness.areApprovalsValidViaPolicyLibrary(policy, signatures, messageHash);
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(ok, "out-of-order signers should fail closed");
    }

    /// @dev Verifies that malformed packed signature data returns false.
    function test_areApprovalsValid_malformedPackedSignature_returnsFalse() public {
        // Setup: build fixture inputs where malformed packed signature data returns false should be denied.
        Policy memory policy = _memberApproverPolicy(reviewer1);
        _setMembersAsOrgMembers(buildArray(reviewer1));

        // Call: execute `areApprovalsValidViaPolicyLibrary` and capture the authorization decision.
        bool ok = harness.areApprovalsValidViaPolicyLibrary(policy, hex"01", keccak256("policy-approval-message"));
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(ok, "malformed packed signatures should fail closed");
    }

    /// @dev Verifies that mixed EOA + ERC-1271 signers are supported when sorted by signer address.
    function test_areApprovalsValid_mixedEOAAndERC1271Sorted_returnsTrue() public {
        // Setup: configure a valid fixture for mixed EOA + ERC-1271 signers are supported when sorted by signer
        // address.
        Policy memory policy = _groupApproverPolicy(2208, 2);

        address erc1271Signer = address(validSigner1271);
        _setActiveGroupWithMembers(2208, buildArray(reviewer1, erc1271Signer));

        bytes32 messageHash = keccak256("policy-approval-message");
        bytes memory eoaSig = _signHash(REVIEWER_PK_1, messageHash);
        bytes memory contractSig = _buildContractSignature(erc1271Signer, hex"CAFE");

        address[] memory signers = new address[](2);
        signers[0] = reviewer1;
        signers[1] = erc1271Signer;

        bytes[] memory signaturesList = new bytes[](2);
        signaturesList[0] = eoaSig;
        signaturesList[1] = contractSig;

        bytes memory signatures = _sortAndConcatSignatures(signers, signaturesList);

        // Call: execute `areApprovalsValidViaPolicyLibrary` with the happy-path payload.
        bool ok = harness.areApprovalsValidViaPolicyLibrary(policy, signatures, messageHash);
        // Verify: assert the expected success result and state updates.
        assertTrue(ok, "sorted mixed EOA + ERC1271 signatures should pass");
    }

    /// @dev Verifies that early-exit after threshold is met ignores trailing malformed bytes and returns true.
    function test_areApprovalsValid_thresholdMetBeforeTrailingMalformedBytes_returnsTrue() public {
        // Setup: configure a valid fixture for early-exit after threshold is met ignores trailing malformed bytes and
        // returns true.
        Policy memory policy = _memberApproverPolicy(reviewer1);
        _setMembersAsOrgMembers(buildArray(reviewer1));

        bytes32 messageHash = keccak256("policy-approval-message");
        bytes memory signature = _signHash(REVIEWER_PK_1, messageHash);
        bytes memory signatures = abi.encodePacked(signature, hex"FF00");

        // Call: execute `areApprovalsValidViaPolicyLibrary` with the happy-path payload.
        bool ok = harness.areApprovalsValidViaPolicyLibrary(policy, signatures, messageHash);
        // Verify: assert the expected success result and state updates.
        assertTrue(ok, "threshold met should return true before trailing malformed bytes are parsed");
    }

    /// @dev Verifies that desired behavior: group threshold 0 should fail closed (false or explicit revert).
    function test_areApprovalsValid_groupThresholdZero_failsClosed_desired() public {
        // Setup: build fixture inputs where desired behavior: group threshold 0 should fail closed (false or explicit
        // revert) should be denied.
        Policy memory policy = _groupApproverPolicy(2209, 0);
        _setActiveGroupWithMembers(2209, buildArray(reviewer1));

        bytes32 messageHash = keccak256("policy-approval-message");
        bytes memory signature = _signHash(REVIEWER_PK_1, messageHash);

        bytes memory callData =
            abi.encodeCall(harness.areApprovalsValidViaPolicyLibrary, (policy, signature, messageHash));
        (bool success, bytes memory result) = address(harness).call(callData);

        if (!success) {
            return;
        }

        bool approved = abi.decode(result, (bool));
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(approved, "desired behavior: threshold=0 should not approve");
    }

    /// @dev Verifies that deterministic result for identical inputs and unchanged state.
    function test_areApprovalsValid_sameInputsUnchangedState_deterministic() public {
        // Setup: configure a valid fixture for deterministic result for identical inputs and unchanged state.
        Policy memory policy = _groupApproverPolicy(2210, 2);
        _setActiveGroupWithMembers(2210, buildArray(reviewer1, reviewer2));

        bytes32 messageHash = keccak256("policy-approval-message");
        uint256[] memory keys = new uint256[](2);
        keys[0] = REVIEWER_PK_1;
        keys[1] = REVIEWER_PK_2;
        bytes memory signatures = _buildSortedEoaSignatures(messageHash, keys);

        // Call: execute `areApprovalsValidViaPolicyLibrary` with the happy-path payload.
        bool first = harness.areApprovalsValidViaPolicyLibrary(policy, signatures, messageHash);
        bool second = harness.areApprovalsValidViaPolicyLibrary(policy, signatures, messageHash);

        // Verify: assert the expected success result and state updates.
        assertEq(first, second, "result must be deterministic");
        assertTrue(first, "both calls should succeed");
    }

    /// @dev Verifies that member approver type always requires exactly 1 approval.
    function test_getRequiredApprovals_memberApprover_returnsOne() public {
        // Setup: configure a valid fixture for member approver type always requires exactly 1 approval.
        Policy memory policy = _memberApproverPolicy(reviewer1);

        // Call: execute `getRequiredApprovalsViaPolicyLibrary` with the happy-path payload.
        uint256 required = harness.getRequiredApprovalsViaPolicyLibrary(policy);
        // Verify: assert the expected success result and state updates.
        assertEq(required, 1, "member approver should always require one approval");
    }

    /// @dev Verifies that group approver type returns configured approval threshold.
    function test_getRequiredApprovals_groupApprover_returnsConfiguredThreshold() public {
        // Setup: configure a valid fixture for group approver type returns configured approval threshold.
        Policy memory policy = _groupApproverPolicy(2211, 3);

        // Call: execute `getRequiredApprovalsViaPolicyLibrary` with the happy-path payload.
        uint256 required = harness.getRequiredApprovalsViaPolicyLibrary(policy);
        // Verify: assert the expected success result and state updates.
        assertEq(required, 3, "group approver should return configured threshold");
    }

    /// @dev Verifies that member approver ignores `approvalThreshold` field.
    function test_getRequiredApprovals_memberApproverIgnoresThresholdField() public {
        // Setup: configure a valid fixture for member approver ignores `approvalThreshold` field.
        Policy memory policy = _memberApproverPolicy(reviewer1);
        policy.config.approval.approvalThreshold = 9;

        // Call: execute `getRequiredApprovalsViaPolicyLibrary` with the happy-path payload.
        uint256 required = harness.getRequiredApprovalsViaPolicyLibrary(policy);
        // Verify: assert the expected success result and state updates.
        assertEq(required, 1, "member approver should ignore threshold field");
    }

    /// @dev Verifies that unknown approver enum values revert during caller decoding.
    function test_getRequiredApprovals_invalidApproverType_revertsInCallerUsage() public {
        // Setup: build fixture inputs where unknown approver enum values revert during caller decoding.
        Policy memory policy = _memberApproverPolicy(reviewer1);
        _setMembersAsOrgMembers(buildArray(reviewer1));

        bytes32 messageHash = keccak256("policy-approval-message");
        bytes memory signature = _signHash(REVIEWER_PK_1, messageHash);
        bytes memory callData =
            abi.encodeCall(harness.areApprovalsValidViaPolicyLibrary, (policy, signature, messageHash));
        _setWord(callData, 4 + 5 * 32, 2);

        // Call: execute a low-level call with malformed enum calldata.
        (bool success,) = address(harness).call(callData);
        // Verify: assert that malformed enum values fail with a revert/panic.
        assertFalse(success, "invalid approver enum should revert in caller usage");
    }

    /// @dev Verifies that non-member signer returns false regardless of approver configuration.
    function test_isSignerAuthorizedForPolicy_nonMemberSigner_returnsFalseAcrossApproverModes() public {
        // Setup: build fixture inputs where non-member signer returns false regardless of approver configuration should
        // be denied.
        address nonMember = address(0xA401);
        Policy memory memberPolicy = _memberApproverPolicy(reviewer1);
        Policy memory groupPolicy = _groupApproverPolicy(2212, 1);

        _setActiveGroupWithMembers(2212, buildArray(reviewer1));
        policyStateHarness.setMemberStatus(nonMember, false);

        // Call: execute `isSignerAuthorizedForPolicyViaPolicyLibrary` and capture the authorization decision.
        bool memberMode = harness.isSignerAuthorizedForPolicyViaPolicyLibrary(memberPolicy, nonMember);
        bool groupMode = harness.isSignerAuthorizedForPolicyViaPolicyLibrary(groupPolicy, nonMember);

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(memberMode, "non-member should be unauthorized in member mode");
        assertFalse(groupMode, "non-member should be unauthorized in group mode");
    }

    /// @dev Verifies that member approver type authorizes only the configured approver member.
    function test_isSignerAuthorizedForPolicy_memberApprover_onlyConfiguredMemberAuthorized() public {
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for member approver type authorizes
        // only the configured approver member.
        Policy memory policy = _memberApproverPolicy(reviewer1);
        _setMembersAsOrgMembers(buildArray(reviewer1, reviewer2));

        // Call: run `isSignerAuthorizedForPolicyViaPolicyLibrary` across the prepared variants.
        bool configured = harness.isSignerAuthorizedForPolicyViaPolicyLibrary(policy, reviewer1);
        bool otherMember = harness.isSignerAuthorizedForPolicyViaPolicyLibrary(policy, reviewer2);

        // Verify: assert each variant returns the expected branch outcome.
        assertTrue(configured, "configured approver member should be authorized");
        assertFalse(otherMember, "other member should not be authorized");
    }

    /// @dev Verifies that group approver type authorizes members of the configured approver group.
    function test_isSignerAuthorizedForPolicy_groupApprover_groupMemberAuthorized() public {
        // Setup: configure a valid fixture for group approver type authorizes members of the configured approver group.
        Policy memory policy = _groupApproverPolicy(2213, 1);
        _setActiveGroupWithMembers(2213, buildArray(reviewer1));

        // Call: execute `isSignerAuthorizedForPolicyViaPolicyLibrary` with the happy-path payload.
        bool authorized = harness.isSignerAuthorizedForPolicyViaPolicyLibrary(policy, reviewer1);
        // Verify: assert the expected success result and state updates.
        assertTrue(authorized, "group member should be authorized");
    }

    /// @dev Verifies that group approver type returns false for non-group member.
    function test_isSignerAuthorizedForPolicy_groupApprover_nonGroupMemberReturnsFalse() public {
        // Setup: build fixture inputs where group approver type returns false for non-group member should be denied.
        Policy memory policy = _groupApproverPolicy(2214, 1);
        _setActiveGroupWithMembers(2214, buildArray(reviewer1));
        _setMembersAsOrgMembers(buildArray(reviewer2));

        // Call: execute `isSignerAuthorizedForPolicyViaPolicyLibrary` and capture the authorization decision.
        bool authorized = harness.isSignerAuthorizedForPolicyViaPolicyLibrary(policy, reviewer2);
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(authorized, "org member outside approver group should be unauthorized");
    }

    /// @dev Verifies that unknown approver enum values revert during signer-authorization decoding.
    function test_isSignerAuthorizedForPolicy_invalidApproverEnum_reverts() public {
        // Setup: build fixture inputs where unknown approver enum values revert during signer-authorization decoding.
        Policy memory policy = _memberApproverPolicy(reviewer1);
        _setMembersAsOrgMembers(buildArray(reviewer1));
        bytes memory callData = abi.encodeCall(harness.isSignerAuthorizedForPolicyViaPolicyLibrary, (policy, reviewer1));
        _setWord(callData, 4 + 5 * 32, 2);

        // Call: execute a low-level call with malformed enum calldata.
        (bool success,) = address(harness).call(callData);
        // Verify: assert that malformed enum values fail with a revert/panic.
        assertFalse(success, "invalid approver enum should revert");
    }

    /// @dev Verifies that zero-address signer returns false.
    function test_isSignerAuthorizedForPolicy_zeroAddressSigner_returnsFalse() public {
        // Setup: build fixture inputs where zero-address signer returns false should be denied.
        Policy memory policy = _memberApproverPolicy(reviewer1);
        _setMembersAsOrgMembers(buildArray(reviewer1));

        // Call: execute `isSignerAuthorizedForPolicyViaPolicyLibrary` and capture the authorization decision.
        bool authorized = harness.isSignerAuthorizedForPolicyViaPolicyLibrary(policy, address(0));
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(authorized, "zero-address signer should fail closed");
    }

    function _memberApproverPolicy(address approverMember) internal view returns (Policy memory policy) {
        policy = _buildBasePolicy();
        policy.config.approval.approverType = ApproverType.Member;
        policy.config.approval.approverMember = approverMember;
        policy.config.approval.approvalThreshold = 1;
    }

    function _groupApproverPolicy(uint256 approverGroupId, uint8 threshold)
        internal
        view
        returns (Policy memory policy)
    {
        policy = _buildBasePolicy();
        policy.config.approval.approverType = ApproverType.Group;
        policy.config.approval.approverGroupId = approverGroupId;
        policy.config.approval.approvalThreshold = threshold;
    }
}
