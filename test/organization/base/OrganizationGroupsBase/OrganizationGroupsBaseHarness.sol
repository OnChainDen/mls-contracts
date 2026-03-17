// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {OrganizationGroupsBase} from "organization/base/OrganizationGroupsBase.sol";
import {OrganizationGroupsStateHarness} from "test/organization/shared/OrganizationGroupsStateHarness.sol";

/**
 * @dev Base-contract-focused test harness for `OrganizationGroupsBase`.
 *      Combines shared state surface with real external base-contract entry points.
 */
contract OrganizationGroupsBaseHarness is OrganizationGroupsStateHarness, OrganizationGroupsBase {}
