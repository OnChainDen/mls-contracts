// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibOrganizationGroupsHarness
} from "test/organization/libraries/LibOrganizationGroups/LibOrganizationGroupsHarness.sol";
import {
    LibOrganizationGroupsInvariantHandler
} from "test/organization/libraries/LibOrganizationGroups/LibOrganizationGroupsInvariantHandler.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";
import {OrganizationGroupsTestBase} from "test/organization/shared/OrganizationGroupsTestBase.sol";

/**
 * @dev Stateful invariant tests for `LibOrganizationGroups` behavior.
 */
contract LibOrganizationGroupsInvariants is OrganizationGroupsTestBase {
    /// @dev Concrete harness under invariant test.
    LibOrganizationGroupsHarness internal harness;

    /// @dev Stateful mutation handler.
    LibOrganizationGroupsInvariantHandler internal handler;

    /**
     * @dev Deploys the library-focused harness for this suite.
     */
    function _deployHarness() internal override returns (OrganizationAdminStateHarness) {
        harness = new LibOrganizationGroupsHarness();
        return OrganizationAdminStateHarness(address(harness));
    }

    /**
     * @dev Deploys handler and registers it as fuzz target.
     */
    function setUp() public override {
        super.setUp();

        handler = new LibOrganizationGroupsInvariantHandler(harness, admin1, admin2, address(0xE701));

        // Register only handler operations as stateful fuzz targets.
        targetContract(address(handler));
    }

    /// @dev Verifies invariant: deleted marker implies group is inactive.
    function invariant_wasGroupDeletedImpliesGroupInactive() public view {
        uint256 count = handler.trackedGroupCount();
        for (uint256 i = 0; i < count; i++) {
            uint256 groupId = handler.trackedGroupIdAt(i);
            if (harness.getWasGroupDeletedStatus(groupId)) {
                assertFalse(harness.isGroupViaLibrary(groupId), "deleted groups must remain inactive");
            }
        }
    }

    /// @dev Verifies invariant: `wasGroupDeleted` is monotonic (`false -> true` only).
    function invariant_wasGroupDeletedMonotonic() public view {
        uint256 count = handler.trackedGroupCount();
        for (uint256 i = 0; i < count; i++) {
            uint256 groupId = handler.trackedGroupIdAt(i);
            if (handler.modelWasDeletedEver(groupId)) {
                assertTrue(harness.getWasGroupDeletedStatus(groupId), "deleted marker should never revert to false");
            }
        }
    }

    /// @dev Verifies invariant: zero address can never be marked as a group member.
    function invariant_zeroAddressNeverBecomesGroupMember() public view {
        uint256 count = handler.trackedGroupCount();
        for (uint256 i = 0; i < count; i++) {
            uint256 groupId = handler.trackedGroupIdAt(i);
            assertFalse(
                harness.isGroupMemberViaLibrary(groupId, address(0)),
                "zero address must never be an active group member"
            );
        }
    }

    /// @dev Verifies desired invariant: active group membership implies active organization membership.
    function invariant_activeGroupMembershipImpliesOrgMembership() public view {
        uint256 groupCount = handler.trackedGroupCount();
        uint256 memberCount = handler.trackedMemberCount();

        for (uint256 i = 0; i < groupCount; i++) {
            uint256 groupId = handler.trackedGroupIdAt(i);

            if (!harness.isGroupViaLibrary(groupId)) {
                continue;
            }

            for (uint256 j = 0; j < memberCount; j++) {
                address member = handler.trackedMemberAt(j);
                if (harness.isGroupMemberViaLibrary(groupId, member)) {
                    assertTrue(
                        harness.getMemberStatus(member), "active group membership should imply active org membership"
                    );
                }
            }
        }
    }
}
