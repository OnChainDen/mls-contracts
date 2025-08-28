// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { OrganizationStorage } from "../storage/OrganizationStorage.sol";

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

        // Initialize counters
        layout.nextMemberId = 1;
        layout.nextGroupId = 1;

        // Create the first admin member with ID 1
        uint8 adminId = 1;
        layout.memberIdToAddress[adminId] = adminAddress;
        layout.addressToMemberId[adminAddress] = adminId;
        
        // Increment the next member ID
        layout.nextMemberId++;

        // Initialize admin permission (always Member type with voting threshold 0)
        layout.adminPermission = OrganizationStorage.AdminPermission({
            adminType: OrganizationStorage.AdminType.Member,
            adminId: adminId,
            votingThreshold: 0
        });

        // Initialize guardian
        layout.guardian = guardian;
    }
}
