// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Policies } from "../libraries/Policies.sol";

/**
 * @title Organization Storage
 * @notice Storage layout for the OnchainCustodyOrganization diamond
 * @author Den Technologies Inc
 */
library OrganizationStorage {
    /**
     * @notice Enum to specify whether admin permission is granted to an individual member or a group
     */
    enum AdminType {
        Member,
        Group
    }

    /**
     * @notice Enum to specify the type of admin operation being performed
     */
    enum AdminOperationType {
        UpdateAdmin,
        CreateGroup,
        ModifyGroup,
        RemoveGroup,
        AddMembers,
        ModifyMember,
        RemoveMembers,
        ModifyPolicies,
        UpdateGuardian,
        ModifyWhitelist,
        DiamondCut // Added for diamond cutting operations

    }

    /**
     * @notice Structure to define admin permissions
     */
    struct AdminPermission {
        AdminType adminType;
        uint8 adminId; // Member ID or Group ID
        uint256 votingThreshold; // Number of signatures required (only used when adminType == Group)
    }

    struct Layout {
        // Admin related storage
        AdminPermission adminPermission;
        address guardian;
        mapping(uint256 => bool) usedAdminNonces;
        // Members related storage
        mapping(uint8 => address) memberIdToAddress;
        mapping(address => uint8) addressToMemberId;
        uint8 nextMemberId;
        // Groups related storage
        mapping(uint8 => mapping(uint8 => bool)) groupIdToMemberIdToInGroup;
        mapping(uint8 => bool) groupIdToExists;
        uint8 nextGroupId;
        // Policies related storage
        Policies.Policy[] policies;
        // Whitelist related storage
        mapping(address => bool) whitelistedAddresses;
    }

    bytes32 internal constant STORAGE_SLOT = keccak256("onchain.custody.organization.storage");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
