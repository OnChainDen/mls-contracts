// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibOrganizationGroupsHarness
} from "test/organization/libraries/LibOrganizationGroups/LibOrganizationGroupsHarness.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";
import {OrganizationGroupsTestBase} from "test/organization/shared/OrganizationGroupsTestBase.sol";

/**
 * @dev Shared deployment/setup harness for `LibOrganizationGroups` unit suites.
 */
abstract contract LibOrganizationGroupsSuiteBase is OrganizationGroupsTestBase {
    /// @dev Concrete harness used by all library-focused section suites.
    LibOrganizationGroupsHarness internal harness;

    /**
     * @dev Deploys the library-focused harness for section suites.
     */
    function _deployHarness() internal override returns (OrganizationAdminStateHarness) {
        harness = new LibOrganizationGroupsHarness();
        return OrganizationAdminStateHarness(address(harness));
    }
}
