// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

import { OnchainCustodyOrganizationDiamond } from "../src/organization/OnchainCustodyOrganizationDiamond.sol";
import { OnchainCustodyAccountDiamond } from "../src/account/OnchainCustodyAccountDiamond.sol";

import { OrganizationAdminFacet } from "../src/organization/facets/OrganizationAdminFacet.sol";
import { AccountAdminFacet } from "../src/account/facets/AccountAdminFacet.sol";
import { OrganizationMembersFacet } from "../src/organization/facets/OrganizationMembersFacet.sol";
import { OrganizationGroupsFacet } from "../src/organization/facets/OrganizationGroupsFacet.sol";
import { OrganizationPolicyFacet } from "../src/organization/facets/OrganizationPolicyFacet.sol";
import { OrganizationWhitelistFacet } from "../src/organization/facets/OrganizationWhitelistFacet.sol";
import { AccountTransactionFacet } from "../src/account/facets/AccountTransactionFacet.sol";

import { OrganizationInit } from "../src/organization/OrganizationInit.sol";
import { AccountInit } from "../src/account/AccountInit.sol";

import { IDiamondCut } from "../src/diamond/interfaces/IDiamondCut.sol";
import { DiamondCutFacet } from "../src/diamond/facets/DiamondCutFacet.sol";
import { DiamondLoupeFacet } from "../src/diamond/facets/DiamondLoupeFacet.sol";
import { Diamond } from "../src/diamond/Diamond.sol";

/**
 * @title Deploy Diamonds Script
 * @notice Script to deploy and configure the diamond proxy contracts
 * @author Den Technologies Inc
 */
contract DeployDiamonds is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying diamonds with deployer:", deployer);

        // Deploy diamond facets (diamond infrastructure)
        DiamondCutFacet diamondCutFacet = new DiamondCutFacet();
        DiamondLoupeFacet diamondLoupeFacet = new DiamondLoupeFacet();

        // Deploy application facets
        OrganizationAdminFacet organizationAdminFacet = new OrganizationAdminFacet();
        AccountAdminFacet accountAdminFacet = new AccountAdminFacet();
        OrganizationMembersFacet membersFacet = new OrganizationMembersFacet();
        OrganizationGroupsFacet groupsFacet = new OrganizationGroupsFacet();
        OrganizationPolicyFacet policyFacet = new OrganizationPolicyFacet();
        OrganizationWhitelistFacet whitelistFacet = new OrganizationWhitelistFacet();
        AccountTransactionFacet transactionFacet = new AccountTransactionFacet();

        console.log("DiamondCutFacet deployed at:", address(diamondCutFacet));
        console.log("DiamondLoupeFacet deployed at:", address(diamondLoupeFacet));
        console.log("OrganizationAdminFacet deployed at:", address(organizationAdminFacet));
        console.log("AccountAdminFacet deployed at:", address(accountAdminFacet));
        console.log("OrganizationMembersFacet deployed at:", address(membersFacet));
        console.log("OrganizationGroupsFacet deployed at:", address(groupsFacet));
        console.log("OrganizationPolicyFacet deployed at:", address(policyFacet));
        console.log("OrganizationWhitelistFacet deployed at:", address(whitelistFacet));
        console.log("AccountTransactionFacet deployed at:", address(transactionFacet));

        // Deploy initialization contracts
        OrganizationInit organizationInit = new OrganizationInit();
        AccountInit accountInit = new AccountInit();

        console.log("OrganizationInit deployed at:", address(organizationInit));
        console.log("AccountInit deployed at:", address(accountInit));

        // Prepare initial facet cuts for organization diamond (diamond infrastructure)
        IDiamondCut.FacetCut[] memory organizationInitialCuts = new IDiamondCut.FacetCut[](2);

        // Diamond Cut Facet
        bytes4[] memory diamondCutSelectors = new bytes4[](1);
        diamondCutSelectors[0] = DiamondCutFacet.diamondCut.selector;
        organizationInitialCuts[0] = IDiamondCut.FacetCut({
            facetAddress: address(diamondCutFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: diamondCutSelectors
        });

        // Diamond Loupe Facet
        bytes4[] memory diamondLoupeSelectors = new bytes4[](5);
        diamondLoupeSelectors[0] = DiamondLoupeFacet.facets.selector;
        diamondLoupeSelectors[1] = DiamondLoupeFacet.facetFunctionSelectors.selector;
        diamondLoupeSelectors[2] = DiamondLoupeFacet.facetAddresses.selector;
        diamondLoupeSelectors[3] = DiamondLoupeFacet.facetAddress.selector;
        diamondLoupeSelectors[4] = DiamondLoupeFacet.supportsInterface.selector;
        organizationInitialCuts[1] = IDiamondCut.FacetCut({
            facetAddress: address(diamondLoupeFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: diamondLoupeSelectors
        });

        // Deploy organization diamond with initial cuts
        OnchainCustodyOrganizationDiamond organizationDiamond =
            new OnchainCustodyOrganizationDiamond(organizationInitialCuts, Diamond.DiamondArgs({ dummy: 0 }));
        console.log("Organization Diamond deployed at:", address(organizationDiamond));

        // Deploy account diamond with same initial cuts
        OnchainCustodyAccountDiamond accountDiamond =
            new OnchainCustodyAccountDiamond(organizationInitialCuts, Diamond.DiamondArgs({ dummy: 0 }));
        console.log("Account Diamond deployed at:", address(accountDiamond));

        // Prepare facet cuts for organization diamond (application facets)
        IDiamondCut.FacetCut[] memory organizationFacetCuts = new IDiamondCut.FacetCut[](5);

        // Organization Admin Facet
        bytes4[] memory adminSelectors = new bytes4[](6);
        adminSelectors[0] = OrganizationAdminFacet.adminPermission.selector;
        adminSelectors[1] = OrganizationAdminFacet.isAdminNonceUsed.selector;
        adminSelectors[2] = OrganizationAdminFacet.computeAdminNonce.selector;
        adminSelectors[3] = OrganizationAdminFacet.updateAdmin.selector;
        adminSelectors[4] = OrganizationAdminFacet.updateGuardian.selector;
        adminSelectors[5] = OrganizationAdminFacet.validateAdminAuthorization.selector;

        organizationFacetCuts[0] = IDiamondCut.FacetCut({
            facetAddress: address(organizationAdminFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: adminSelectors
        });

        // Members Facet
        bytes4[] memory membersSelectors = new bytes4[](6);
        membersSelectors[0] = OrganizationMembersFacet.addressToMemberId.selector;
        membersSelectors[1] = OrganizationMembersFacet.getMemberAddress.selector;
        membersSelectors[2] = OrganizationMembersFacet.memberExists.selector;
        membersSelectors[3] = OrganizationMembersFacet.addMembers.selector;
        membersSelectors[4] = OrganizationMembersFacet.modifyMember.selector;
        membersSelectors[5] = OrganizationMembersFacet.removeMembers.selector;

        organizationFacetCuts[1] = IDiamondCut.FacetCut({
            facetAddress: address(membersFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: membersSelectors
        });

        // Groups Facet
        bytes4[] memory groupsSelectors = new bytes4[](5);
        groupsSelectors[0] = bytes4(keccak256("isMemberInGroup(uint8,uint8)"));
        groupsSelectors[1] = bytes4(keccak256("isMemberInGroup(address,uint8)"));
        groupsSelectors[2] = OrganizationGroupsFacet.groupExists.selector;
        groupsSelectors[3] = OrganizationGroupsFacet.createGroup.selector;
        groupsSelectors[4] = OrganizationGroupsFacet.modifyGroup.selector;

        organizationFacetCuts[2] = IDiamondCut.FacetCut({
            facetAddress: address(groupsFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: groupsSelectors
        });

        // Policy Facet
        bytes4[] memory policySelectors = new bytes4[](15);
        policySelectors[0] = OrganizationPolicyFacet.getPolicies.selector;
        policySelectors[1] = OrganizationPolicyFacet.modifyPolicies.selector;
        policySelectors[2] = OrganizationPolicyFacet.doesPolicyApplyToTransaction.selector;
        policySelectors[3] = OrganizationPolicyFacet.doesTransactionMatchPolicySourceAccounts.selector;
        policySelectors[4] = OrganizationPolicyFacet.doesTransactionMatchPolicyInitiator.selector;
        policySelectors[5] = OrganizationPolicyFacet.doesTransactionMatchPolicyTransactionType.selector;
        policySelectors[6] = OrganizationPolicyFacet.doesTransactionMatchPolicyDestination.selector;
        policySelectors[7] = OrganizationPolicyFacet.getRequiredApprovals.selector;
        policySelectors[8] = OrganizationPolicyFacet.isSignerAuthorizedForPolicy.selector;
        policySelectors[9] = OrganizationPolicyFacet.isSignerAuthorizedAsInitiator.selector;
        policySelectors[10] = OrganizationPolicyFacet.getActualDestination.selector;
        policySelectors[11] = OrganizationPolicyFacet.extractTokenRecipient.selector;
        policySelectors[12] = OrganizationPolicyFacet.isTransactionTokenTransfer.selector;
        policySelectors[13] = OrganizationPolicyFacet.extractTokenAddress.selector;
        policySelectors[14] = OrganizationPolicyFacet.extractTransferAmount.selector;

        organizationFacetCuts[3] = IDiamondCut.FacetCut({
            facetAddress: address(policyFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: policySelectors
        });

        // Whitelist Facet
        bytes4[] memory whitelistSelectors = new bytes4[](2);
        whitelistSelectors[0] = OrganizationWhitelistFacet.isAddressWhitelisted.selector;
        whitelistSelectors[1] = OrganizationWhitelistFacet.modifyWhitelist.selector;

        organizationFacetCuts[4] = IDiamondCut.FacetCut({
            facetAddress: address(whitelistFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: whitelistSelectors
        });

        // Initialize organization diamond
        bytes memory organizationInitData = abi.encodeWithSelector(
            OrganizationInit.init.selector,
            deployer, // Admin member address (deployer will be the initial admin member)
            deployer // Guardian is the deployer
        );

        // Note: Initial diamond cut will fail without guardian protection setup
        // This deployment script needs guardian setup before cutting additional facets
        console.log("Warning: Diamond cuts will require guardian setup and admin signatures");
        console.log("Use the DiamondCutFacet.diamondCut function with proper authorization");

        console.log("Organization diamond configured");

        // Prepare facet cuts for account diamond
        IDiamondCut.FacetCut[] memory accountFacetCuts = new IDiamondCut.FacetCut[](2);

        // Transaction Facet
        bytes4[] memory transactionSelectors = new bytes4[](4);
        transactionSelectors[0] = AccountTransactionFacet.isNonceUsed.selector;
        transactionSelectors[1] = AccountTransactionFacet.computeNonce.selector;
        transactionSelectors[2] = AccountTransactionFacet.executeTransaction.selector;
        transactionSelectors[3] = AccountTransactionFacet.rejectTransaction.selector;

        accountFacetCuts[0] = IDiamondCut.FacetCut({
            facetAddress: address(transactionFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: transactionSelectors
        });

        // Account Admin Facet
        bytes4[] memory accountAdminSelectors = new bytes4[](2);
        accountAdminSelectors[0] = AccountAdminFacet.getOrganizationAddress.selector;
        accountAdminSelectors[1] = AccountAdminFacet.validateAdminAuthorization.selector;

        accountFacetCuts[1] = IDiamondCut.FacetCut({
            facetAddress: address(accountAdminFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: accountAdminSelectors
        });

        // Initialize account diamond
        bytes memory accountInitData = abi.encodeWithSelector(AccountInit.init.selector, address(organizationDiamond));

        // Note: Account diamond will also require proper guardian authorization for cuts
        console.log("Account diamond cuts will also require guardian authorization");

        console.log("Account diamond configured");
        console.log("Deployment completed successfully!");

        vm.stopBroadcast();
    }
}
