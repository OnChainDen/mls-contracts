// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibOrganizationAccountTransactionHarness
} from "test/organization/libraries/LibOrganizationAccountTransaction/LibOrganizationAccountTransactionHarness.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";
import {OrganizationPolicyTestBase} from "test/organization/shared/OrganizationPolicyTestBase.sol";

/**
 * @dev Shared deployment/setup harness for `LibOrganizationAccountTransaction` suites.
 */
abstract contract LibOrganizationAccountTransactionSuiteBase is OrganizationPolicyTestBase {
    /// @dev Concrete harness used by account-transaction policy suites.
    LibOrganizationAccountTransactionHarness internal harness;

    /**
     * @dev Deploys the account-transaction library harness.
     */
    function _deployHarness() internal override returns (OrganizationAdminStateHarness) {
        harness = new LibOrganizationAccountTransactionHarness();
        return OrganizationAdminStateHarness(address(harness));
    }
}
