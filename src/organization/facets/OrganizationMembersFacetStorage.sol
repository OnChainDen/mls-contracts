// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Organization Members Facet Storage
 * @notice Storage layout for the OrganizationMembersFacet
 * @author Den Technologies Inc
 */
library OrganizationMembersFacetStorage {
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
