// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { LibAccountOrganizationAddressStorage } from "./libraries/storage/LibAccountOrganizationAddressStorage.sol";

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
        LibAccountOrganizationAddressStorage.Layout storage accountOrgLayout =
            LibAccountOrganizationAddressStorage.layout();

        // Initialize organization address
        accountOrgLayout.organizationAddress = organizationAddress;
    }
}
