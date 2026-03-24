// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {ContractType} from "types/CommonTypes.sol";

/**
 * @title Implementation Whitelist Storage
 * @dev ERC-7201 namespaced storage for implementation whitelist functionality
 * @author Den Technologies Inc
 */
library LibImplementationWhitelistStorage {
    /**
     * @dev Storage layout for implementation whitelist
     * @custom:storage-location erc7201:den.mls-wallet.implementation-whitelist.main
     * @param whitelisted Nested mapping of contract type to implementation address to whitelist status
     */
    struct Layout {
        mapping(ContractType => mapping(address => bool)) whitelisted;
    }

    /// @dev Storage location for WhitelistStorage, following ERC-7201 namespaced storage pattern.
    /// @dev Formula: keccak256(abi.encode(uint256(keccak256("den.mls-wallet.implementation-whitelist.main")) - 1)) &
    /// ~bytes32(uint256(0xff)) @dev Verify: `cast index-erc7201 "den.mls-wallet.implementation-whitelist.main"`
    bytes32 internal constant STORAGE_LOCATION = 0xca671afbd25869f26c28645085add0f916fc247d25fcba9293e21543f45bd300;

    /**
     * @dev Returns the storage layout at the namespaced slot
     * @return _layout The storage layout struct
     */
    function layout() internal pure returns (Layout storage _layout) {
        assembly {
            _layout.slot := STORAGE_LOCATION
        }
    }
}
