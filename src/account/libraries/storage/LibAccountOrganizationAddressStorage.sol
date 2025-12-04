// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Account Organization Address Storage
 * @notice Consolidated storage layout for the organization address used by account functionality
 * @author Den Technologies Inc
 */
library LibAccountOrganizationAddressStorage {
    struct Layout {
        // The address of the onchain custody organization contract that this account is associated with
        address organizationAddress;
    }

    bytes32 internal constant STORAGE_SLOT = keccak256("onchain.custody.account.organization.storage");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
