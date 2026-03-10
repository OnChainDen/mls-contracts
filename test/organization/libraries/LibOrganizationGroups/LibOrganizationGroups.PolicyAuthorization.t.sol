// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibOrganizationPolicySuiteBase
} from "test/organization/libraries/LibOrganizationPolicy/LibOrganizationPolicySuiteBase.sol";
import {ApproverType, Policy} from "types/PolicyTypes.sol";

/**
 * @dev Cross-library group tests that assert policy authorization fails closed when group state is stale or absent.
 */
contract LibOrganizationGroupsPolicyAuthorizationTest is LibOrganizationPolicySuiteBase {
    uint256 internal constant AUTHORIZATION_GROUP_ID = 9_301;
    bytes32 internal constant REVIEW_HASH = keccak256("lib-organization-groups-policy-review-hash");

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

    /// @dev Verifies group-based policy authorization fails when `isGroup(groupId)` is false even if member bits are
    /// still set.
    function test_GROUP_INV_3_groupBasedAuthorizationFailsWhenGroupIsInactiveEvenIfMembershipBitsExist() public {
        // Setup: configure a shared group policy, keep both addresses as current org members, and seed the raw
        // group-member bits without marking the group itself active.
        Policy memory policy = _buildSharedGroupPolicy(AUTHORIZATION_GROUP_ID);
        policyStateHarness.setMemberStatus(initiator1, true);
        policyStateHarness.setMemberStatus(reviewer1, true);
        policyStateHarness.setGroupMemberStatus(AUTHORIZATION_GROUP_ID, initiator1, true);
        policyStateHarness.setGroupMemberStatus(AUTHORIZATION_GROUP_ID, reviewer1, true);

        bytes memory reviewerSignature = _signHash(REVIEWER_PK_1, REVIEW_HASH);

        // Call: query initiator and approval authorization through the policy library while `isGroup(groupId)==false`.
        bool initiatorAuthorized = harness.isInitiatorAuthorizedViaPolicyLibrary(policy, initiator1);
        bool approvalsValid = harness.areApprovalsValidViaPolicyLibrary(policy, reviewerSignature, REVIEW_HASH);

        // Verify: neither policy path may succeed without an active group, even though the raw membership bits exist.
        assertTrue(
            policyStateHarness.getGroupMemberStatus(AUTHORIZATION_GROUP_ID, initiator1),
            "raw initiator group bit should remain set for the regression guard"
        );
        assertTrue(
            policyStateHarness.getGroupMemberStatus(AUTHORIZATION_GROUP_ID, reviewer1),
            "raw reviewer group bit should remain set for the regression guard"
        );
        assertFalse(initiatorAuthorized, "inactive group must not authorize initiation");
        assertFalse(approvalsValid, "inactive group must not authorize approvals");
    }

    /// @dev Verifies an address removed from organization membership cannot remain effectively authorized through a
    /// stale group-membership bit.
    function test_GROUP_INV_8_removedOrgMemberCannotRemainEffectivelyAuthorizedViaGroupPolicy() public {
        // Setup: configure a live group policy, seed both addresses as org members plus group members, and verify the
        // policy is initially usable.
        Policy memory policy = _buildSharedGroupPolicy(AUTHORIZATION_GROUP_ID);
        policyStateHarness.setGroupStatus(AUTHORIZATION_GROUP_ID, true);
        policyStateHarness.setMemberStatus(initiator1, true);
        policyStateHarness.setMemberStatus(reviewer1, true);
        policyStateHarness.setGroupMemberStatus(AUTHORIZATION_GROUP_ID, initiator1, true);
        policyStateHarness.setGroupMemberStatus(AUTHORIZATION_GROUP_ID, reviewer1, true);

        bytes memory reviewerSignature = _signHash(REVIEWER_PK_1, REVIEW_HASH);
        assertTrue(
            harness.isInitiatorAuthorizedViaPolicyLibrary(policy, initiator1),
            "active member should initially authorize through the group policy"
        );
        assertTrue(
            harness.areApprovalsValidViaPolicyLibrary(policy, reviewerSignature, REVIEW_HASH),
            "active reviewer should initially authorize through the group policy"
        );

        // Call: remove both addresses from organization membership while leaving the group and raw membership bits
        // untouched.
        policyStateHarness.setMemberStatus(initiator1, false);
        policyStateHarness.setMemberStatus(reviewer1, false);

        bool initiatorAuthorized = harness.isInitiatorAuthorizedViaPolicyLibrary(policy, initiator1);
        bool approvalsValid = harness.areApprovalsValidViaPolicyLibrary(policy, reviewerSignature, REVIEW_HASH);

        // Verify: stale group-member bits must not keep either address effectively authorized once org membership is
        // gone.
        assertTrue(
            policyStateHarness.getGroupMemberStatus(AUTHORIZATION_GROUP_ID, initiator1),
            "stale initiator group bit should remain set for this regression guard"
        );
        assertTrue(
            policyStateHarness.getGroupMemberStatus(AUTHORIZATION_GROUP_ID, reviewer1),
            "stale reviewer group bit should remain set for this regression guard"
        );
        assertFalse(initiatorAuthorized, "removed org member must not stay authorized via group initiator path");
        assertFalse(approvalsValid, "removed org member must not stay authorized via group approval path");
    }
}
