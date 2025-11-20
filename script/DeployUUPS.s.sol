// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { ImplementationWhitelist } from "../src/diamond/ImplementationWhitelist.sol";
import { OrganizationImplementation } from "../src/organization/OrganizationImplementation.sol";
import { AccountImplementation } from "../src/account/AccountImplementation.sol";
import { OrganizationFactory } from "../src/organization/OrganizationFactory.sol";
import { IAdminFacet, AdminType } from "../src/interfaces/IAdminFacet.sol";

/**
 * @title Deploy UUPS Contracts
 * @notice Script to deploy UUPS implementation contracts, whitelist, and factory
 * @author Den Technologies Inc
 */
contract DeployUUPS is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying UUPS contracts with deployer:", deployer);

        // Deploy ImplementationWhitelist
        ImplementationWhitelist whitelist = new ImplementationWhitelist(deployer);
        console.log("ImplementationWhitelist deployed at:", address(whitelist));

        // Deploy OrganizationImplementation
        OrganizationImplementation organizationImplementation = new OrganizationImplementation();
        console.log("OrganizationImplementation deployed at:", address(organizationImplementation));

        // Deploy AccountImplementation
        AccountImplementation accountImplementation = new AccountImplementation();
        console.log("AccountImplementation deployed at:", address(accountImplementation));

        // Add implementations to whitelist
        uint256 orgSetId = whitelist.addWhitelistedImplementationSet(
            ImplementationWhitelist.ContractType.Organization, address(organizationImplementation)
        );
        console.log("Organization implementation whitelisted with setId:", orgSetId);

        uint256 accountSetId = whitelist.addWhitelistedImplementationSet(
            ImplementationWhitelist.ContractType.Account, address(accountImplementation)
        );
        console.log("Account implementation whitelisted with setId:", accountSetId);

        // Deploy OrganizationFactory
        OrganizationFactory factory = new OrganizationFactory(deployer);
        console.log("OrganizationFactory deployed at:", address(factory));

        vm.stopBroadcast();

        console.log("Deployment completed successfully!");
    }
}
