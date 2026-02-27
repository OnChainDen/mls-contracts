// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    OrganizationAccountFactoryBaseHarness
} from "test/organization/base/OrganizationAccountFactoryBase/OrganizationAccountFactoryBaseHarness.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";
import {
    OrganizationAccountFactoryTestBase
} from "test/organization/shared/OrganizationAccountFactoryTestBase.sol";

/**
 * @dev Shared deployment/setup helpers for `OrganizationAccountFactoryBase` unit suites.
 */
abstract contract OrganizationAccountFactoryBaseSuiteBase is OrganizationAccountFactoryTestBase {
    /// @dev Concrete harness used by base-contract account-factory section suites.
    OrganizationAccountFactoryBaseHarness internal harness;

    /**
     * @dev Deploys the base-contract-focused account-factory harness.
     */
    function _deployHarness() internal override returns (OrganizationAdminStateHarness) {
        harness = new OrganizationAccountFactoryBaseHarness();
        return OrganizationAdminStateHarness(address(harness));
    }
}
