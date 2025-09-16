// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccountOrganizationAddressStorage } from "./facets/AccountOrganizationAddressStorage.sol";

/**
 * @title Account Initialization
 * @notice Initialization contract for OnchainCustodyAccount diamond
 * @author Den Technologies Inc
 */
contract AccountInit {
    /**
     * @notice Initializes the account contract with the organization address
     * @param organizationAddress The address of the onchain custody organization contract
     */
    function init(address organizationAddress) external {
        AccountOrganizationAddressStorage.Layout storage layout = AccountOrganizationAddressStorage.layout();

        // Initialize organization address
        layout.organizationAddress = organizationAddress;
    }
}
