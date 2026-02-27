// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

import {IOrganizationAccountFactory} from "interfaces/organization/IOrganizationAccountFactory.sol";
import {LibOrganizationAccountFactory} from "organization/libraries/LibOrganizationAccountFactory.sol";
import {
    LibOrganizationAccountFactoryStorage
} from "organization/libraries/storage/LibOrganizationAccountFactoryStorage.sol";
import {
    OrganizationAccountFactoryStateHarness
} from "test/organization/shared/OrganizationAccountFactoryStateHarness.sol";

/**
 * @dev Library-focused test harness for `LibOrganizationAccountFactory`.
 *      Exposes wrappers around public/internal helper functions.
 */
contract LibOrganizationAccountFactoryHarness is OrganizationAccountFactoryStateHarness {
    /**
     * @dev Wrapper around `setAccountImplementation`.
     */
    function setAccountImplementationViaLibrary(address newImplementation) external {
        LibOrganizationAccountFactory.setAccountImplementation(newImplementation);
    }

    /**
     * @dev Wrapper around `deployAccount`.
     */
    function deployAccountViaLibrary(bytes32 create2Salt) external returns (address) {
        return LibOrganizationAccountFactory.deployAccount(create2Salt);
    }

    /**
     * @dev Wrapper around `computeAccountAddress`.
     */
    function computeAccountAddressViaLibrary(bytes32 salt) external view returns (address) {
        return LibOrganizationAccountFactory.computeAccountAddress(salt);
    }

    /**
     * @dev Wrapper around `isAccountDeployedByOrganization`.
     */
    function isAccountDeployedByOrganizationViaLibrary(address accountAddress) external view returns (bool) {
        return LibOrganizationAccountFactory.isAccountDeployedByOrganization(accountAddress);
    }

    /**
     * @dev Wrapper around `validateIsAccountDeployedByOrgOrRevert`.
     */
    function validateIsAccountDeployedByOrgOrRevertViaLibrary(address accountAddress) external view {
        LibOrganizationAccountFactory.validateIsAccountDeployedByOrgOrRevert(accountAddress);
    }

    /**
     * @dev Wrapper around `_getAccountProxyBytecode`.
     */
    function getAccountProxyBytecodeViaLibrary() external view returns (bytes memory) {
        return LibOrganizationAccountFactory._getAccountProxyBytecode();
    }

    /**
     * @dev Fault-injected deploy wrapper used to exercise the defensive mismatch revert path.
     */
    function deployAccountViaInjectedAddressMismatch(bytes32 create2Salt) external returns (address accountAddress) {
        bytes memory bytecode = LibOrganizationAccountFactory._getAccountProxyBytecode();

        accountAddress = Create2.deploy(0, create2Salt, bytecode);

        if (accountAddress != LibOrganizationAccountFactory.computeAccountAddress(bytes32(uint256(create2Salt) + 1))) {
            revert IOrganizationAccountFactory.AccountDeploymentAddressMismatch();
        }

        LibOrganizationAccountFactoryStorage.layout().deployedAccounts[accountAddress] = true;
        emit IOrganizationAccountFactory.AccountDeployed(accountAddress, address(this), create2Salt);
    }

    /**
     * @dev Beacon implementation getter used by AccountProxy constructor validation.
     */
    function implementation() external view returns (address) {
        return LibOrganizationAccountFactoryStorage.layout().accountImplementation;
    }
}
