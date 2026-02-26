// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationGroups} from "interfaces/organization/IOrganizationGroups.sol";
import {IOrganizationPolicy} from "interfaces/organization/IOrganizationPolicy.sol";
import {SignatureUtils} from "libraries/SignatureUtils.sol";
import {PolicyLibrariesSuiteBase} from "test/organization/libraries/policy/PolicyLibrariesSuiteBase.sol";
import {ApproverType, Policy} from "types/PolicyTypes.sol";

/**
 * @dev Unit tests for `LibPolicyApproval` wrappers.
 */
contract LibPolicyApprovalTest is PolicyLibrariesSuiteBase {
    /// @dev [LPA-1] Empty signatures return false.
    function test_areApprovalsValid_emptySignatures_returnsFalse() public {
        Policy memory policy = _memberApproverPolicy(reviewer1);

        bool ok = harness.areApprovalsValidViaPolicyLibrary(policy, bytes(""), keccak256("LPA-1"));
        assertFalse(ok, "empty signatures must fail");
    }

    /// @dev [LPA-2] Member approver with authorized member signature returns true.
    function test_areApprovalsValid_memberApproverAuthorizedSigner_returnsTrue() public {
        Policy memory policy = _memberApproverPolicy(reviewer1);
        _setMembersAsOrgMembers(buildArray(reviewer1));

        bytes32 messageHash = keccak256("LPA-2");
        bytes memory signature = _signHash(REVIEWER_PK_1, messageHash);

        bool ok = harness.areApprovalsValidViaPolicyLibrary(policy, signature, messageHash);
        assertTrue(ok, "authorized member signature should pass");
    }

    /// @dev [LPA-3] Member approver reverts `UnauthorizedApprovalSigner` for non-authorized signer.
    function test_areApprovalsValid_memberApproverUnauthorizedSigner_revertsUnauthorizedApprovalSigner() public {
        Policy memory policy = _memberApproverPolicy(reviewer1);
        _setMembersAsOrgMembers(buildArray(reviewer1, reviewer2));

        bytes32 messageHash = keccak256("LPA-3");
        bytes memory signature = _signHash(REVIEWER_PK_2, messageHash);

        vm.expectRevert(abi.encodeWithSelector(IOrganizationPolicy.UnauthorizedApprovalSigner.selector, reviewer2));
        harness.areApprovalsValidViaPolicyLibrary(policy, signature, messageHash);
    }

    /// @dev [LPA-4] Member approver reverts `UnauthorizedApprovalSigner` when signer is not in org.
    function test_areApprovalsValid_memberApproverSignerNotInOrg_revertsUnauthorizedApprovalSigner() public {
        Policy memory policy = _memberApproverPolicy(reviewer1);
        policyStateHarness.setMemberStatus(reviewer1, false);

        bytes32 messageHash = keccak256("LPA-4");
        bytes memory signature = _signHash(REVIEWER_PK_1, messageHash);

        vm.expectRevert(abi.encodeWithSelector(IOrganizationPolicy.UnauthorizedApprovalSigner.selector, reviewer1));
        harness.areApprovalsValidViaPolicyLibrary(policy, signature, messageHash);
    }

    /// @dev [LPA-5] Group approver with threshold N and exactly N valid sorted signatures returns true.
    function test_areApprovalsValid_groupApproverExactThresholdSortedSignatures_returnsTrue() public {
        Policy memory policy = _groupApproverPolicy(2201, 2);
        _setActiveGroupWithMembers(2201, buildArray(reviewer1, reviewer2));

        bytes32 messageHash = keccak256("LPA-5");
        uint256[] memory keys = new uint256[](2);
        keys[0] = REVIEWER_PK_1;
        keys[1] = REVIEWER_PK_2;
        bytes memory signatures = _buildSortedEOASignatures(messageHash, keys);

        bool ok = harness.areApprovalsValidViaPolicyLibrary(policy, signatures, messageHash);
        assertTrue(ok, "exact threshold of valid signatures should pass");
    }

    /// @dev [LPA-6] Group approver accepts more-than-threshold valid sorted signatures.
    function test_areApprovalsValid_groupApproverThresholdOneWithTwoValidSignatures_returnsTrue() public {
        Policy memory policy = _groupApproverPolicy(2202, 1);
        _setActiveGroupWithMembers(2202, buildArray(reviewer1, reviewer2));

        bytes32 messageHash = keccak256("LPA-6");
        uint256[] memory keys = new uint256[](2);
        keys[0] = REVIEWER_PK_1;
        keys[1] = REVIEWER_PK_2;
        bytes memory signatures = _buildSortedEOASignatures(messageHash, keys);

        bool ok = harness.areApprovalsValidViaPolicyLibrary(policy, signatures, messageHash);
        assertTrue(ok, "more-than-threshold signatures should be accepted");
    }

    /// @dev [LPA-7] Group approver with fewer than threshold valid signatures returns false.
    function test_areApprovalsValid_groupApproverFewerThanThreshold_returnsFalse() public {
        Policy memory policy = _groupApproverPolicy(2203, 2);
        _setActiveGroupWithMembers(2203, buildArray(reviewer1));

        bytes32 messageHash = keccak256("LPA-7");
        bytes memory signature = _signHash(REVIEWER_PK_1, messageHash);

        bool ok = harness.areApprovalsValidViaPolicyLibrary(policy, signature, messageHash);
        assertFalse(ok, "fewer valid signatures than threshold must fail");
    }

    /// @dev [LPA-8] Group approver reverts `UnauthorizedApprovalSigner` when signer is not in approver group.
    function test_areApprovalsValid_groupApproverSignerNotInGroup_revertsUnauthorizedApprovalSigner() public {
        Policy memory policy = _groupApproverPolicy(2204, 1);
        _setActiveGroupWithMembers(2204, buildArray(reviewer1));
        _setMembersAsOrgMembers(buildArray(reviewer2));

        bytes32 messageHash = keccak256("LPA-8");
        bytes memory signature = _signHash(REVIEWER_PK_2, messageHash);

        vm.expectRevert(abi.encodeWithSelector(IOrganizationPolicy.UnauthorizedApprovalSigner.selector, reviewer2));
        harness.areApprovalsValidViaPolicyLibrary(policy, signature, messageHash);
    }

    /// @dev [LPA-9] Group approver reverts `GroupDoesNotExist` when approver group is missing.
    function test_areApprovalsValid_groupApproverMissingGroup_revertsGroupDoesNotExist() public {
        Policy memory policy = _groupApproverPolicy(2205, 1);
        _setMembersAsOrgMembers(buildArray(reviewer1));

        bytes32 messageHash = keccak256("LPA-9");
        bytes memory signature = _signHash(REVIEWER_PK_1, messageHash);

        vm.expectRevert(abi.encodeWithSelector(IOrganizationGroups.GroupDoesNotExist.selector, 2205));
        harness.areApprovalsValidViaPolicyLibrary(policy, signature, messageHash);
    }

    /// @dev [LPA-10] Duplicate signer reverts `DuplicateOrOutOfOrderSigner`.
    function test_areApprovalsValid_duplicateSigner_revertsDuplicateOrOutOfOrderSigner() public {
        Policy memory policy = _groupApproverPolicy(2206, 2);
        _setActiveGroupWithMembers(2206, buildArray(reviewer1));

        bytes32 messageHash = keccak256("LPA-10");
        bytes memory signature = _signHash(REVIEWER_PK_1, messageHash);
        bytes memory signatures = abi.encodePacked(signature, signature);

        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationPolicy.DuplicateOrOutOfOrderSigner.selector, reviewer1, reviewer1)
        );
        harness.areApprovalsValidViaPolicyLibrary(policy, signatures, messageHash);
    }

    /// @dev [LPA-11] Out-of-order signer sequence reverts `DuplicateOrOutOfOrderSigner`.
    function test_areApprovalsValid_outOfOrderSigner_revertsDuplicateOrOutOfOrderSigner() public {
        Policy memory policy = _groupApproverPolicy(2207, 2);
        _setActiveGroupWithMembers(2207, buildArray(reviewer1, reviewer2));

        bytes32 messageHash = keccak256("LPA-11");
        bytes memory sig1 = _signHash(REVIEWER_PK_1, messageHash);
        bytes memory sig2 = _signHash(REVIEWER_PK_2, messageHash);

        address high = reviewer1;
        address low = reviewer2;
        bytes memory highSig = sig1;
        bytes memory lowSig = sig2;
        if (reviewer2 > reviewer1) {
            high = reviewer2;
            low = reviewer1;
            highSig = sig2;
            lowSig = sig1;
        }

        bytes memory signatures = abi.encodePacked(highSig, lowSig);

        vm.expectRevert(abi.encodeWithSelector(IOrganizationPolicy.DuplicateOrOutOfOrderSigner.selector, low, high));
        harness.areApprovalsValidViaPolicyLibrary(policy, signatures, messageHash);
    }

    /// @dev [LPA-12] Malformed packed signature data bubbles signature recovery revert.
    function test_areApprovalsValid_malformedPackedSignature_revertsSignatureRecoveryFailed() public {
        Policy memory policy = _memberApproverPolicy(reviewer1);
        _setMembersAsOrgMembers(buildArray(reviewer1));

        vm.expectRevert(SignatureUtils.SignatureRecoveryFailed.selector);
        harness.areApprovalsValidViaPolicyLibrary(policy, hex"01", keccak256("LPA-12"));
    }

    /// @dev [LPA-13] Mixed EOA + ERC-1271 signers are supported when sorted by signer address.
    function test_areApprovalsValid_mixedEOAAndERC1271Sorted_returnsTrue() public {
        Policy memory policy = _groupApproverPolicy(2208, 2);

        address erc1271Signer = address(validSigner1271);
        _setActiveGroupWithMembers(2208, buildArray(reviewer1, erc1271Signer));

        bytes32 messageHash = keccak256("LPA-13");
        bytes memory eoaSig = _signHash(REVIEWER_PK_1, messageHash);
        bytes memory contractSig = _buildContractSignature(erc1271Signer, hex"CAFE");

        address[] memory signers = new address[](2);
        signers[0] = reviewer1;
        signers[1] = erc1271Signer;

        bytes[] memory signaturesList = new bytes[](2);
        signaturesList[0] = eoaSig;
        signaturesList[1] = contractSig;

        bytes memory signatures = _sortAndConcatSignatures(signers, signaturesList);

        bool ok = harness.areApprovalsValidViaPolicyLibrary(policy, signatures, messageHash);
        assertTrue(ok, "sorted mixed EOA + ERC1271 signatures should pass");
    }

    /// @dev [LPA-14] Early-exit after threshold is met ignores trailing malformed bytes and returns true.
    function test_areApprovalsValid_thresholdMetBeforeTrailingMalformedBytes_returnsTrue() public {
        Policy memory policy = _memberApproverPolicy(reviewer1);
        _setMembersAsOrgMembers(buildArray(reviewer1));

        bytes32 messageHash = keccak256("LPA-14");
        bytes memory signature = _signHash(REVIEWER_PK_1, messageHash);
        bytes memory signatures = abi.encodePacked(signature, hex"FF00");

        bool ok = harness.areApprovalsValidViaPolicyLibrary(policy, signatures, messageHash);
        assertTrue(ok, "threshold met should return true before trailing malformed bytes are parsed");
    }

    /// @dev [LPA-15] Desired behavior: group threshold 0 should fail closed (false or explicit revert).
    function test_areApprovalsValid_groupThresholdZero_failsClosed_desired() public {
        Policy memory policy = _groupApproverPolicy(2209, 0);
        _setActiveGroupWithMembers(2209, buildArray(reviewer1));

        bytes32 messageHash = keccak256("LPA-15");
        bytes memory signature = _signHash(REVIEWER_PK_1, messageHash);

        bytes memory callData =
            abi.encodeCall(harness.areApprovalsValidViaPolicyLibrary, (policy, signature, messageHash));
        (bool success, bytes memory result) = address(harness).call(callData);

        if (!success) {
            return;
        }

        bool approved = abi.decode(result, (bool));
        assertFalse(approved, "desired behavior: threshold=0 should not approve");
    }

    /// @dev [LPA-16] Deterministic result for identical inputs and unchanged state.
    function test_areApprovalsValid_sameInputsUnchangedState_deterministic() public {
        Policy memory policy = _groupApproverPolicy(2210, 2);
        _setActiveGroupWithMembers(2210, buildArray(reviewer1, reviewer2));

        bytes32 messageHash = keccak256("LPA-16");
        uint256[] memory keys = new uint256[](2);
        keys[0] = REVIEWER_PK_1;
        keys[1] = REVIEWER_PK_2;
        bytes memory signatures = _buildSortedEOASignatures(messageHash, keys);

        bool first = harness.areApprovalsValidViaPolicyLibrary(policy, signatures, messageHash);
        bool second = harness.areApprovalsValidViaPolicyLibrary(policy, signatures, messageHash);

        assertEq(first, second, "result must be deterministic");
        assertTrue(first, "both calls should succeed");
    }

    /// @dev [LPA-REQ-1] Member approver type always requires exactly 1 approval.
    function test_getRequiredApprovals_memberApprover_returnsOne() public {
        Policy memory policy = _memberApproverPolicy(reviewer1);

        uint256 required = harness.getRequiredApprovalsViaPolicyLibrary(policy);
        assertEq(required, 1, "member approver should always require one approval");
    }

    /// @dev [LPA-REQ-2] Group approver type returns configured approval threshold.
    function test_getRequiredApprovals_groupApprover_returnsConfiguredThreshold() public {
        Policy memory policy = _groupApproverPolicy(2211, 3);

        uint256 required = harness.getRequiredApprovalsViaPolicyLibrary(policy);
        assertEq(required, 3, "group approver should return configured threshold");
    }

    /// @dev [LPA-REQ-3] Member approver ignores `approvalThreshold` field.
    function test_getRequiredApprovals_memberApproverIgnoresThresholdField() public {
        Policy memory policy = _memberApproverPolicy(reviewer1);
        policy.config.approval.approvalThreshold = 9;

        uint256 required = harness.getRequiredApprovalsViaPolicyLibrary(policy);
        assertEq(required, 1, "member approver should ignore threshold field");
    }

    /// @dev [LPA-REQ-4] Unknown approver enum fails closed in caller usage.
    function test_getRequiredApprovals_invalidApproverType_failsClosedInCallerUsage() public {
        Policy memory policy = _memberApproverPolicy(reviewer1);
        _setMembersAsOrgMembers(buildArray(reviewer1));

        bytes32 messageHash = keccak256("LPA-REQ-4");
        bytes memory signature = _signHash(REVIEWER_PK_1, messageHash);

        vm.expectRevert(abi.encodeWithSelector(IOrganizationPolicy.UnauthorizedApprovalSigner.selector, reviewer1));
        harness.areApprovalsValidViaPolicyLibraryRawApproverType(policy, type(uint256).max, signature, messageHash);
    }

    /// @dev [LPA-AUTH-1] Non-member signer returns false regardless of approver configuration.
    function test_isSignerAuthorizedForPolicy_nonMemberSigner_returnsFalseAcrossApproverModes() public {
        address nonMember = address(0xA401);
        Policy memory memberPolicy = _memberApproverPolicy(reviewer1);
        Policy memory groupPolicy = _groupApproverPolicy(2212, 1);

        _setActiveGroupWithMembers(2212, buildArray(reviewer1));
        policyStateHarness.setMemberStatus(nonMember, false);

        bool memberMode = harness.isSignerAuthorizedForPolicyViaPolicyLibrary(memberPolicy, nonMember);
        bool groupMode = harness.isSignerAuthorizedForPolicyViaPolicyLibrary(groupPolicy, nonMember);

        assertFalse(memberMode, "non-member should be unauthorized in member mode");
        assertFalse(groupMode, "non-member should be unauthorized in group mode");
    }

    /// @dev [LPA-AUTH-2] Member approver type authorizes only the configured approver member.
    function test_isSignerAuthorizedForPolicy_memberApprover_onlyConfiguredMemberAuthorized() public {
        Policy memory policy = _memberApproverPolicy(reviewer1);
        _setMembersAsOrgMembers(buildArray(reviewer1, reviewer2));

        bool configured = harness.isSignerAuthorizedForPolicyViaPolicyLibrary(policy, reviewer1);
        bool otherMember = harness.isSignerAuthorizedForPolicyViaPolicyLibrary(policy, reviewer2);

        assertTrue(configured, "configured approver member should be authorized");
        assertFalse(otherMember, "other member should not be authorized");
    }

    /// @dev [LPA-AUTH-3] Group approver type authorizes members of the configured approver group.
    function test_isSignerAuthorizedForPolicy_groupApprover_groupMemberAuthorized() public {
        Policy memory policy = _groupApproverPolicy(2213, 1);
        _setActiveGroupWithMembers(2213, buildArray(reviewer1));

        bool authorized = harness.isSignerAuthorizedForPolicyViaPolicyLibrary(policy, reviewer1);
        assertTrue(authorized, "group member should be authorized");
    }

    /// @dev [LPA-AUTH-4] Group approver type returns false for non-group member.
    function test_isSignerAuthorizedForPolicy_groupApprover_nonGroupMemberReturnsFalse() public {
        Policy memory policy = _groupApproverPolicy(2214, 1);
        _setActiveGroupWithMembers(2214, buildArray(reviewer1));
        _setMembersAsOrgMembers(buildArray(reviewer2));

        bool authorized = harness.isSignerAuthorizedForPolicyViaPolicyLibrary(policy, reviewer2);
        assertFalse(authorized, "org member outside approver group should be unauthorized");
    }

    /// @dev [LPA-AUTH-5] Unknown approver enum returns false.
    function test_isSignerAuthorizedForPolicy_invalidApproverEnum_returnsFalse() public {
        Policy memory policy = _memberApproverPolicy(reviewer1);
        _setMembersAsOrgMembers(buildArray(reviewer1));

        bool authorized =
            harness.isSignerAuthorizedForPolicyViaPolicyLibraryRawApproverType(policy, type(uint256).max, reviewer1);
        assertFalse(authorized, "invalid approver type should fail closed");
    }

    /// @dev [LPA-AUTH-6] Zero-address signer returns false.
    function test_isSignerAuthorizedForPolicy_zeroAddressSigner_returnsFalse() public {
        Policy memory policy = _memberApproverPolicy(reviewer1);
        _setMembersAsOrgMembers(buildArray(reviewer1));

        bool authorized = harness.isSignerAuthorizedForPolicyViaPolicyLibrary(policy, address(0));
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
