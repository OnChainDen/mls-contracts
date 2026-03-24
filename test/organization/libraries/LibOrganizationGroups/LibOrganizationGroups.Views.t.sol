// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibOrganizationGroupsSuiteBase
} from "test/organization/libraries/LibOrganizationGroups/LibOrganizationGroupsSuiteBase.sol";

/**
 * @dev Unit tests for read-only wrappers around `LibOrganizationGroups` views.
 */
contract LibOrganizationGroupsViewsTest is LibOrganizationGroupsSuiteBase {
    /// @dev Verifies `isGroup` returns true for an active group.
    function test_isGroup_returnsTrueForActiveGroup() public {
        uint256 groupId = 7301;

        // Setup: mark target group as active.
        groupsStateHarness.setGroupStatus(groupId, true);

        // Call: query group existence.
        bool actualIsGroup = harness.isGroupViaLibrary(groupId);

        // Verify: active group should return true.
        assertTrue(actualIsGroup, "active group should return true");
    }

    /// @dev Verifies `isGroup` returns false for a group that never existed.
    function test_isGroup_returnsFalseForNeverExistingGroup() public view {
        uint256 groupId = 7302;

        // Call: query untouched group ID.
        bool actualIsGroup = harness.isGroupViaLibrary(groupId);

        // Verify: untouched group should return false.
        assertFalse(actualIsGroup, "never-existing group should return false");
    }

    /// @dev Verifies `isGroup` returns false after deletion.
    function test_isGroup_returnsFalseAfterDeletion() public {
        uint256 groupId = 7303;

        // Setup: create and then delete the same group.
        harness.modifyGroupsViaLibrary(_buildModificationsArray(_createModification(groupId, buildArray(admin1))));
        harness.modifyGroupsViaLibrary(_buildModificationsArray(_deleteModification(groupId)));

        // Call: query deleted group status.
        bool actualIsGroup = harness.isGroupViaLibrary(groupId);

        // Verify: deleted group should return false.
        assertFalse(actualIsGroup, "deleted group should return false");
    }

    /// @dev Verifies boundary IDs `0` and `type(uint256).max` are queryable without revert.
    function test_isGroup_boundaryIdsZeroAndMax_queryWithoutRevert() public view {
        // Call: query boundary IDs.
        bool actualZero = harness.isGroupViaLibrary(0);
        bool actualMax = harness.isGroupViaLibrary(type(uint256).max);

        // Verify: both queries complete and return false in untouched state.
        assertFalse(actualZero, "untouched groupId=0 should return false");
        assertFalse(actualMax, "untouched groupId=max should return false");
    }

    /// @dev Verifies `isGroupMember` returns true for an address currently in a group.
    function test_isGroupMember_returnsTrueForAddressCurrentlyInGroup() public {
        uint256 groupId = 7304;

        // Setup: create group with admin1 as a member.
        harness.modifyGroupsViaLibrary(_buildModificationsArray(_createModification(groupId, buildArray(admin1))));

        // Call: query membership for added address.
        bool actualIsGroupMember = harness.isGroupMemberViaLibrary(groupId, admin1);

        // Verify: added address should return true.
        assertTrue(actualIsGroupMember, "current group member should return true");
    }

    /// @dev Verifies `isGroupMember` returns false for an address not in the group.
    function test_isGroupMember_returnsFalseForAddressNotInGroup() public {
        uint256 groupId = 7305;

        // Setup: create group with admin1 only.
        harness.modifyGroupsViaLibrary(_buildModificationsArray(_createModification(groupId, buildArray(admin1))));

        // Call: query membership for non-member address.
        bool actualIsGroupMember = harness.isGroupMemberViaLibrary(groupId, admin2);

        // Verify: non-member address should return false.
        assertFalse(actualIsGroupMember, "non-member should return false");
    }

    /// @dev Verifies desired behavior that non-existent groups always return false for membership queries.
    function test_isGroupMember_nonExistentGroup_returnsFalse() public view {
        uint256 groupId = 7306;

        // Call: query membership against a non-existent group.
        bool actualIsGroupMember = harness.isGroupMemberViaLibrary(groupId, admin1);

        // Verify: non-existent group should return false.
        assertFalse(actualIsGroupMember, "non-existent group membership query should return false");
    }

    /// @dev Verifies `isGroupMember` returns false when membership bit is true but group is inactive.
    function test_isGroupMember_fudgedGhostBitWithInactiveGroup_returnsFalse() public {
        uint256 groupId = 7309;

        // Setup: fudge state directly so membership bit is true while group remains inactive.
        groupsStateHarness.setGroupStatus(groupId, false);
        groupsStateHarness.setGroupMemberStatus(groupId, admin1, true);

        // Sanity-check: raw storage has the ghost membership bit set.
        assertTrue(groupsStateHarness.getGroupMemberStatus(groupId, admin1), "precondition: ghost bit should be set");

        // Call: query through library view wrapper.
        bool actualIsGroupMember = harness.isGroupMemberViaLibrary(groupId, admin1);

        // Verify: inactive groups must never report active membership.
        assertFalse(actualIsGroupMember, "inactive group should not report membership even if storage bit is true");
    }

    /// @dev Verifies desired behavior that deleted groups return false even if ghost membership data exists.
    function test_isGroupMember_deletedGroupWithGhostData_returnsFalse() public {
        uint256 groupId = 7307;

        // Setup: create then delete group; membership mapping entry remains as ghost data.
        harness.modifyGroupsViaLibrary(_buildModificationsArray(_createModification(groupId, buildArray(admin1))));
        harness.modifyGroupsViaLibrary(_buildModificationsArray(_deleteModification(groupId)));

        // Call: query membership after deletion.
        bool actualIsGroupMember = harness.isGroupMemberViaLibrary(groupId, admin1);

        // Desired behavior: deleted groups should not report active membership.
        assertFalse(actualIsGroupMember, "deleted group should not leak ghost membership via isGroupMember");
    }

    /// @dev Verifies desired behavior that active group membership implies current org membership and active group.
    function test_isGroupMember_inactiveOrgMemberOrDeletedGroup_neverReturnsTrue() public {
        uint256 groupId = 7308;

        // Setup: create group with admin1 as a member, then remove org membership.
        harness.modifyGroupsViaLibrary(_buildModificationsArray(_createModification(groupId, buildArray(admin1))));
        groupsStateHarness.setMemberStatus(admin1, false);

        // Call: query while group is active but org membership is inactive.
        bool actualWhileOrgMemberInactive = harness.isGroupMemberViaLibrary(groupId, admin1);

        // Desired behavior: group membership should not be true when org membership is inactive.
        assertFalse(actualWhileOrgMemberInactive, "inactive org member should not be treated as active group member");

        // Setup: delete the group and query again.
        harness.modifyGroupsViaLibrary(_buildModificationsArray(_deleteModification(groupId)));

        // Call: query membership after deletion.
        bool actualAfterDeletion = harness.isGroupMemberViaLibrary(groupId, admin1);

        // Desired behavior: deleted groups should never report active membership.
        assertFalse(actualAfterDeletion, "deleted group should not report active membership");
    }
}
