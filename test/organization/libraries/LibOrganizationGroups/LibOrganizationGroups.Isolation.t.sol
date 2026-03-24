// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibOrganizationGroupsSuiteBase
} from "test/organization/libraries/LibOrganizationGroups/LibOrganizationGroupsSuiteBase.sol";

/**
 * @dev Cross-library isolation tests for `LibOrganizationGroups`.
 */
contract LibOrganizationGroupsIsolationTest is LibOrganizationGroupsSuiteBase {
    /// @dev Verifies `LibOrganizationGroups.modifyGroups` does not change admin counters, threshold, or existing
    /// admin/member flags while creating, updating, and deleting groups.
    function test_modifyGroups_doesNotAlterAdminCountersThresholdOrMembershipFlags() public {
        // Setup: seed a two-admin organization with one extra member, snapshot the admin/member state, and build a
        // create-update-delete sequence against a single group ID.
        _setMembersAndAdmins({
            members: buildArray(admin1, admin2, admin3), admins: buildArray(admin1, admin2), threshold: 2
        });

        uint256 expectedAdminCount = harness.getAdminCount();
        uint256 expectedThreshold = harness.getVotingThreshold();
        bool expectedAdmin1 = harness.getAdminStatus(admin1);
        bool expectedAdmin2 = harness.getAdminStatus(admin2);
        bool expectedAdmin3 = harness.getAdminStatus(admin3);
        bool expectedMember1 = harness.getMemberStatus(admin1);
        bool expectedMember2 = harness.getMemberStatus(admin2);
        bool expectedMember3 = harness.getMemberStatus(admin3);

        // Call: create a group, mutate its membership, then delete it through the library entry point.
        harness.modifyGroupsViaLibrary(_buildModificationsArray(_createModification(77, buildArray(admin3))));
        harness.modifyGroupsViaLibrary(
            _buildModificationsArray(_updateModification(77, buildArray(admin1), buildArray(admin3)))
        );
        harness.modifyGroupsViaLibrary(_buildModificationsArray(_deleteModification(77)));

        // Verify: group mutations do not directly change admin count, threshold, or preexisting admin/member flags.
        assertEq(harness.getAdminCount(), expectedAdminCount, "group changes must not alter admin count");
        assertEq(harness.getVotingThreshold(), expectedThreshold, "group changes must not alter voting threshold");
        assertEq(harness.getAdminStatus(admin1), expectedAdmin1, "group changes must not alter admin1 status");
        assertEq(harness.getAdminStatus(admin2), expectedAdmin2, "group changes must not alter admin2 status");
        assertEq(harness.getAdminStatus(admin3), expectedAdmin3, "group changes must not alter admin3 status");
        assertEq(harness.getMemberStatus(admin1), expectedMember1, "group changes must not alter admin1 membership");
        assertEq(harness.getMemberStatus(admin2), expectedMember2, "group changes must not alter admin2 membership");
        assertEq(harness.getMemberStatus(admin3), expectedMember3, "group changes must not alter admin3 membership");
    }
}
