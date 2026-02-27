// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {OrganizationAccountFactoryBase} from "organization/base/OrganizationAccountFactoryBase.sol";
import {LibOrganizationAccountFactory} from "organization/libraries/LibOrganizationAccountFactory.sol";
import {
    OrganizationAccountFactoryStateHarness
} from "test/organization/shared/OrganizationAccountFactoryStateHarness.sol";

/**
 * @dev Base-contract-focused test harness for `OrganizationAccountFactoryBase`.
 *      Combines shared account-factory state setters with real external base-contract entry points.
 */
contract OrganizationAccountFactoryBaseHarness is OrganizationAccountFactoryStateHarness, OrganizationAccountFactoryBase {
    /**
     * @dev Wrapper around `LibOrganizationAccountFactory.computeAccountAddress`.
     */
    function computeAccountAddressViaLibraryWrapper(bytes32 salt) external view returns (address) {
        return LibOrganizationAccountFactory.computeAccountAddress(salt);
    }
}
