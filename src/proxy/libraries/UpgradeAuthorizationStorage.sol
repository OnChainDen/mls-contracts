// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC7201Namespace } from "@openzeppelin/contracts/utils/ERC7201Namespace.sol";
import { IImplementationWhitelist } from "../../interfaces/IImplementationWhitelist.sol";

/**
 * @title Upgrade Authorization Storage
 * @notice ERC-7201 namespaced storage for upgrade authorization state
 * @author Den Technologies Inc
 */
library UpgradeAuthorizationStorage {
    using ERC7201Namespace for bytes32;

    // Storage namespace for upgrade authorization
    bytes32 private constant STORAGE_NAMESPACE = keccak256("onchain.custody.upgrade.authorization");

    struct Layout {
        // Address of the implementation whitelist contract
        address whitelistAddress;
        // Contract type (Account or Organization)
        IImplementationWhitelist.ContractType contractType;
        // Mapping of used upgrade nonces
        mapping(uint256 => bool) usedUpgradeNonces;
    }

    /**
     * @notice Get the storage layout for upgrade authorization
     * @return layout The storage layout
     */
    function layout() internal pure returns (Layout storage layout_) {
        bytes32 slot = STORAGE_NAMESPACE.erc7201Location();
        assembly {
            layout_.slot := slot
        }
    }
}
