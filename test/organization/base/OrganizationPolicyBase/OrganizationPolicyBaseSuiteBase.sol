// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    OrganizationPolicyBaseHarness
} from "test/organization/base/OrganizationPolicyBase/OrganizationPolicyBaseHarness.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";
import {OrganizationPolicyTestBase} from "test/organization/shared/OrganizationPolicyTestBase.sol";

/**
 * @dev Shared deployment/auth-builder helpers for `OrganizationPolicyBase` unit suites.
 */
abstract contract OrganizationPolicyBaseSuiteBase is OrganizationPolicyTestBase {
    /// @dev Concrete harness used by all base-contract-focused policy section suites.
    OrganizationPolicyBaseHarness internal harness;

    /**
     * @dev Deploys the base-contract-focused harness for section suites.
     */
    function _deployHarness() internal override returns (OrganizationAdminStateHarness) {
        harness = new OrganizationPolicyBaseHarness();
        return OrganizationAdminStateHarness(address(harness));
    }
}
