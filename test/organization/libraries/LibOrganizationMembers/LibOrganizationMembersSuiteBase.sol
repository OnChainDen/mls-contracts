// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibOrganizationMembersHarness
} from "test/organization/libraries/LibOrganizationMembers/LibOrganizationMembersHarness.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";
import {OrganizationAdminTestBase} from "test/organization/shared/OrganizationAdminTestBase.sol";

/**
 * @dev Shared deployment/setup harness for `LibOrganizationMembers` unit suites.
 *      Keeps section files focused on behavior assertions rather than repetitive fixture bootstrapping.
 */
abstract contract LibOrganizationMembersSuiteBase is OrganizationAdminTestBase {
    /// @dev Concrete harness used by all library-focused section suites.
    LibOrganizationMembersHarness internal harness;

    /**
     * @dev Deploys the library-focused harness for section suites.
     */
    function _deployHarness() internal override returns (OrganizationAdminStateHarness) {
        harness = new LibOrganizationMembersHarness();
        return OrganizationAdminStateHarness(address(harness));
    }
}
