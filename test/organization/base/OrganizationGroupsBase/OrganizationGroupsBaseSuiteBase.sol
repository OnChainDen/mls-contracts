// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    OrganizationGroupsBaseHarness
} from "test/organization/base/OrganizationGroupsBase/OrganizationGroupsBaseHarness.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";
import {OrganizationGroupsTestBase} from "test/organization/shared/OrganizationGroupsTestBase.sol";

/**
 * @dev Shared deployment/auth-builder helpers for `OrganizationGroupsBase` unit suites.
 */
abstract contract OrganizationGroupsBaseSuiteBase is OrganizationGroupsTestBase {
    /// @dev Concrete harness used by all base-contract-focused section suites.
    OrganizationGroupsBaseHarness internal harness;

    /**
     * @dev Deploys the base-contract-focused harness for section suites.
     */
    function _deployHarness() internal override returns (OrganizationAdminStateHarness) {
        harness = new OrganizationGroupsBaseHarness();
        return OrganizationAdminStateHarness(address(harness));
    }
}
