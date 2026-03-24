// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title Implementation Whitelist Proxy
 * @notice UUPS proxy contract for Implementation Whitelist
 * @author Den Technologies Inc
 */
contract ImplementationWhitelistProxy is ERC1967Proxy {
    error EmptyInitializationData();

    /**
     * @notice Constructor for the proxy
     * @param implementation The implementation contract address
     * @param initData Encoded call to initialize(owner, orgImpls, accImpls)
     * @dev ERC1967Proxy will delegatecall initData to the implementation atomically
     */
    constructor(address implementation, bytes memory initData) ERC1967Proxy(implementation, initData) {
        if (initData.length == 0) {
            revert EmptyInitializationData();
        }
    }
}
