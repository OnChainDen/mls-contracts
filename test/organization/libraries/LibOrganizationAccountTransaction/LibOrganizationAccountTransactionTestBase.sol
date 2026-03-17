// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibOrganizationAccountTransactionHarness
} from "test/organization/libraries/LibOrganizationAccountTransaction/LibOrganizationAccountTransactionHarness.sol";
import {
    OrganizationAccountTransactionTestBase
} from "test/organization/shared/OrganizationAccountTransactionTestBase.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";

/**
 * @dev Shared deployment/setup helpers for library-focused account-transaction suites.
 */
abstract contract LibOrganizationAccountTransactionTestBase is OrganizationAccountTransactionTestBase {
    /// @dev Concrete harness used by account-transaction library suites.
    LibOrganizationAccountTransactionHarness internal harness;

    /**
     * @dev Deploys the account-transaction library harness.
     */
    function _deployHarness() internal override returns (OrganizationAdminStateHarness) {
        harness = new LibOrganizationAccountTransactionHarness();
        return OrganizationAdminStateHarness(address(harness));
    }
}
