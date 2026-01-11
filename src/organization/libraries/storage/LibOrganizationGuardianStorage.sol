// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Organization Guardian Storage
 * @notice Storage layout for organization guardian functionality
 * @author Den Technologies Inc
 */
library LibOrganizationGuardianStorage {
    struct Layout {
        address guardian;
    }

    bytes32 internal constant STORAGE_SLOT = keccak256("onchain.custody.organization.guardian.storage");

    function layout() internal pure returns (Layout storage _layout) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            _layout.slot := slot
        }
    }
}
