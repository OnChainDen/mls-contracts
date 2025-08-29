// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { OrganizationStorage } from "./OrganizationStorage.sol";

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
    function init(
        address adminAddress,
        address guardian
    )
        external
    {
        OrganizationStorage.Layout storage layout = OrganizationStorage.layout();

        // Validate admin address
        if (adminAddress == address(0)) {
            revert InvalidAdminAddress();
        }

        // Create the first admin member with ID 1
        layout.memberIdToAddress[1] = adminAddress;
        layout.addressToMemberId[adminAddress] = 1;
        
        // Initialize counters
        layout.nextGroupId = 1;
        layout.nextMemberId = 2; // Start with 2 because initial admin is ID 1

        // Initialize admin permission (always Member type with voting threshold 0)
        layout.adminPermission = OrganizationStorage.AdminPermission({
            adminType: OrganizationStorage.AdminType.Member,
            adminId: 1,
            votingThreshold: 0
        });

        // Initialize guardian
        layout.guardian = guardian;
    }
}
