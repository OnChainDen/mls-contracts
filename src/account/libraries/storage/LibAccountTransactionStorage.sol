// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Account Transaction Storage
 * @notice Storage layout for account transaction functionality
 * @author Den Technologies Inc
 */
library LibAccountTransactionStorage {
    enum Operation {
        Call,
        DelegateCall
    }

    struct Layout {
        // Mapping of nonces for replay protection. Each nonce can only be used once.
        mapping(uint256 => bool) usedNonces;
    }

    bytes32 internal constant STORAGE_SLOT = keccak256("onchain.custody.account.transaction.storage");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
