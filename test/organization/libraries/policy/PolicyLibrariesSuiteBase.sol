// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {PolicyLibrariesHarness} from "test/organization/libraries/policy/PolicyLibrariesHarness.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";
import {OrganizationPolicyTestBase} from "test/organization/shared/OrganizationPolicyTestBase.sol";

/**
 * @dev Shared deployment/setup harness for policy-library suites under `libraries/policy`.
 */
abstract contract PolicyLibrariesSuiteBase is OrganizationPolicyTestBase {
    /// @dev Concrete harness used by all policy-library section suites in this subtree.
    PolicyLibrariesHarness internal harness;

    /**
     * @dev Deploys the local policy-library harness for section suites.
     */
    function _deployHarness() internal override returns (OrganizationAdminStateHarness) {
        harness = new PolicyLibrariesHarness();
        return OrganizationAdminStateHarness(address(harness));
    }

    /**
     * @dev Marks a set of addresses as organization members.
     */
    function _setMembersAsOrgMembers(address[] memory members) internal {
        for (uint256 i = 0; i < members.length; i++) {
            policyStateHarness.setMemberStatus(members[i], true);
        }
    }

    /**
     * @dev Creates an active group and marks all provided addresses as group members and org members.
     */
    function _setActiveGroupWithMembers(uint256 groupId, address[] memory members) internal {
        policyStateHarness.setGroupStatus(groupId, true);
        for (uint256 i = 0; i < members.length; i++) {
            policyStateHarness.setMemberStatus(members[i], true);
            policyStateHarness.setGroupMemberStatus(groupId, members[i], true);
        }
    }
}
