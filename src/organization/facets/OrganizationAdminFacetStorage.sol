// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AdminType } from "../../interfaces/IAdminFacet.sol";

/**
 * @title Organization Admin Facet Storage
 * @notice Storage layout for the OrganizationAdminFacet
 * @author Den Technologies Inc
 */
library OrganizationAdminFacetStorage {
    /**
     * @notice Structure to define admin permissions
     */
    struct AdminPermission {
        AdminType adminType;
        uint8 adminId; // Member ID or Group ID
        uint256 votingThreshold; // Number of signatures required (only used when adminType == Group)
    }

    struct Layout {
        AdminPermission adminPermission;
        mapping(uint256 => bool) usedAdminNonces;
    }

    bytes32 internal constant STORAGE_SLOT = keccak256("onchain.custody.organization.admin.storage");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
