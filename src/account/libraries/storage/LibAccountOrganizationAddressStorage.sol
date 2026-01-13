// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

/**
 * @title Account Organization Address Storage
 * @dev Reads the organization address from the EIP-1967 Beacon slot
 * @dev Since the Account is a BeaconProxy and the Organization acts as the Beacon,
 *      the organization address is stored in the standard EIP-1967 Beacon slot.
 * @author Den Technologies Inc
 */
library LibAccountOrganizationAddressStorage {
    /**
     * @dev Gets the organization address (beacon address) from the EIP-1967 Beacon slot
     * @return The address of the organization contract (beacon)
     */
    function getOrganizationAddress() internal view returns (address) {
        return ERC1967Utils.getBeacon();
    }
}
