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
     * @notice Initializes the organization contract with admin and guardian
     * @param adminType The admin type (Member or Group)
     * @param adminId The admin ID (member ID or group ID)
     * @param votingThreshold The voting threshold (only used when adminType is Group)
     * @param guardian The guardian address
     */
    function init(
        OrganizationStorage.AdminType adminType,
        uint8 adminId,
        uint256 votingThreshold,
        address guardian
    )
        external
    {
        OrganizationStorage.Layout storage l = OrganizationStorage.layout();

        // Initialize admin permission
        l.adminPermission = OrganizationStorage.AdminPermission({
            adminType: adminType,
            adminId: adminId,
            votingThreshold: adminType == OrganizationStorage.AdminType.Group ? votingThreshold : 0
        });

        // Initialize guardian
        l.guardian = guardian;

        // Initialize counters
        l.nextMemberId = 1;
        l.nextGroupId = 1;
    }
}
