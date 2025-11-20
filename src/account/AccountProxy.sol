// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { LibAccountOrganizationAddressStorage } from "./libraries/storage/LibAccountOrganizationAddressStorage.sol";

/**
 * @title Account Proxy
 * @notice UUPS proxy contract for Account
 * @author Den Technologies Inc
 */
contract AccountProxy is ERC1967Proxy {
    /**
     * @notice Initialize the proxy
     * @param implementation The implementation contract address
     * @param data The initialization calldata
     * @param organizationAddress The organization address (stored for account operations)
     */
    constructor(
        address implementation,
        bytes memory data,
        address organizationAddress
    )
        ERC1967Proxy(implementation, data)
    {
        // Store organization address in storage
        LibAccountOrganizationAddressStorage.layout().organizationAddress = organizationAddress;
    }
}
