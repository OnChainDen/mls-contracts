// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Organization Account Factory Storage
 * @notice Storage layout for organization account factory functionality
 * @author Den Technologies Inc
 */
library LibOrganizationAccountFactoryStorage {
    struct Layout {
        mapping(address => bool) deployedAccounts;
    }

    bytes32 internal constant STORAGE_SLOT = keccak256("onchain.custody.organization.account.factory.storage");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
