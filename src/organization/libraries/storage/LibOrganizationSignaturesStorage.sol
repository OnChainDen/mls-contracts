// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Organization Signatures Storage
 * @notice Storage layout for organization signature and nonce functionality
 * @dev Used for all operation types (admin operations and account transactions)
 * @author Den Technologies Inc
 */
library LibOrganizationSignaturesStorage {
    struct Layout {
        mapping(uint256 => bool) usedNonces;
    }

    bytes32 internal constant STORAGE_SLOT = keccak256("onchain.custody.organization.signatures.storage");

    function layout() internal pure returns (Layout storage _layout) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            _layout.slot := slot
        }
    }
}
