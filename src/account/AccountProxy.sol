// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { LibAccountOrganizationAddressStorage } from "./libraries/storage/LibAccountOrganizationAddressStorage.sol";
import { UpgradeAuthorizationStorage } from "../proxy/libraries/UpgradeAuthorizationStorage.sol";
import { IImplementationWhitelist } from "../interfaces/IImplementationWhitelist.sol";

/**
 * @title Account Proxy
 * @notice UUPS proxy contract for Account
 * @author Den Technologies Inc
 */
contract AccountProxy is ERC1967Proxy {
    /**
     * @notice Constructor for the proxy
     * @param implementation The implementation contract address
     * @param organizationAddress The organization address (stored for account operations)
     * @param whitelistAddress The address of the implementation whitelist contract
     * @dev The proxy is deployed without initialization. All storage is set in the constructor.
     */
    constructor(
        address implementation,
        address organizationAddress,
        address whitelistAddress
    )
        ERC1967Proxy(implementation, "")
    {
        // Store organization address in storage
        LibAccountOrganizationAddressStorage.layout().organizationAddress = organizationAddress;

        // Store whitelist address and contract type in storage
        UpgradeAuthorizationStorage.Layout storage upgradeAuthLayout = UpgradeAuthorizationStorage.layout();
        upgradeAuthLayout.whitelistAddress = whitelistAddress;
        upgradeAuthLayout.contractType = IImplementationWhitelist.ContractType.Account;
    }
}
