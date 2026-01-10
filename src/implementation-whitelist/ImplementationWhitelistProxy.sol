// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ImplementationWhitelistImplementation} from "./ImplementationWhitelistImplementation.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title Implementation Whitelist Proxy
 * @notice UUPS proxy contract for Implementation Whitelist
 * @author Den Technologies Inc
 */
contract ImplementationWhitelistProxy is ERC1967Proxy {
    /**
     * @notice Constructor for the proxy
     * @param implementation The implementation contract address
     * @param owner The initial owner address for the whitelist contract
     */
    constructor(address implementation, address owner)
        ERC1967Proxy(implementation, abi.encodeCall(ImplementationWhitelistImplementation.initialize, (owner)))
    {}
}
