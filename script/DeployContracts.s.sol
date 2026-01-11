// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccountImplementation} from "../src/account/AccountImplementation.sol";
import {ImplementationWhitelistImplementation} from
    "../src/implementation-whitelist/ImplementationWhitelistImplementation.sol";
import {IImplementationWhitelist} from "../src/implementation-whitelist/interfaces/IImplementationWhitelist.sol";
import {OrganizationFactory} from "../src/organization/OrganizationFactory.sol";
import {OrganizationImplementation} from "../src/organization/OrganizationImplementation.sol";
import {Script, console} from "forge-std/Script.sol";

/**
 * @title Deploy Contracts
 * @notice Script to deploy implementation contracts, whitelist, and factory
 * @author Den Technologies Inc
 */
contract DeployContracts is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying contracts with deployer:", deployer);

        // Deploy ImplementationWhitelistImplementation
        ImplementationWhitelistImplementation whitelist = new ImplementationWhitelistImplementation();
        whitelist.initialize(deployer);
        console.log("ImplementationWhitelistImplementation deployed at:", address(whitelist));

        // Deploy OrganizationImplementation
        OrganizationImplementation organizationImplementation = new OrganizationImplementation();
        console.log("OrganizationImplementation deployed at:", address(organizationImplementation));

        // Deploy AccountImplementation
        AccountImplementation accountImplementation = new AccountImplementation();
        console.log("AccountImplementation deployed at:", address(accountImplementation));

        // Add implementations to whitelist
        address[] memory orgImpl = new address[](1);
        orgImpl[0] = address(organizationImplementation);
        address[] memory empty = new address[](0);
        whitelist.whitelistImplementations(IImplementationWhitelist.ContractType.Organization, orgImpl, empty);
        console.log("Organization implementation whitelisted at:", address(organizationImplementation));

        address[] memory accImpl = new address[](1);
        accImpl[0] = address(accountImplementation);
        whitelist.whitelistImplementations(IImplementationWhitelist.ContractType.Account, accImpl, empty);
        console.log("Account implementation whitelisted at:", address(accountImplementation));

        // Deploy OrganizationFactory
        OrganizationFactory factory = new OrganizationFactory(deployer);
        console.log("OrganizationFactory deployed at:", address(factory));

        vm.stopBroadcast();

        console.log("Deployment completed successfully!");
    }
}
