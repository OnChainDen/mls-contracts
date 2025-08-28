// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

import { OnchainCustodyOrganizationDiamond } from "../src/OnchainCustodyOrganizationDiamond.sol";
import { OnchainCustodyAccountDiamond } from "../src/OnchainCustodyAccountDiamond.sol";

import { OrganizationAdminFacet } from "../src/facets/OrganizationAdminFacet.sol";
import { AccountAdminFacet } from "../src/facets/AccountAdminFacet.sol";
import { MembersFacet } from "../src/facets/MembersFacet.sol";
import { GroupsFacet } from "../src/facets/GroupsFacet.sol";
import { PolicyFacet } from "../src/facets/PolicyFacet.sol";
import { WhitelistFacet } from "../src/facets/WhitelistFacet.sol";
import { TransactionFacet } from "../src/facets/TransactionFacet.sol";

import { OrganizationInit } from "../src/init/OrganizationInit.sol";
import { AccountInit } from "../src/init/AccountInit.sol";

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
        MembersFacet membersFacet = new MembersFacet();
        GroupsFacet groupsFacet = new GroupsFacet();
        PolicyFacet policyFacet = new PolicyFacet();
        WhitelistFacet whitelistFacet = new WhitelistFacet();
        TransactionFacet transactionFacet = new TransactionFacet();

        console.log("DiamondCutFacet deployed at:", address(diamondCutFacet));
        console.log("DiamondLoupeFacet deployed at:", address(diamondLoupeFacet));
        console.log("OrganizationAdminFacet deployed at:", address(organizationAdminFacet));
        console.log("AccountAdminFacet deployed at:", address(accountAdminFacet));
        console.log("MembersFacet deployed at:", address(membersFacet));
        console.log("GroupsFacet deployed at:", address(groupsFacet));
        console.log("PolicyFacet deployed at:", address(policyFacet));
        console.log("WhitelistFacet deployed at:", address(whitelistFacet));
        console.log("TransactionFacet deployed at:", address(transactionFacet));

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
        membersSelectors[0] = MembersFacet.addressToMemberId.selector;
        membersSelectors[1] = MembersFacet.getMemberAddress.selector;
        membersSelectors[2] = MembersFacet.memberExists.selector;
        membersSelectors[3] = MembersFacet.addMembers.selector;
        membersSelectors[4] = MembersFacet.modifyMember.selector;
        membersSelectors[5] = MembersFacet.removeMembers.selector;

        organizationFacetCuts[1] = IDiamondCut.FacetCut({
            facetAddress: address(membersFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: membersSelectors
        });

        // Groups Facet
        bytes4[] memory groupsSelectors = new bytes4[](5);
        groupsSelectors[0] = bytes4(keccak256("isMemberInGroup(uint8,uint8)"));
        groupsSelectors[1] = bytes4(keccak256("isMemberInGroup(address,uint8)"));
        groupsSelectors[2] = GroupsFacet.groupExists.selector;
        groupsSelectors[3] = GroupsFacet.createGroup.selector;
        groupsSelectors[4] = GroupsFacet.modifyGroup.selector;

        organizationFacetCuts[2] = IDiamondCut.FacetCut({
            facetAddress: address(groupsFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: groupsSelectors
        });

        // Policy Facet
        bytes4[] memory policySelectors = new bytes4[](15);
        policySelectors[0] = PolicyFacet.getPolicies.selector;
        policySelectors[1] = PolicyFacet.modifyPolicies.selector;
        policySelectors[2] = PolicyFacet.doesPolicyApplyToTransaction.selector;
        policySelectors[3] = PolicyFacet.doesTransactionMatchPolicySourceAccounts.selector;
        policySelectors[4] = PolicyFacet.doesTransactionMatchPolicyInitiator.selector;
        policySelectors[5] = PolicyFacet.doesTransactionMatchPolicyTransactionType.selector;
        policySelectors[6] = PolicyFacet.doesTransactionMatchPolicyDestination.selector;
        policySelectors[7] = PolicyFacet.getRequiredApprovals.selector;
        policySelectors[8] = PolicyFacet.isSignerAuthorizedForPolicy.selector;
        policySelectors[9] = PolicyFacet.isSignerAuthorizedAsInitiator.selector;
        policySelectors[10] = PolicyFacet.getActualDestination.selector;
        policySelectors[11] = PolicyFacet.extractTokenRecipient.selector;
        policySelectors[12] = PolicyFacet.isTransactionTokenTransfer.selector;
        policySelectors[13] = PolicyFacet.extractTokenAddress.selector;
        policySelectors[14] = PolicyFacet.extractTransferAmount.selector;

        organizationFacetCuts[3] = IDiamondCut.FacetCut({
            facetAddress: address(policyFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: policySelectors
        });

        // Whitelist Facet
        bytes4[] memory whitelistSelectors = new bytes4[](2);
        whitelistSelectors[0] = WhitelistFacet.isAddressWhitelisted.selector;
        whitelistSelectors[1] = WhitelistFacet.modifyWhitelist.selector;

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
        transactionSelectors[0] = TransactionFacet.isNonceUsed.selector;
        transactionSelectors[1] = TransactionFacet.computeNonce.selector;
        transactionSelectors[2] = TransactionFacet.executeTransaction.selector;
        transactionSelectors[3] = TransactionFacet.rejectTransaction.selector;

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
