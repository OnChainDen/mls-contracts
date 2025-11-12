// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { OrganizationAdminFacetStorage } from "./facets/OrganizationAdminFacetStorage.sol";
import { OrganizationMembersFacetStorage } from "./facets/OrganizationMembersFacetStorage.sol";
import { OrganizationGroupsFacetStorage } from "./facets/OrganizationGroupsFacetStorage.sol";
import { OrganizationGuardianFacetStorage } from "./facets/OrganizationGuardianFacetStorage.sol";
import { OrganizationPolicyFacetStorage } from "./facets/OrganizationPolicyFacetStorage.sol";
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
        OrganizationAdminFacetStorage.Layout storage adminLayout = OrganizationAdminFacetStorage.layout();
        OrganizationMembersFacetStorage.Layout storage membersLayout = OrganizationMembersFacetStorage.layout();
        OrganizationGroupsFacetStorage.Layout storage groupsLayout = OrganizationGroupsFacetStorage.layout();
        OrganizationGuardianFacetStorage.Layout storage guardianLayout = OrganizationGuardianFacetStorage.layout();
        OrganizationPolicyFacetStorage.Layout storage policyLayout = OrganizationPolicyFacetStorage.layout();

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
        adminLayout.adminPermission = OrganizationAdminFacetStorage.AdminPermission({
            adminType: AdminType.Member,
            adminId: 1,
            votingThreshold: 0
        });

        // Set guardian
        guardianLayout.guardian = guardian;
    }
}
