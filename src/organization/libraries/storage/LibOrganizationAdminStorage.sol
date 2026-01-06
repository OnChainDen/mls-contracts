// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AdminType } from "../../../interfaces/IOrganization.sol";

/**
 * @title Organization Admin Storage
 * @notice Storage layout for organization admin functionality
 * @dev Admin can be a single member (identified by address) or a group (identified by groupId)
 * @author Den Technologies Inc
 */
library LibOrganizationAdminStorage {
    /**
     * @notice Structure to define admin permissions
     * @dev Uses address for Member admin and bytes32 groupId for Group admin
     */
    struct AdminPermission {
        AdminType adminType;
        address adminMember; // Used when adminType == Member
        bytes32 adminGroupId; // Used when adminType == Group
        uint256 votingThreshold; // Number of signatures required (only used when adminType == Group)
    }

    struct Layout {
        AdminPermission adminPermission;
    }

    bytes32 internal constant STORAGE_SLOT = keccak256("onchain.custody.organization.admin.storage");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
