// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { LibOrganizationWhitelistStorage } from "./storage/LibOrganizationWhitelistStorage.sol";

/**
 * @title Lib Organization Whitelist
 * @notice Library for whitelist-related operations for Organization contracts
 * @dev This library should ONLY be used by Organization contracts
 * @author Den Technologies Inc
 */
library LibOrganizationWhitelist {
    /**
     * @notice Emitted when the organization's address whitelist is modified
     * @param addedAddresses The addresses that were added to the whitelist
     * @param removedAddresses The addresses that were removed from the whitelist
     */
    event WhitelistModified(address[] addedAddresses, address[] removedAddresses);

    /**
     * @notice Emitted when a whitelist operation is rejected due to invalid parameters
     * @param reason The reason for the rejection
     */
    error WhitelistOperationRejected(string reason);

    /**
     * @notice Checks if an address is whitelisted
     * @param addressToCheck The address to check
     * @return True if the address is whitelisted, false otherwise
     */
    function isAddressWhitelisted(address addressToCheck) internal view returns (bool) {
        return LibOrganizationWhitelistStorage.layout().whitelistedAddresses[addressToCheck];
    }

    /**
     * @notice Modifies the organization's address whitelist by adding and/or removing addresses
     * @dev This is a batch operation that can add multiple addresses and remove multiple addresses in a single call.
     * @param addressesToAdd The array of addresses to add to the whitelist
     * @param addressesToRemove The array of addresses to remove from the whitelist
     */
    function modifyWhitelist(
        address[] memory addressesToAdd,
        address[] memory addressesToRemove
    )
        internal
    {

        LibOrganizationWhitelistStorage.Layout storage whitelistLayout = LibOrganizationWhitelistStorage.layout();

        // Add addresses to whitelist
        for (uint256 i = 0; i < addressesToAdd.length; ++i) {
            address addressToAdd = addressesToAdd[i];
            if (addressToAdd == address(0)) {
                revert WhitelistOperationRejected("Cannot add zero address to whitelist");
            }
            whitelistLayout.whitelistedAddresses[addressToAdd] = true;
        }

        // Remove addresses from whitelist
        for (uint256 i = 0; i < addressesToRemove.length; ++i) {
            whitelistLayout.whitelistedAddresses[addressesToRemove[i]] = false;
        }

        // Emit event
        emit WhitelistModified(addressesToAdd, addressesToRemove);
    }
}
