// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Account Storage
 * @notice Storage layout for the OnchainCustodyAccount diamond
 * @author Den Technologies Inc
 */
library AccountStorage {
    enum Operation {
        Call,
        DelegateCall
    }

    struct Layout {
        // The address of the onchain custody organization contract that this account is associated with
        address organizationAddress;
        // Mapping of nonces for replay protection. Each nonce can only be used once.
        mapping(uint256 => bool) usedNonces;
    }

    bytes32 internal constant STORAGE_SLOT = keccak256("onchain.custody.account.storage");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
