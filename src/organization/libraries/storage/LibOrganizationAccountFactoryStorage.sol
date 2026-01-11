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
        // The current implementation address for all Account beacon proxies
        address accountImplementation;
    }

    bytes32 internal constant STORAGE_SLOT = keccak256("onchain.custody.organization.account.factory.storage");

    function layout() internal pure returns (Layout storage _layout) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            _layout.slot := slot
        }
    }
}
