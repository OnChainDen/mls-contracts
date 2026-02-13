// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

import {AccountProxy} from "account/AccountProxy.sol";
import {IImplementationWhitelist} from "interfaces/IImplementationWhitelist.sol";
import {IOrganizationAccountFactory} from "interfaces/organization/IOrganizationAccountFactory.sol";
import {
    LibOrganizationAccountFactoryStorage
} from "organization/libraries/storage/LibOrganizationAccountFactoryStorage.sol";
import {LibOrganizationUpgradeStorage} from "organization/libraries/storage/LibOrganizationUpgradeStorage.sol";
import {ContractType} from "types/CommonTypes.sol";

/**
 * @title Lib Organization Account Factory
 * @dev Library for deploying Account contracts as BeaconProxies with the Organization as the beacon.
 *      This library should ONLY be used by Organization contracts.
 * @author Den Technologies Inc
 */
library LibOrganizationAccountFactory {
    /**
     * @dev Validates and sets the account implementation address.
     *      Reverts if the implementation is not whitelisted for account contracts.
     * @param newImplementation The new account implementation address
     */
    function setAccountImplementation(address newImplementation) internal {
        // Validate implementation against whitelist
        // forgefmt: disable-next-item
        IImplementationWhitelist(LibOrganizationUpgradeStorage.layout().whitelistAddress)
            .validateIsImplementationWhitelistedOrRevert(
                ContractType.Account,
                newImplementation
            );

        // Update the account implementation in storage
        LibOrganizationAccountFactoryStorage.layout().accountImplementation = newImplementation;
    }

    /**
     * @dev Deploys a new Account BeaconProxy at a deterministic address.
     *      Uses CREATE2 to ensure the same address across different chains.
     *      The Organization (this contract) acts as the beacon.
     * @param create2Salt The salt for CREATE2 deployment
     * @return accountAddress The address of the deployed account proxy
     */
    function deployAccount(bytes32 create2Salt) internal returns (address accountAddress) {
        bytes memory bytecode = _getAccountProxyBytecode();

        // Deploy the AccountProxy using CREATE2
        accountAddress = Create2.deploy(0, create2Salt, bytecode);

        // Case: The deployed address does not match the address we expected
        if (accountAddress != computeAccountAddress(create2Salt)) {
            revert IOrganizationAccountFactory.AccountDeploymentAddressMismatch();
        }

        // Mark the account as deployed by this organization
        LibOrganizationAccountFactoryStorage.layout().deployedAccounts[accountAddress] = true;

        emit IOrganizationAccountFactory.AccountDeployed(accountAddress, address(this), create2Salt);
    }

    /**
     * @dev Computes the address where an account proxy would be deployed
     * @param salt The salt for CREATE2 deployment
     * @return The computed address
     */
    function computeAccountAddress(bytes32 salt) internal view returns (address) {
        return Create2.computeAddress(salt, keccak256(_getAccountProxyBytecode()));
    }

    /**
     * @dev Checks if an account was deployed by this organization
     * @param accountAddress The address of the account to check
     * @return True if the account was deployed by this organization, false otherwise
     */
    function isAccountDeployedByOrganization(address accountAddress) internal view returns (bool) {
        return LibOrganizationAccountFactoryStorage.layout().deployedAccounts[accountAddress];
    }

    /**
     * @dev Validates that an account was deployed by this organization.
     *      Reverts with AccountNotDeployedByOrganization if the account was not deployed by this organization.
     * @param accountAddress The address of the account to validate
     */
    function validateIsAccountDeployedByOrgOrRevert(address accountAddress) internal view {
        if (!isAccountDeployedByOrganization(accountAddress)) {
            revert IOrganizationAccountFactory.AccountNotDeployedByOrganization(accountAddress);
        }
    }

    /// @dev Returns the creation bytecode for deploying an AccountProxy
    /// @return bytecode The creation bytecode to deploy via CREATE2
    function _getAccountProxyBytecode() internal view returns (bytes memory bytecode) {
        // Generate the bytecode to deploy the AccountProxy (which is a BeaconProxy) with the Organization
        // as the beacon (address(this)) and no initialization data (empty bytes)
        return abi.encodePacked(type(AccountProxy).creationCode, abi.encode(address(this), ""));
    }
}
