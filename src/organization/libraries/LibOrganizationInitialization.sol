// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {IOrganizationInitialization} from "interfaces/organization/IOrganizationInitialization.sol";
import {LibOrganizationAdmin} from "organization/libraries/LibOrganizationAdmin.sol";
import {LibOrganizationAdminStorage} from "organization/libraries/storage/LibOrganizationAdminStorage.sol";
import {
    LibOrganizationDeployerAddressStorage
} from "organization/libraries/storage/LibOrganizationDeployerAddressStorage.sol";
import {LibOrganizationGroupsStorage} from "organization/libraries/storage/LibOrganizationGroupsStorage.sol";
import {LibOrganizationGuardianStorage} from "organization/libraries/storage/LibOrganizationGuardianStorage.sol";
import {LibOrganizationMembersStorage} from "organization/libraries/storage/LibOrganizationMembersStorage.sol";
import {AdminConfig, AllAdminsInOrgProofs} from "types/AdminTypes.sol";
import {InitializationParams} from "types/CommonTypes.sol";

/**
 * @title Lib Organization Initialization
 * @dev Library for post-deployment initialization of Organization contracts
 * @dev This library should ONLY be used by Organization contracts.
 *      Members and Groups are stored as Merkle trees - only the roots are stored on-chain.
 *      Full member/group data is stored off-chain (IPFS) and provided via calldata at validation time.
 * @author Den Technologies Inc
 */
library LibOrganizationInitialization {
    /**
     * @dev Initializes the organization contract with Merkle-based members/groups and admin configuration
     * @dev Deployer authorization is enforced by the external wrapper function.
     *      Members and groups are represented as Merkle trees - only roots are stored on-chain.
     *      Validates that all admin addresses are members to prevent bricking.
     * @param params The initialization parameters struct
     */
    function initialize(InitializationParams calldata params) public {
        // Check if already initialized
        if (isInitialized()) {
            revert IOrganizationInitialization.AlreadyInitialized();
        }

        // Validate members root is provided (organization must have at least one member)
        if (params.membersRoot == bytes32(0)) {
            revert IOrganizationInitialization.InvalidMembersRoot();
        }

        // Validate admin configuration
        LibOrganizationAdmin.validateAdminConfigurationOrRevert(
            params.adminsRoot, params.adminCount, params.votingThreshold
        );

        // Create proofs struct to verify all admins are in the organization
        // forgefmt: disable-next-item
        AllAdminsInOrgProofs memory allAdminsInOrgProofs =
            AllAdminsInOrgProofs({
                adminAddresses: params.adminAddresses,
                adminInOrgAdminTreeProofs: params.adminInAdminTreeProofs,
                adminInOrgMembersTreeProofs: params.adminInMembersTreeProofs
            });

        // Validate all admins are members (this prevents bricking at initialization)
        LibOrganizationAdmin.validateAllAdminsAreMembersOrRevert(
            allAdminsInOrgProofs, params.adminsRoot, params.membersRoot, params.adminCount
        );

        // Set roots
        LibOrganizationMembersStorage.layout().membersRoot = params.membersRoot;
        LibOrganizationGroupsStorage.layout().groupsRoot = params.groupsRoot;

        // Set admin configuration
        LibOrganizationAdminStorage.Layout storage adminLayout = LibOrganizationAdminStorage.layout();
        adminLayout.adminConfig = AdminConfig({
            adminsRoot: params.adminsRoot, adminCount: params.adminCount, votingThreshold: params.votingThreshold
        });

        // Set guardian
        LibOrganizationGuardianStorage.layout().guardian = params.guardian;

        emit IOrganizationInitialization.OrganizationInitialized({
            adminsRoot: params.adminsRoot,
            adminCount: params.adminCount,
            votingThreshold: params.votingThreshold,
            adminAddresses: params.adminAddresses,
            guardian: params.guardian,
            membersRoot: params.membersRoot,
            groupsRoot: params.groupsRoot,
            membersIpfsCid: params.membersIpfsCid,
            groupsIpfsCid: params.groupsIpfsCid
        });
    }

    /**
     * @dev Enforces that the caller is the deployer address
     * @dev This function will revert if msg.sender is not the deployer
     */
    function enforceOnlyDeployer() public view {
        if (msg.sender != LibOrganizationDeployerAddressStorage.layout().deployerAddress) {
            revert IOrganizationInitialization.UnauthorizedDeployer();
        }
    }

    /**
     * @dev Gets the deployer address from storage
     * @return The deployer address
     */
    function getDeployerAddress() public view returns (address) {
        return LibOrganizationDeployerAddressStorage.layout().deployerAddress;
    }

    /**
     * @dev Checks if the organization has been initialized
     * @dev Checks if membersRoot is set (since every organization must have at least one member)
     * @return True if initialized, false otherwise
     */
    function isInitialized() public view returns (bool) {
        return LibOrganizationMembersStorage.layout().membersRoot != bytes32(0);
    }
}
