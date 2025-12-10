// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IImplementationWhitelist } from "../interfaces/IImplementationWhitelist.sol";

/**
 * @title Implementation Whitelist Storage
 * @notice Storage layout for implementation whitelist functionality
 * @author Den Technologies Inc
 */
library LibImplementationWhitelistStorage {
    struct Layout {
        mapping(IImplementationWhitelist.ContractType => mapping(address => bool)) whitelisted;
    }

    bytes32 internal constant STORAGE_SLOT = keccak256("onchain.custody.implementation.whitelist.storage");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
