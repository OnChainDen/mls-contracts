// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {OrganizationGuardianRecoveryBase} from "organization/base/OrganizationGuardianRecoveryBase.sol";
import {
    OrganizationGuardianRecoveryStateHarness
} from "test/organization/shared/OrganizationGuardianRecoveryStateHarness.sol";

/**
 * @dev Base-contract-focused test harness for `OrganizationGuardianRecoveryBase`.
 *      Combines shared state surface with real external base-contract entry points.
 */
contract OrganizationGuardianRecoveryBaseHarness is
    OrganizationGuardianRecoveryStateHarness,
    OrganizationGuardianRecoveryBase
{}
