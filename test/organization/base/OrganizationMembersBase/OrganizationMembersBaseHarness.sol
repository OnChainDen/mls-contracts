// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {OrganizationAdminBase} from "organization/base/OrganizationAdminBase.sol";
import {OrganizationMembersBase} from "organization/base/OrganizationMembersBase.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";

/**
 * @dev Base-contract-focused test harness for `OrganizationMembersBase`.
 *      Combines the shared state surface with the real external base contract entry points.
 */
contract OrganizationMembersBaseHarness is OrganizationAdminStateHarness, OrganizationMembersBase, OrganizationAdminBase {}
