// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccountProxy } from "../../account/AccountProxy.sol";
import { LibOrganizationAccountFactoryStorage } from "./storage/LibOrganizationAccountFactoryStorage.sol";

/**
 * @title Lib Organization Account Factory
 * @notice Library for deploying Account contracts as BeaconProxies with the Organization as the beacon
 * @dev This library should ONLY be used by Organization contracts
 * @author Den Technologies Inc
 */
library LibOrganizationAccountFactory {
    /**
     * @notice Emitted when a new account proxy is deployed
     * @param accountAddress The address of the deployed account proxy
     * @param organizationAddress The address of the organization that deployed it (beacon)
     * @param salt The salt used for CREATE2 deployment
     */
    event AccountDeployed(address indexed accountAddress, address indexed organizationAddress, bytes32 indexed salt);

    /**
     * @notice Error thrown when deployment fails
     */
    error AccountDeploymentFailed();

    /**
     * @notice Error thrown when the deployed address does not match the computed address
     */
    error AccountDeploymentAddressMismatch();

    /**
     * @notice Error thrown when an account was not deployed by this organization
     * @param accountAddress The address of the account that was not deployed by this organization
     */
    error AccountNotDeployedByOrganization(address accountAddress);

    /**
     * @notice Deploys a new Account BeaconProxy at a deterministic address
     * @dev Uses CREATE2 to ensure the same address across different chains.
     *      The Organization (this contract) acts as the beacon.
     * @param create2Salt The salt for CREATE2 deployment
     * @return accountAddress The address of the deployed account proxy
     */
    function deployAccount(bytes32 create2Salt) internal returns (address accountAddress) {
        // Generate the bytecode to deploy the AccountProxy (which is a BeaconProxy) with the Organization
        // as the beacon (address(this)) and no initialization data (empty bytes)
        bytes memory bytecode = abi.encodePacked(type(AccountProxy).creationCode, abi.encode(address(this), ""));

        // Deploy the AccountProxy using CREATE2
        assembly {
            accountAddress := create2(0, add(bytecode, 0x20), mload(bytecode), create2Salt)
        }

        // Case: Deployment failed
        if (accountAddress == address(0)) {
            revert AccountDeploymentFailed();
        }

        // Case: The deployed address does not match the address we expected
        if (accountAddress != computeAccountAddress(create2Salt)) {
            revert AccountDeploymentAddressMismatch();
        }

        // Mark the account as deployed by this organization
        LibOrganizationAccountFactoryStorage.layout().deployedAccounts[accountAddress] = true;

        emit AccountDeployed(accountAddress, address(this), create2Salt);
    }

    /**
     * @notice Computes the address where an account proxy would be deployed
     * @param salt The salt for CREATE2 deployment
     * @return The computed address
     */
    function computeAccountAddress(bytes32 salt) internal view returns (address) {
        bytes memory bytecode = abi.encodePacked(type(AccountProxy).creationCode, abi.encode(address(this), ""));

        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));

        return address(uint160(uint256(hash)));
    }

    /**
     * @notice Checks if an account was deployed by this organization
     * @param accountAddress The address of the account to check
     * @return True if the account was deployed by this organization, false otherwise
     */
    function isAccountDeployedByOrganization(address accountAddress) internal view returns (bool) {
        return LibOrganizationAccountFactoryStorage.layout().deployedAccounts[accountAddress];
    }
}
