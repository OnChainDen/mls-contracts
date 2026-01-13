// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {InitializationParams} from "../../interfaces/IOrganization.sol";
import {LibOrganizationAdmin} from "./LibOrganizationAdmin.sol";
import {LibOrganizationAdminStorage} from "./storage/LibOrganizationAdminStorage.sol";
import {LibOrganizationDeployerAddressStorage} from "./storage/LibOrganizationDeployerAddressStorage.sol";
import {LibOrganizationGroupsStorage} from "./storage/LibOrganizationGroupsStorage.sol";
import {LibOrganizationGuardianStorage} from "./storage/LibOrganizationGuardianStorage.sol";
import {LibOrganizationMembersStorage} from "./storage/LibOrganizationMembersStorage.sol";

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
     * @dev Emitted when organization is successfully initialized
     * @param adminsRoot The merkle root of admin addresses
     * @param adminCount The number of admins
     * @param votingThreshold The voting threshold for admin operations
     * @param adminAddresses The admin addresses (in ascending order)
     * @param guardian The guardian address set during initialization
     * @param membersRoot The initial members Merkle root
     * @param groupsRoot The initial groups Merkle root
     * @param membersIpfsCid The IPFS CID for members data
     * @param groupsIpfsCid The IPFS CID for groups data
     */
    event OrganizationInitialized(
        bytes32 adminsRoot,
        uint256 adminCount,
        uint256 votingThreshold,
        address[] adminAddresses,
        address guardian,
        bytes32 membersRoot,
        bytes32 groupsRoot,
        string membersIpfsCid,
        string groupsIpfsCid
    );

    /**
     * @dev Error thrown when caller is not the authorized deployer
     */
    error UnauthorizedDeployer();

    /**
     * @dev Error thrown when organization is already initialized
     */
    error AlreadyInitialized();

    /**
     * @dev Error thrown when invalid members root is provided
     */
    error InvalidMembersRoot();

    /**
     * @dev Initializes the organization contract with Merkle-based members/groups and admin configuration
     * @dev Deployer authorization is enforced by the external wrapper function.
     *      Members and groups are represented as Merkle trees - only roots are stored on-chain.
     *      Validates that all admin addresses are members to prevent bricking.
     * @param params The initialization parameters struct
     */
    function initialize(InitializationParams calldata params) internal {
        // Check if already initialized
        if (isInitialized()) {
            revert AlreadyInitialized();
        }

        // Validate members root is provided (organization must have at least one member)
        if (params.membersRoot == bytes32(0)) {
            revert InvalidMembersRoot();
        }

        // Validate admin configuration
        LibOrganizationAdmin.validateAdminConfigurationOrRevert(
            params.adminsRoot, params.adminCount, params.votingThreshold
        );

        // Create proofs struct to verify all admins are in the organization
        // forgefmt: disable-next-item
        LibOrganizationAdmin.AllAdminsInOrgProofs memory allAdminsInOrgProofs =
            LibOrganizationAdmin.AllAdminsInOrgProofs({
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
        adminLayout.adminPermission = LibOrganizationAdminStorage.AdminPermission({
            adminsRoot: params.adminsRoot, adminCount: params.adminCount, votingThreshold: params.votingThreshold
        });

        // Set guardian
        LibOrganizationGuardianStorage.layout().guardian = params.guardian;

        emit OrganizationInitialized({
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
    function enforceOnlyDeployer() internal view {
        if (msg.sender != LibOrganizationDeployerAddressStorage.layout().deployerAddress) {
            revert UnauthorizedDeployer();
        }
    }

    /**
     * @dev Gets the deployer address from storage
     * @return The deployer address
     */
    function getDeployerAddress() internal view returns (address) {
        return LibOrganizationDeployerAddressStorage.layout().deployerAddress;
    }

    /**
     * @dev Checks if the organization has been initialized
     * @dev Checks if membersRoot is set (since every organization must have at least one member)
     * @return True if initialized, false otherwise
     */
    function isInitialized() internal view returns (bool) {
        return LibOrganizationMembersStorage.layout().membersRoot != bytes32(0);
    }
}
