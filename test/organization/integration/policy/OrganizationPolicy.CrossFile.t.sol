// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibOrganizationPolicySuiteBase
} from "test/organization/libraries/LibOrganizationPolicy/LibOrganizationPolicySuiteBase.sol";
import {ApproverType, Policy} from "types/PolicyTypes.sol";

/**
 * @dev Cross-file policy tests that exercise authorization changes after member/group mutations.
 */
contract OrganizationPolicyCrossFileTest is LibOrganizationPolicySuiteBase {
    uint256 internal constant AUTHORIZATION_GROUP_ID = 7701;
    bytes32 internal constant REVIEW_HASH = keccak256("organization-policy-cross-file-review-hash");

    /**
     * @dev Builds a policy that requires an exact member initiator and an exact member approver.
     * @param initiatorMember Member allowed to initiate.
     * @param approverMember Member allowed to approve.
     * @return policy Policy configured for member-scoped authorization checks.
     */
    function _buildMemberScopedPolicy(address initiatorMember, address approverMember)
        internal
        view
        returns (Policy memory policy)
    {
        policy = _buildBasePolicy();
        policy.config.initiator.anyInitiator = false;
        policy.config.initiator.initiatorType = ApproverType.Member;
        policy.config.initiator.initiatorMember = initiatorMember;
        policy.config.approval.approverType = ApproverType.Member;
        policy.config.approval.approverMember = approverMember;
        policy.config.approval.approvalThreshold = 1;
    }

    /**
     * @dev Builds a policy that requires the same group for initiation and approval.
     * @param groupId Group that must authorize both actions.
     * @return policy Policy configured for shared group-scoped authorization checks.
     */
    function _buildSharedGroupPolicy(uint256 groupId) internal view returns (Policy memory policy) {
        policy = _buildBasePolicy();
        policy.config.initiator.anyInitiator = false;
        policy.config.initiator.initiatorType = ApproverType.Group;
        policy.config.initiator.initiatorGroupId = groupId;
        policy.config.approval.approverType = ApproverType.Group;
        policy.config.approval.approverGroupId = groupId;
        policy.config.approval.approvalThreshold = 1;
    }

    /// @dev Verifies policy authorization fails after removing the designated initiator and reviewer from membership.
    function test_OMB_MM_3_removedMemberStopsQualifyingAsPolicyInitiatorAndReviewer() public {
        // Setup: configure a member-scoped policy and seed the designated initiator/reviewer as active members.
        Policy memory policy = _buildMemberScopedPolicy(initiator1, reviewer1);
        policyStateHarness.setMemberStatus(initiator1, true);
        policyStateHarness.setMemberStatus(reviewer1, true);

        bytes memory reviewerSignature = _signHash(REVIEWER_PK_1, REVIEW_HASH);

        // Verify: the policy initially authorizes the seeded initiator and reviewer.
        assertTrue(
            harness.isInitiatorAuthorizedViaPolicyLibrary(policy, initiator1),
            "member initiator should authorize before removal"
        );
        assertTrue(
            harness.areApprovalsValidViaPolicyLibrary(policy, reviewerSignature, REVIEW_HASH),
            "member approver should authorize before removal"
        );

        // Call: remove both addresses from organization membership while leaving the policy configuration unchanged.
        policyStateHarness.setMemberStatus(initiator1, false);
        policyStateHarness.setMemberStatus(reviewer1, false);

        // Verify: the same policy no longer authorizes either the removed initiator or the removed reviewer.
        assertFalse(
            harness.isInitiatorAuthorizedViaPolicyLibrary(policy, initiator1),
            "removed initiator must fail policy authorization"
        );
        assertFalse(
            harness.areApprovalsValidViaPolicyLibrary(policy, reviewerSignature, REVIEW_HASH),
            "removed reviewer must fail policy authorization"
        );
    }

    /// @dev Verifies deleted groups stop authorizing policies even when stale group-member bits still remain set.
    function test_OGB_MG_3_OGB_MG_5_GROUP_INV_4_deletedGroupWithGhostMembershipStopsAuthorizingPolicies() public {
        // Setup: configure a shared group-based policy and seed live organization membership plus group membership.
        Policy memory policy = _buildSharedGroupPolicy(AUTHORIZATION_GROUP_ID);
        policyStateHarness.setGroupStatus(AUTHORIZATION_GROUP_ID, true);
        policyStateHarness.setMemberStatus(initiator1, true);
        policyStateHarness.setMemberStatus(reviewer1, true);
        policyStateHarness.setGroupMemberStatus(AUTHORIZATION_GROUP_ID, initiator1, true);
        policyStateHarness.setGroupMemberStatus(AUTHORIZATION_GROUP_ID, reviewer1, true);

        bytes memory reviewerSignature = _signHash(REVIEWER_PK_1, REVIEW_HASH);

        // Verify: the active group initially authorizes both initiation and approval.
        assertTrue(
            harness.isInitiatorAuthorizedViaPolicyLibrary(policy, initiator1),
            "active group should authorize its initiator member"
        );
        assertTrue(
            harness.areApprovalsValidViaPolicyLibrary(policy, reviewerSignature, REVIEW_HASH),
            "active group should authorize its reviewer member"
        );

        // Call: delete the group by clearing only the active-group bit while preserving the stored member bits.
        policyStateHarness.setGroupStatus(AUTHORIZATION_GROUP_ID, false);

        // Verify: ghost membership bits remain set, but deleted-group policies fail closed for both auth paths.
        assertTrue(
            policyStateHarness.getGroupMemberStatus(AUTHORIZATION_GROUP_ID, initiator1),
            "ghost initiator membership bit should remain set for this regression guard"
        );
        assertTrue(
            policyStateHarness.getGroupMemberStatus(AUTHORIZATION_GROUP_ID, reviewer1),
            "ghost reviewer membership bit should remain set for this regression guard"
        );
        assertFalse(
            harness.isInitiatorAuthorizedViaPolicyLibrary(policy, initiator1),
            "deleted group must not authorize initiation"
        );
        assertFalse(
            harness.areApprovalsValidViaPolicyLibrary(policy, reviewerSignature, REVIEW_HASH),
            "deleted group must not authorize approvals"
        );
    }
}
