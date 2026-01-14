// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibOrganizationDeployerAddressStorage} from "./libraries/storage/LibOrganizationDeployerAddressStorage.sol";
import {LibOrganizationUpgradeStorage} from "./libraries/storage/LibOrganizationUpgradeStorage.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title Organization Proxy
 * @notice UUPS proxy contract for Organization
 * @author Den Technologies Inc
 */
contract OrganizationProxy is ERC1967Proxy {
    /**
     * @notice Constructor for the proxy
     * @param implementation The implementation contract address
     * @param whitelistAddress The address of the implementation whitelist contract
     * @dev The deployer (msg.sender) is stored for initialization authorization.
     *      The factory deploys and initializes atomically in a single transaction.
     */
    constructor(address implementation, address whitelistAddress) ERC1967Proxy(implementation, "") {
        // Store deployer address (the factory) in storage for initialization authorization
        LibOrganizationDeployerAddressStorage.layout().deployerAddress = msg.sender;

        // Store whitelist address in storage for upgrade validation
        LibOrganizationUpgradeStorage.layout().whitelistAddress = whitelistAddress;
    }
}
