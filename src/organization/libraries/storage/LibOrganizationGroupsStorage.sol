// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Organization Groups Storage
 * @notice Storage layout for organization groups functionality
 * @author Den Technologies Inc
 */
library LibOrganizationGroupsStorage {
    struct Layout {
        mapping(uint8 => mapping(uint8 => bool)) groupIdToMemberIdToInGroup;
        mapping(uint8 => bool) groupIdToExists;
        mapping(uint8 => uint256) groupIdToMemberCount;
        uint8 nextGroupId;
    }

    bytes32 internal constant STORAGE_SLOT = keccak256("onchain.custody.organization.groups.storage");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
