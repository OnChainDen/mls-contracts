// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { LibOrganizationAdminStorage } from "./storage/LibOrganizationAdminStorage.sol";
import { LibOrganizationDeployerAddressStorage } from "./storage/LibOrganizationDeployerAddressStorage.sol";
import { LibOrganizationMembersStorage } from "./storage/LibOrganizationMembersStorage.sol";
import { LibOrganizationGroupsStorage } from "./storage/LibOrganizationGroupsStorage.sol";
import { LibOrganizationGuardianStorage } from "./storage/LibOrganizationGuardianStorage.sol";
import { LibOrganizationPolicyStorage } from "./storage/LibOrganizationPolicyStorage.sol";
import { AdminType } from "../../interfaces/IOrganization.sol";

/**
 * @title Lib Organization Initialization
 * @notice Library for post-deployment initialization of Organization contracts
 * @dev This library should ONLY be used by Organization contracts.
 *      Members and Groups are stored as Merkle trees - only the roots are stored on-chain.
 *      Full member/group data is stored off-chain (IPFS) and provided via calldata at validation time.
 * @author Den Technologies Inc
 */
library LibOrganizationInitialization {
    /**
     * @notice Emitted when organization is successfully initialized
     * @param adminType The admin type set during initialization
     * @param adminMember The admin member address (if Member type)
     * @param adminGroupId The admin group ID (if Group type)
     * @param votingThreshold The voting threshold (if Group type)
     * @param guardian The guardian address set during initialization
     * @param membersRoot The initial members Merkle root
     * @param groupsRoot The initial groups Merkle root
     * @param membersIpfsCid The IPFS CID for members data
     * @param groupsIpfsCid The IPFS CID for groups data
     */
    event OrganizationInitialized(
        AdminType adminType,
        address adminMember,
        bytes32 adminGroupId,
        uint256 votingThreshold,
        address guardian,
        bytes32 membersRoot,
        bytes32 groupsRoot,
        string membersIpfsCid,
        string groupsIpfsCid
    );

    /**
     * @notice Error thrown when caller is not the authorized deployer
     */
    error UnauthorizedDeployer();

    /**
     * @notice Error thrown when organization is already initialized
     */
    error AlreadyInitialized();

    /**
     * @notice Error thrown when invalid admin configuration is provided
     */
    error InvalidAdminConfiguration();

    /**
     * @notice Error thrown when invalid members root is provided
     */
    error InvalidMembersRoot();

    /**
     * @notice Enforces that the caller is the deployer address
     * @dev This function will revert if msg.sender is not the deployer
     */
    function enforceOnlyDeployer() internal view {
        if (msg.sender != LibOrganizationDeployerAddressStorage.layout().deployerAddress) {
            revert UnauthorizedDeployer();
        }
    }

    /**
     * @notice Initializes the organization contract with Merkle-based members/groups and admin configuration
     * @dev Deployer authorization is enforced by the external wrapper function.
     *      Members and groups are represented as Merkle trees - only roots are stored on-chain.
     * @param adminType Type of admin (Member or Group)
     * @param adminMember The admin member address (only used when adminType is Member)
     * @param adminGroupId The admin group ID (only used when adminType is Group)
     * @param votingThreshold Voting threshold (only used for Group admin type)
     * @param guardian Guardian address for the organization
     * @param membersRoot The initial Merkle root for all members
     * @param groupsRoot The initial Merkle root for all groups
     * @param membersIpfsCid The IPFS CID where full members data is stored for disaster recovery
     * @param groupsIpfsCid The IPFS CID where full groups data is stored for disaster recovery
     */
    function initialize(
        AdminType adminType,
        address adminMember,
        bytes32 adminGroupId,
        uint256 votingThreshold,
        address guardian,
        bytes32 membersRoot,
        bytes32 groupsRoot,
        string calldata membersIpfsCid,
        string calldata groupsIpfsCid
    )
        internal
    {
        // Check if already initialized
        if (isInitialized()) {
            revert AlreadyInitialized();
        }

        // Validate and set roots
        _validateAndSetRoots(adminType, membersRoot, groupsRoot);

        // Set admin configuration
        _setAdminConfiguration(adminType, adminMember, adminGroupId, votingThreshold);

        // Initialize policy counter
        LibOrganizationPolicyStorage.layout().nextPolicyId = 1;

        // Set guardian
        LibOrganizationGuardianStorage.layout().guardian = guardian;

        _emitInitializedEvent(
            adminType,
            adminMember,
            adminGroupId,
            votingThreshold,
            guardian,
            membersRoot,
            groupsRoot,
            membersIpfsCid,
            groupsIpfsCid
        );
    }

    /**
     * @notice Validates and sets the members and groups roots
     */
    function _validateAndSetRoots(AdminType adminType, bytes32 membersRoot, bytes32 groupsRoot) private {
        // Validate members root is provided (organization must have at least one member)
        if (membersRoot == bytes32(0)) {
            revert InvalidMembersRoot();
        }

        // Groups root must be provided for group admin
        if (adminType == AdminType.Group && groupsRoot == bytes32(0)) {
            revert InvalidAdminConfiguration();
        }

        // Set roots
        LibOrganizationMembersStorage.layout().membersRoot = membersRoot;
        LibOrganizationGroupsStorage.layout().groupsRoot = groupsRoot;
    }

    /**
     * @notice Sets the admin configuration
     */
    function _setAdminConfiguration(
        AdminType adminType,
        address adminMember,
        bytes32 adminGroupId,
        uint256 votingThreshold
    )
        private
    {
        // Validate admin configuration
        if (adminType == AdminType.Member) {
            if (adminMember == address(0)) {
                revert InvalidAdminConfiguration();
            }
        } else if (adminType == AdminType.Group) {
            if (adminGroupId == bytes32(0) || votingThreshold == 0) {
                revert InvalidAdminConfiguration();
            }
        }

        LibOrganizationAdminStorage.Layout storage adminLayout = LibOrganizationAdminStorage.layout();
        adminLayout.adminPermission = LibOrganizationAdminStorage.AdminPermission({
            adminType: adminType,
            adminMember: adminType == AdminType.Member ? adminMember : address(0),
            adminGroupId: adminType == AdminType.Group ? adminGroupId : bytes32(0),
            votingThreshold: adminType == AdminType.Group ? votingThreshold : 0
        });
    }

    /**
     * @notice Emits the OrganizationInitialized event
     */
    function _emitInitializedEvent(
        AdminType adminType,
        address adminMember,
        bytes32 adminGroupId,
        uint256 votingThreshold,
        address guardian,
        bytes32 membersRoot,
        bytes32 groupsRoot,
        string calldata membersIpfsCid,
        string calldata groupsIpfsCid
    )
        private
    {
        emit OrganizationInitialized(
            adminType,
            adminType == AdminType.Member ? adminMember : address(0),
            adminType == AdminType.Group ? adminGroupId : bytes32(0),
            adminType == AdminType.Group ? votingThreshold : 0,
            guardian,
            membersRoot,
            groupsRoot,
            membersIpfsCid,
            groupsIpfsCid
        );
    }

    /**
     * @notice Gets the deployer address from storage
     * @return The deployer address
     */
    function getDeployerAddress() internal view returns (address) {
        return LibOrganizationDeployerAddressStorage.layout().deployerAddress;
    }

    /**
     * @notice Checks if the organization has been initialized
     * @dev Checks if membersRoot is set (since every organization must have at least one member)
     * @return True if initialized, false otherwise
     */
    function isInitialized() internal view returns (bool) {
        return LibOrganizationMembersStorage.layout().membersRoot != bytes32(0);
    }
}
