// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibOrganizationPolicyHarness
} from "test/organization/libraries/LibOrganizationPolicy/LibOrganizationPolicyHarness.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";
import {OrganizationPolicyTestBase} from "test/organization/shared/OrganizationPolicyTestBase.sol";

/**
 * @dev Shared deployment/setup harness for policy-library-focused suites.
 */
abstract contract LibOrganizationPolicySuiteBase is OrganizationPolicyTestBase {
    /// @dev Concrete harness used by all policy-library-focused section suites.
    LibOrganizationPolicyHarness internal harness;

    /**
     * @dev Deploys the policy-library-focused harness for section suites.
     */
    function _deployHarness() internal override returns (OrganizationAdminStateHarness) {
        harness = new LibOrganizationPolicyHarness();
        return OrganizationAdminStateHarness(address(harness));
    }
}
