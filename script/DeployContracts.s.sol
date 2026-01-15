// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccountImplementation} from "account/AccountImplementation.sol";
import {Script, console} from "forge-std/Script.sol";
import {
    ImplementationWhitelistImplementation
} from "implementation-whitelist/ImplementationWhitelistImplementation.sol";
import {OrganizationFactory} from "organization/OrganizationFactory.sol";
import {OrganizationImplementation} from "organization/OrganizationImplementation.sol";
import {ContractType} from "types/CommonTypes.sol";

/**
 * @title Deploy Contracts
 * @notice Script to deploy implementation contracts, whitelist, and factory
 * @author Den Technologies Inc
 */
contract DeployContracts is Script {
    /**
     * @notice Deploys all core contracts for the onchain custody system
     * @dev Deploys in order: ImplementationWhitelistImplementation, OrganizationImplementation,
     *      AccountImplementation, whitelists the implementations, and deploys OrganizationFactory.
     *      Requires PRIVATE_KEY environment variable to be set.
     */
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
        // Note: LibOrganizationAdmin, LibOrganizationInitialization, and LibOrganizationAccountSignature
        // are external libraries that Foundry will automatically deploy and link.
        // For production deployments, use --libraries flag to specify pre-deployed library addresses.
        OrganizationImplementation organizationImplementation = new OrganizationImplementation();
        console.log("OrganizationImplementation deployed at:", address(organizationImplementation));
        console.log("(External libraries were automatically deployed and linked)");

        // Deploy AccountImplementation
        AccountImplementation accountImplementation = new AccountImplementation();
        console.log("AccountImplementation deployed at:", address(accountImplementation));

        // Add implementations to whitelist
        address[] memory orgImpl = new address[](1);
        orgImpl[0] = address(organizationImplementation);
        address[] memory empty = new address[](0);
        whitelist.whitelistImplementations(ContractType.Organization, orgImpl, empty);
        console.log("Organization implementation whitelisted at:", address(organizationImplementation));

        address[] memory accImpl = new address[](1);
        accImpl[0] = address(accountImplementation);
        whitelist.whitelistImplementations(ContractType.Account, accImpl, empty);
        console.log("Account implementation whitelisted at:", address(accountImplementation));

        // Deploy OrganizationFactory
        OrganizationFactory factory = new OrganizationFactory(deployer);
        console.log("OrganizationFactory deployed at:", address(factory));

        vm.stopBroadcast();

        console.log("Deployment completed successfully!");
    }
}
