// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import "../src/organization/OnchainCustodyOrganizationDiamond.sol";
import "../src/diamond/interfaces/IDiamondCut.sol";
import "../src/diamond/Diamond.sol";

/**
 * @title Deploy
 * @notice Deployment script for the Onchain Custody system
 */
contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the OnchainCustodyOrganization contract
        IDiamondCut.FacetCut[] memory emptyFacetCuts = new IDiamondCut.FacetCut[](0);
        OnchainCustodyOrganizationDiamond onchainCustody =
            new OnchainCustodyOrganizationDiamond(emptyFacetCuts, deployer);
        console.log("OnchainCustodyOrganizationDiamond deployed at:", address(onchainCustody));

        vm.stopBroadcast();

        // Log deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("OnchainCustodyOrganizationDiamond Address:", address(onchainCustody));

        // Save deployment addresses to a file for future reference
        string memory deploymentInfo = string.concat(
            "{\n",
            '  "onchainCustodyOrganization": "',
            vm.toString(address(onchainCustody)),
            '",\n',
            '  "deployer": "',
            vm.toString(deployer),
            '"\n',
            "}"
        );

        vm.writeFile("./deployments/latest.json", deploymentInfo);
        console.log("\nDeployment info saved to ./deployments/latest.json");
    }
}
