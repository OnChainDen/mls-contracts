// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {OrganizationAccountSignatureBase} from "organization/base/OrganizationAccountSignatureBase.sol";
import {OrganizationPolicyStateHarness} from "test/organization/shared/OrganizationPolicyStateHarness.sol";

/**
 * @dev Base-contract-focused test harness for `OrganizationAccountSignatureBase`.
 *      Combines shared policy/account state setters with real external base-contract entry points.
 */
contract OrganizationAccountSignatureBaseHarness is OrganizationPolicyStateHarness, OrganizationAccountSignatureBase {}
