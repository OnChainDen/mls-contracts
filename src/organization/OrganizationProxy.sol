// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IOrganizationFactory} from "interfaces/IOrganizationFactory.sol";
import {
    LibOrganizationDeployerAddressStorage
} from "organization/libraries/storage/LibOrganizationDeployerAddressStorage.sol";
import {LibOrganizationUpgradeStorage} from "organization/libraries/storage/LibOrganizationUpgradeStorage.sol";

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
        // Case: Implementation contract is a zero address
        if (implementation == address(0)) {
            revert IOrganizationFactory.ZeroAddress();
        }

        // Case: Whitelist contract is a zero address
        if (whitelistAddress == address(0)) {
            revert IOrganizationFactory.ZeroAddress();
        }

        // Case: Whitelist contract is not a deployed contract
        if (whitelistAddress.code.length == 0) {
            revert Address.AddressEmptyCode(whitelistAddress);
        }

        // Store deployer address (the factory) in storage for initialization authorization
        LibOrganizationDeployerAddressStorage.layout().deployerAddress = msg.sender;

        // Store whitelist address in storage for upgrade validation
        LibOrganizationUpgradeStorage.layout().whitelistAddress = whitelistAddress;
    }
}
