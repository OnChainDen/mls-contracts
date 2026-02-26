// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibOrganizationAccountSignatureHarness
} from "test/organization/libraries/LibOrganizationAccountSignature/LibOrganizationAccountSignatureHarness.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";
import {OrganizationPolicyTestBase} from "test/organization/shared/OrganizationPolicyTestBase.sol";

/**
 * @dev Shared deployment/setup harness for `LibOrganizationAccountSignature` suites.
 */
abstract contract LibOrganizationAccountSignatureSuiteBase is OrganizationPolicyTestBase {
    /// @dev Concrete harness used by account-signature policy suites.
    LibOrganizationAccountSignatureHarness internal harness;

    /**
     * @dev Deploys the account-signature library harness.
     */
    function _deployHarness() internal override returns (OrganizationAdminStateHarness) {
        harness = new LibOrganizationAccountSignatureHarness();
        return OrganizationAdminStateHarness(address(harness));
    }
}
