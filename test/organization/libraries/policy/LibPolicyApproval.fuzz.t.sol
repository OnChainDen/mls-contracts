// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {PolicyLibrariesFuzzTestBase} from "test/organization/libraries/policy/PolicyLibrariesFuzzTestBase.sol";
import {Policy} from "types/PolicyTypes.sol";

/**
 * @dev Fuzz tests for `LibPolicyApproval`.
 */
contract LibPolicyApprovalFuzzTest is PolicyLibrariesFuzzTestBase {
    /// @dev Verifies `LibPolicyApproval.areApprovalsValid` accepts only sorted unique reviewer signatures.
    /// @param messageHash The message hash signed by the reviewers.
    function testFuzz_areApprovalsValid_requiresSortedUniqueReviewers(bytes32 messageHash) public {
        // Setup: configure a threshold-two approver group and prepare sorted, duplicate, and reversed signature sets.
        Policy memory policy = _groupApproverPolicy(7801, 2);
        _setActiveGroupWithMembers(7801, buildArray(reviewer1, reviewer2));

        uint256[] memory keys = new uint256[](2);
        keys[0] = REVIEWER_PK_1;
        keys[1] = REVIEWER_PK_2;
        bytes memory sortedSignatures = _buildSortedEoaSignatures(messageHash, keys);

        bytes memory reviewer1Signature = _signHash(REVIEWER_PK_1, messageHash);
        bytes memory reviewer2Signature = _signHash(REVIEWER_PK_2, messageHash);
        bytes memory duplicateSignatures = bytes.concat(reviewer1Signature, reviewer1Signature);
        bytes memory reversedSignatures = reviewer1 < reviewer2
            ? bytes.concat(reviewer2Signature, reviewer1Signature)
            : bytes.concat(reviewer1Signature, reviewer2Signature);

        // Call: evaluate the exact sorted quorum plus duplicate and out-of-order mutation branches.
        bool sortedAllowed = harness.areApprovalsValidViaPolicyLibrary(policy, sortedSignatures, messageHash);
        bool duplicateAllowed = harness.areApprovalsValidViaPolicyLibrary(policy, duplicateSignatures, messageHash);
        bool reversedAllowed = harness.areApprovalsValidViaPolicyLibrary(policy, reversedSignatures, messageHash);

        // Verify: only the sorted unique signer stream should satisfy the approval policy.
        assertTrue(sortedAllowed, "sorted unique signatures should pass");
        assertFalse(duplicateAllowed, "duplicate signers should fail");
        assertFalse(reversedAllowed, "out-of-order signers should fail");
    }

    /// @dev Verifies `LibPolicyApproval._isSignerAuthorizedForPolicy` requires both organization membership and the
    /// configured member/group match.
    /// @param rawGroupId The group identifier used for the group-based authorization branch.
    /// @param outsider An address kept outside the organization for the negative branch.
    function testFuzz_isSignerAuthorized_requiresMembershipAndConfiguredMatch(
        uint256 rawGroupId,
        address outsider
    ) public {
        vm.assume(outsider != reviewer1);
        vm.assume(outsider != reviewer2);

        uint256 groupId = bound(rawGroupId, 1, type(uint32).max);

        // Setup: mark reviewer1 as the configured member approver, reviewer2 as an org member outside the group, and
        // keep `outsider` outside the organization.
        Policy memory memberPolicy = _memberApproverPolicy(reviewer1);
        Policy memory groupPolicy = _groupApproverPolicy(groupId, 1);
        _setMembersAsOrgMembers(buildArray(reviewer1, reviewer2));
        _setActiveGroupWithMembers(groupId, buildArray(reviewer1));
        policyStateHarness.setMemberStatus(outsider, false);

        // Call: evaluate member-mode and group-mode authorization across matching, mismatching, and non-member signers.
        bool memberConfigured = harness.isSignerAuthorizedForPolicyViaPolicyLibrary(memberPolicy, reviewer1);
        bool memberOther = harness.isSignerAuthorizedForPolicyViaPolicyLibrary(memberPolicy, reviewer2);
        bool memberOutsider = harness.isSignerAuthorizedForPolicyViaPolicyLibrary(memberPolicy, outsider);

        bool groupConfigured = harness.isSignerAuthorizedForPolicyViaPolicyLibrary(groupPolicy, reviewer1);
        bool groupOther = harness.isSignerAuthorizedForPolicyViaPolicyLibrary(groupPolicy, reviewer2);
        bool groupOutsider = harness.isSignerAuthorizedForPolicyViaPolicyLibrary(groupPolicy, outsider);

        // Verify: only organization members that match the configured member/group policy branch are authorized.
        assertTrue(memberConfigured, "configured member approver should be authorized");
        assertFalse(memberOther, "other members should fail member-mode authorization");
        assertFalse(memberOutsider, "non-members should fail member-mode authorization");
        assertTrue(groupConfigured, "configured group member should be authorized");
        assertFalse(groupOther, "members outside the approver group should fail");
        assertFalse(groupOutsider, "non-members should fail group-mode authorization");
    }
}
