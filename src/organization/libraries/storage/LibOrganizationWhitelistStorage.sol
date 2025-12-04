// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Organization Whitelist Storage
 * @notice Storage layout for organization whitelist functionality
 * @author Den Technologies Inc
 */
library LibOrganizationWhitelistStorage {
    struct Layout {
        mapping(address => bool) whitelistedAddresses;
    }

    bytes32 internal constant STORAGE_SLOT = keccak256("onchain.custody.organization.whitelist.storage");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
