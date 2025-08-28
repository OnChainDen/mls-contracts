// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { OrganizationStorage } from "../OrganizationStorage.sol";
import { IAdminFacet } from "../../interfaces/IAdminFacet.sol";
import { IGuardianFacet } from "../../interfaces/IGuardianFacet.sol";

/**
 * @title Organization Whitelist Facet
 * @notice Handles whitelist-related operations for the OnchainCustodyOrganization diamond
 * @author Den Technologies Inc
 */
contract OrganizationWhitelistFacet {
    using OrganizationStorage for OrganizationStorage.Layout;

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
     * @notice Emitted when an admin operation is rejected due to insufficient authorization
     * @param reason The reason for the rejection
     */
    error AdminOperationRejected(string reason);

    /**
     * @notice Emitted when an admin operation uses a nonce that has already been used
     * @param nonce The nonce that was attempted to be used
     */
    error AdminNonceAlreadyUsed(uint256 nonce);

    /**
     * @notice Emitted when an admin operation has wrong chain ID
     * @param expected The expected chain ID
     * @param provided The provided chain ID
     */
    error InvalidAdminChainId(uint256 expected, uint256 provided);

    /**
     * @notice Checks if an address is whitelisted
     * @param addressToCheck The address to check
     * @return True if the address is whitelisted, false otherwise
     */
    function isAddressWhitelisted(address addressToCheck) public view returns (bool) {
        return OrganizationStorage.layout().whitelistedAddresses[addressToCheck];
    }

    /**
     * @notice Modifies the organization's address whitelist by adding and/or removing addresses
     * @dev This function can only be called by the current admin (individual or group with sufficient signatures)
     *      This is a batch operation that can add multiple addresses and remove multiple addresses in a single call.
     * @param addressesToAdd The array of addresses to add to the whitelist
     * @param addressesToRemove The array of addresses to remove from the whitelist
     * @param salt A user-provided salt for nonce computation
     * @param chainId The chain ID for cross-chain replay protection - must match current chain ID
     * @param signatures The signatures from the current admin authorizing this operation
     */
    function modifyWhitelist(
        address[] memory addressesToAdd,
        address[] memory addressesToRemove,
        uint256 salt,
        uint256 chainId,
        bytes memory signatures
    )
        public
    {
        IGuardianFacet(address(this)).enforceOnlyGuardian();

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(addressesToAdd, addressesToRemove);

        // Validate that the current admin has authorized this operation
        IAdminFacet(address(this)).validateAdminAuthorization(
            OrganizationStorage.AdminOperationType.ModifyWhitelist, operationData, salt, chainId, signatures
        );

        OrganizationStorage.Layout storage l = OrganizationStorage.layout();

        // Add addresses to whitelist
        for (uint256 i = 0; i < addressesToAdd.length; ++i) {
            address addressToAdd = addressesToAdd[i];
            if (addressToAdd == address(0)) {
                revert WhitelistOperationRejected("Cannot add zero address to whitelist");
            }
            l.whitelistedAddresses[addressToAdd] = true;
        }

        // Remove addresses from whitelist
        for (uint256 i = 0; i < addressesToRemove.length; ++i) {
            l.whitelistedAddresses[addressesToRemove[i]] = false;
        }

        // Emit event
        emit WhitelistModified(addressesToAdd, addressesToRemove);
    }
}
