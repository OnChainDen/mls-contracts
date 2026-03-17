// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganization} from "interfaces/IOrganization.sol";
import {OrganizationProxy} from "organization/OrganizationProxy.sol";
import {LibOrganizationUpgradeStorage} from "organization/libraries/storage/LibOrganizationUpgradeStorage.sol";
import {InitializationWhitelistMock} from "test/organization/OrganizationFactory/OrganizationFactoryHarnesses.sol";
import {
    InitializationSuiteBase
} from "test/organization/base/OrganizationInitializationBase/OrganizationInitializationBaseSuiteBase.sol";

/**
 * @dev Fuzz tests for `OrganizationProxy`.
 */
contract OrganizationProxyFuzzTest is InitializationSuiteBase {}
