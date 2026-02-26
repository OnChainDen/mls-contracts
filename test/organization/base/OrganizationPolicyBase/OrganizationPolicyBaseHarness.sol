// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {OrganizationPolicyBase} from "organization/base/OrganizationPolicyBase.sol";
import {OrganizationPolicyStateHarness} from "test/organization/shared/OrganizationPolicyStateHarness.sol";

/**
 * @dev Base-contract-focused test harness for `OrganizationPolicyBase`.
 *      Combines shared state surface with real external base-contract entry points.
 */
contract OrganizationPolicyBaseHarness is OrganizationPolicyStateHarness, OrganizationPolicyBase {}
