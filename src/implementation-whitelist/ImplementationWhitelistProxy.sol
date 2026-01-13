// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    LibImplementationWhitelistDeployerAddressStorage
} from "./libraries/LibImplementationWhitelistDeployerAddressStorage.sol";
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
     * @dev The deployer (msg.sender) is stored for initialization authorization.
     *      The factory deploys and initializes atomically in a single transaction.
     */
    constructor(address implementation) ERC1967Proxy(implementation, "") {
        // Store deployer address (the factory) in storage for initialization authorization
        LibImplementationWhitelistDeployerAddressStorage.layout().deployerAddress = msg.sender;
    }
}
