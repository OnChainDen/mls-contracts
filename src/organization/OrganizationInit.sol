// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { LibOrganizationAdminStorage } from "./libraries/storage/LibOrganizationAdminStorage.sol";
import { LibOrganizationMembersStorage } from "./libraries/storage/LibOrganizationMembersStorage.sol";
import { LibOrganizationGroupsStorage } from "./libraries/storage/LibOrganizationGroupsStorage.sol";
import { LibOrganizationGuardianStorage } from "./libraries/storage/LibOrganizationGuardianStorage.sol";
import { LibOrganizationPolicyStorage } from "./libraries/storage/LibOrganizationPolicyStorage.sol";
import { AdminType } from "../interfaces/IAdminFacet.sol";

/**
 * @title Organization Initialization
 * @notice Initialization contract for OnchainCustodyOrganization diamond
 * @author Den Technologies Inc
 */
contract OrganizationInit {
    /**
     * @notice Emitted when an invalid admin address is provided
     */
    error InvalidAdminAddress();

    /**
     * @notice Initializes the organization contract with admin and guardian
     * @dev Creates the first admin member with ID 1 and sets up admin permissions
     * @param adminAddress The address of the admin member
     * @param guardian The guardian address
     */
    function init(address adminAddress, address guardian) external {
        LibOrganizationAdminStorage.Layout storage adminLayout = LibOrganizationAdminStorage.layout();
        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();
        LibOrganizationGroupsStorage.Layout storage groupsLayout = LibOrganizationGroupsStorage.layout();
        LibOrganizationGuardianStorage.Layout storage guardianLayout = LibOrganizationGuardianStorage.layout();
        LibOrganizationPolicyStorage.Layout storage policyLayout = LibOrganizationPolicyStorage.layout();

        // Validate admin address
        if (adminAddress == address(0)) {
            revert InvalidAdminAddress();
        }

        // Set up the first member (admin)
        membersLayout.memberIdToAddress[1] = adminAddress;
        membersLayout.addressToMemberId[adminAddress] = 1;

        // Initialize counters
        membersLayout.nextMemberId = 2;
        groupsLayout.nextGroupId = 1;
        policyLayout.nextPolicyId = 1;

        // Set admin permission
        adminLayout.adminPermission =
            LibOrganizationAdminStorage.AdminPermission({ adminType: AdminType.Member, adminId: 1, votingThreshold: 0 });

        // Set guardian
        guardianLayout.guardian = guardian;
    }
}
