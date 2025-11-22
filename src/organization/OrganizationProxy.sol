// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { LibOrganizationDeployerAddressStorage } from "./libraries/storage/LibOrganizationDeployerAddressStorage.sol";

/**
 * @title Organization Proxy
 * @notice UUPS proxy contract for Organization
 * @author Den Technologies Inc
 */
contract OrganizationProxy is ERC1967Proxy {
    /**
     * @notice Constructor for the proxy
     * @param implementation The implementation contract address
     * @param deployerAddress The deployer address (stored for initialization authorization)
     * @dev The proxy is deployed without initialization. Initialize must be called separately.
     */
    constructor(address implementation, address deployerAddress) ERC1967Proxy(implementation, "") {
        // Store deployer address in storage
        LibOrganizationDeployerAddressStorage.layout().deployerAddress = deployerAddress;
    }
}
