// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    OrganizationAccountSignatureBaseHarness
} from "test/organization/base/OrganizationAccountSignatureBase/OrganizationAccountSignatureBaseHarness.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";
import {OrganizationPolicyTestBase} from "test/organization/shared/OrganizationPolicyTestBase.sol";

/**
 * @dev Shared deployment/setup helpers for `OrganizationAccountSignatureBase` unit suites.
 */
abstract contract OrganizationAccountSignatureBaseSuiteBase is OrganizationPolicyTestBase {
    /// @dev Concrete harness used by base-contract account-signature suites.
    OrganizationAccountSignatureBaseHarness internal harness;

    /**
     * @dev Deploys the base-contract-focused account-signature harness.
     */
    function _deployHarness() internal override returns (OrganizationAdminStateHarness) {
        harness = new OrganizationAccountSignatureBaseHarness();
        return OrganizationAdminStateHarness(address(harness));
    }
}
