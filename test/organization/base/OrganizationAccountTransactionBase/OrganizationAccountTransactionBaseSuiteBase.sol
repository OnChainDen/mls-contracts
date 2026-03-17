// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    OrganizationAccountTransactionBaseHarness
} from "test/organization/base/OrganizationAccountTransactionBase/OrganizationAccountTransactionBaseHarness.sol";
import {
    OrganizationAccountTransactionTestBase
} from "test/organization/shared/OrganizationAccountTransactionTestBase.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";

/**
 * @dev Shared deployment/setup helpers for `OrganizationAccountTransactionBase` suites.
 */
abstract contract OrganizationAccountTransactionBaseSuiteBase is OrganizationAccountTransactionTestBase {
    /// @dev Concrete harness used by account-transaction base-contract suites.
    OrganizationAccountTransactionBaseHarness internal harness;

    /**
     * @dev Deploys the base-contract-focused account-transaction harness.
     */
    function _deployHarness() internal override returns (OrganizationAdminStateHarness) {
        harness = new OrganizationAccountTransactionBaseHarness();
        return OrganizationAdminStateHarness(address(harness));
    }
}
