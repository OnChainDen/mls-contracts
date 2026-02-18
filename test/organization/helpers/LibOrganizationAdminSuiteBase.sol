// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {LibOrganizationAdminHarness} from "test/organization/harness/LibOrganizationAdminHarness.sol";
import {OrganizationAdminStateHarness} from "test/organization/harness/OrganizationAdminStateHarness.sol";
import {OrganizationAdminTestBase} from "test/organization/helpers/OrganizationAdminTestBase.sol";

/**
 * @dev Shared deployment/setup harness for `LibOrganizationAdmin` unit suites.
 *      Keeps section files focused on behavior assertions rather than repetitive fixture bootstrapping.
 */
abstract contract LibOrganizationAdminSuiteBase is OrganizationAdminTestBase {
    /// @dev Concrete harness used by all library-focused section suites.
    LibOrganizationAdminHarness internal harness;

    /// @dev Common operation payload reused by auth-validation tests.
    bytes internal baseOperationData;

    /**
     * @dev Deploys the library-focused harness for section suites.
     */
    function _deployHarness() internal override returns (OrganizationAdminStateHarness) {
        harness = new LibOrganizationAdminHarness();
        return OrganizationAdminStateHarness(address(harness));
    }

    /**
     * @dev Initializes reusable baseline payload for authorization tests.
     */
    function setUp() public virtual override {
        super.setUp();
        // Shared payload keeps auth tests focused on signature/nonce behavior rather than payload shape.
        baseOperationData = abi.encode(bytes32("operation"), uint256(123));
    }
}
