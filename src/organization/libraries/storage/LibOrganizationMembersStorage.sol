// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Organization Members Storage
 * @notice Storage layout for organization members functionality
 * @author Den Technologies Inc
 */
library LibOrganizationMembersStorage {
    struct Layout {
        mapping(uint8 => address) memberIdToAddress;
        mapping(address => uint8) addressToMemberId;
        uint8 nextMemberId;
    }

    bytes32 internal constant STORAGE_SLOT = keccak256("onchain.custody.organization.members.storage");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
