// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {OrganizationGuardianBase} from "organization/base/OrganizationGuardianBase.sol";
import {OrganizationGuardianStateHarness} from "test/organization/shared/OrganizationGuardianStateHarness.sol";

/**
 * @dev Base-contract-focused test harness for `OrganizationGuardianBase`.
 *      Combines shared state surface with real external base-contract entry points.
 */
contract OrganizationGuardianBaseHarness is OrganizationGuardianStateHarness, OrganizationGuardianBase {}
