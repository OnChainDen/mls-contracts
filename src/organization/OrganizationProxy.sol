// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { LibOrganizationDeployerAddressStorage } from "./libraries/storage/LibOrganizationDeployerAddressStorage.sol";
import { UpgradeAuthorizationStorage } from "../proxy/libraries/UpgradeAuthorizationStorage.sol";
import { IImplementationWhitelist } from "../implementation-whitelist/interfaces/IImplementationWhitelist.sol";

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
     * @param whitelistAddress The address of the implementation whitelist contract
     * @dev The proxy is deployed without initialization. Initialize must be called separately.
     */
    constructor(
        address implementation,
        address deployerAddress,
        address whitelistAddress
    )
        ERC1967Proxy(implementation, "")
    {
        // Store deployer address in storage
        LibOrganizationDeployerAddressStorage.layout().deployerAddress = deployerAddress;

        // Store whitelist address and contract type in storage
        UpgradeAuthorizationStorage.Layout storage upgradeAuthLayout = UpgradeAuthorizationStorage.layout();
        upgradeAuthLayout.whitelistAddress = whitelistAddress;
        upgradeAuthLayout.contractType = IImplementationWhitelist.ContractType.Organization;
    }
}
