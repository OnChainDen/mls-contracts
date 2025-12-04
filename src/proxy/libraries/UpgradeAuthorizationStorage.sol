// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IImplementationWhitelist } from "../../interfaces/IImplementationWhitelist.sol";

/**
 * @title Upgrade Authorization Storage
 * @notice ERC-7201 namespaced storage for upgrade authorization state
 * @author Den Technologies Inc
 */
library UpgradeAuthorizationStorage {
    // Storage namespace for upgrade authorization
    bytes32 private constant STORAGE_NAMESPACE = keccak256("onchain.custody.upgrade.authorization");

    struct Layout {
        // Address of the implementation whitelist contract
        address whitelistAddress;
        // Contract type (Account or Organization)
        IImplementationWhitelist.ContractType contractType;
    }

    /**
     * @notice Get the storage layout for upgrade authorization
     * @return layout The storage layout
     * @dev Computes ERC-7201 location: keccak256(abi.encode(uint256(keccak256(namespace)) - 1)) &
     * ~bytes32(uint256(0xff))
     */
    function layout() internal pure returns (Layout storage layout_) {
        bytes32 slot;
        assembly {
            // Compute ERC-7201 location: keccak256(abi.encode(uint256(STORAGE_NAMESPACE) - 1)) &
            // ~bytes32(uint256(0xff))
            let namespaceHash := STORAGE_NAMESPACE
            let adjustedHash := sub(namespaceHash, 1)
            mstore(0x00, adjustedHash)
            let hash := keccak256(0x00, 0x20)
            slot := and(hash, not(0xff))
        }
        assembly {
            layout_.slot := slot
        }
    }
}
