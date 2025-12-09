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
 * @dev This library should ONLY be used by Organization contracts
 * @author Den Technologies Inc
 */
library LibOrganizationInitialization {
    /**
     * @notice Emitted when organization is successfully initialized
     * @param adminType The admin type set during initialization
     * @param adminAddresses The admin addresses set during initialization
     * @param guardian The guardian address set during initialization
     */
    event OrganizationInitialized(AdminType adminType, address[] adminAddresses, address guardian);

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
     * @notice Enforces that the caller is the deployer address
     * @dev This function will revert if msg.sender is not the deployer
     */
    function enforceOnlyDeployer() internal view {
        if (msg.sender != LibOrganizationDeployerAddressStorage.layout().deployerAddress) {
            revert UnauthorizedDeployer();
        }
    }

    /**
     * @notice Initializes the organization contract with admin configuration
     * @dev Deployer authorization is enforced by the external wrapper function
     * @param adminType Type of admin (Member or Group)
     * @param adminAddresses Array of addresses to be added as admin members
     * @param votingThreshold Voting threshold (only used for Group admin type)
     * @param guardian Guardian address for the organization
     */
    function initialize(
        AdminType adminType,
        address[] memory adminAddresses,
        uint256 votingThreshold,
        address guardian
    )
        internal
    {
        // Check if already initialized
        if (isInitialized()) {
            revert AlreadyInitialized();
        }

        // Validate admin configuration
        if (adminAddresses.length == 0) {
            revert InvalidAdminConfiguration();
        }

        if (adminType == AdminType.Group && votingThreshold == 0) {
            revert InvalidAdminConfiguration();
        }

        if (adminType == AdminType.Member && adminAddresses.length > 1) {
            revert InvalidAdminConfiguration();
        }

        // Set admin configuration - create members and optionally create group
        _setAdminConfiguration(adminType, adminAddresses, votingThreshold);

        // Initialize policy counter
        policyLayout.nextPolicyId = 1;

        // Set guardian
        LibOrganizationGuardianStorage.layout().guardian = guardian;

        emit OrganizationInitialized(adminType, adminAddresses, guardian);
    }

    /**
     * @notice Sets the admin configuration by creating members and optionally a group
     * @param adminType Type of admin (Member or Group)
     * @param adminAddresses Array of addresses to be added as admin members
     * @param votingThreshold Voting threshold for group admins
     * @return adminId The ID of the admin (member ID or group ID)
     */
    function _setAdminConfiguration(
        AdminType adminType,
        address[] memory adminAddresses,
        uint256 votingThreshold
    )
        private
        returns (uint8 adminId)
    {
        LibOrganizationAdminStorage.Layout storage adminLayout = LibOrganizationAdminStorage.layout();
        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();
        LibOrganizationGroupsStorage.Layout storage groupsLayout = LibOrganizationGroupsStorage.layout();
        LibOrganizationPolicyStorage.Layout storage policyLayout = LibOrganizationPolicyStorage.layout();

        // Case: Individual admin
        if (adminType == AdminType.Member) {
            // Validate admin address
            if (adminAddresses[0] == address(0)) {
                revert InvalidAdminConfiguration();
            }

            // Add member to mappings
            membersLayout.memberIdToAddress[1] = adminAddresses[0];
            membersLayout.addressToMemberId[adminAddresses[0]] = 1;

            // Initialize the member, group, and policy counters
            membersLayout.nextMemberId = 2;
            groupsLayout.nextGroupId = 1;

            // Set admin permission
            adminLayout.adminPermission =
                LibOrganizationAdminStorage.AdminPermission({ adminType: adminType, adminId: 1, votingThreshold: 0 });
        }
        // Case: Group admin
        else {
            // Create a group with all members
            groupsLayout.groupIdToExists[1] = true;
            groupsLayout.groupIdToMemberCount[1] = uint256(adminAddresses.length);

            // Initialize the member, group, and policy counters
            membersLayout.nextMemberId = uint8(adminAddresses.length + 1);
            groupsLayout.nextGroupId = 2;

            // Create members for all admin addresses
            for (uint256 i = 0; i < adminAddresses.length; ++i) {
                // Validate admin address
                if (adminAddresses[i] == address(0)) {
                    revert InvalidAdminConfiguration();
                }

                uint8 memberId = uint8(i + 1);

                // Add member to mappings
                membersLayout.memberIdToAddress[memberId] = adminAddresses[i];
                membersLayout.addressToMemberId[adminAddresses[i]] = memberId;
                groupsLayout.groupIdToMemberIdToInGroup[1][memberId] = true;
            }

            // Set admin permission
            adminLayout.adminPermission = LibOrganizationAdminStorage.AdminPermission({
                adminType: adminType,
                adminId: 1,
                votingThreshold: votingThreshold
            });
        }
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
     * @return True if initialized, false otherwise
     */
    function isInitialized() internal view returns (bool) {
        return LibOrganizationAdminStorage.layout().adminPermission.adminId != 0;
    }
}
