// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibOrganizationAccountFactoryHarness
} from "test/organization/libraries/LibOrganizationAccountFactory/LibOrganizationAccountFactoryHarness.sol";
import {OrganizationAccountFactoryTestBase} from "test/organization/shared/OrganizationAccountFactoryTestBase.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";

/**
 * @dev Shared deployment/setup harness for `LibOrganizationAccountFactory` suites.
 */
abstract contract LibOrganizationAccountFactorySuiteBase is OrganizationAccountFactoryTestBase {
    /// @dev Concrete harness used by account-factory library suites.
    LibOrganizationAccountFactoryHarness internal harness;

    /**
     * @dev Deploys the account-factory library harness.
     */
    function _deployHarness() internal override returns (OrganizationAdminStateHarness) {
        harness = new LibOrganizationAccountFactoryHarness();
        return OrganizationAdminStateHarness(address(harness));
    }
}
