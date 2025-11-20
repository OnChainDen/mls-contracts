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
     * @notice Initialize the proxy
     * @param implementation The implementation contract address
     * @param data The initialization calldata
     * @param deployerAddress The deployer address (stored for initialization authorization)
     */
    constructor(
        address implementation,
        bytes memory data,
        address deployerAddress
    )
        ERC1967Proxy(implementation, data)
    {
        // Store deployer address in storage
        LibOrganizationDeployerAddressStorage.layout().deployerAddress = deployerAddress;
    }
}
