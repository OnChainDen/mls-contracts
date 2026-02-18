// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    OrganizationGroupsBaseSuiteBase
} from "test/organization/base/OrganizationGroupsBase/OrganizationGroupsBaseSuiteBase.sol";

/**
 * @dev Unit tests for read-only wrappers exposed by `OrganizationGroupsBase`.
 */
contract OrganizationGroupsBaseViewsTest is OrganizationGroupsBaseSuiteBase {
    /// @dev Verifies `isGroup` mirrors library values for active, non-existent, and deleted groups.
    function test_isGroup_passthroughForActiveNonExistentAndDeleted() public {
        uint256 activeGroupId = 8001;
        uint256 neverGroupId = 8002;
        uint256 deletedGroupId = 8003;

        // Setup: seed one active group and one deleted group.
        groupsStateHarness.setGroupStatus(activeGroupId, true);
        groupsStateHarness.setWasGroupDeletedStatus(deletedGroupId, true);

        // Call: read through base view wrappers.
        bool actualActive = harness.isGroup(activeGroupId);
        bool actualNever = harness.isGroup(neverGroupId);
        bool actualDeleted = harness.isGroup(deletedGroupId);

        // Verify: base getters mirror underlying library storage values.
        assertTrue(actualActive, "active group should return true");
        assertFalse(actualNever, "never-existing group should return false");
        assertFalse(actualDeleted, "deleted group should return false");
    }

    /// @dev Verifies `isGroupMember` mirrors library values for existing-group member/non-member queries.
    function test_isGroupMember_passthroughForExistingGroupMemberAndNonMember() public {
        uint256 groupId = 8004;

        // Setup: seed one active group with one active member.
        groupsStateHarness.setGroupStatus(groupId, true);
        groupsStateHarness.setGroupMemberStatus(groupId, admin1, true);

        // Call: read through base view wrappers.
        bool actualMember = harness.isGroupMember(groupId, admin1);
        bool actualNonMember = harness.isGroupMember(groupId, admin2);

        // Verify: base getter matches underlying library view behavior.
        assertTrue(actualMember, "known group member should return true");
        assertFalse(actualNonMember, "known non-member should return false");
    }

    /// @dev Verifies desired behavior that `isGroupMember` returns false for non-existent groups.
    function test_isGroupMember_nonExistentGroup_returnsFalse() public view {
        uint256 nonExistentGroupId = 8005;

        // Call: query membership for non-existent group.
        bool actual = harness.isGroupMember(nonExistentGroupId, admin1);

        // Verify: non-existent groups should report no active membership.
        assertFalse(actual, "non-existent group membership query should return false");
    }

    /// @dev Verifies desired behavior that deleted groups do not leak ghost membership via base getter.
    function test_isGroupMember_deletedGroup_returnsFalseDespiteGhostMembership() public {
        uint256 groupId = 8006;

        // Setup: deleted group with historical membership entry.
        groupsStateHarness.setWasGroupDeletedStatus(groupId, true);
        groupsStateHarness.setGroupMemberStatus(groupId, admin1, true);

        // Call: query membership through base getter.
        bool actual = harness.isGroupMember(groupId, admin1);

        // Desired behavior: deleted groups should not report active membership.
        assertFalse(actual, "deleted group should not leak ghost membership through base getter");
    }
}
