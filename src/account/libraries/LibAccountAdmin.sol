// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { LibAccountOrganizationAddressStorage } from "./storage/LibAccountOrganizationAddressStorage.sol";
import { IAdminFacet, AdminOperationType } from "../../interfaces/IAdminFacet.sol";

/**
 * @title Lib Account Admin
 * @notice Library for admin-related operations for Account contracts by forwarding to the organization
 * @dev This library should ONLY be used by Account contracts
 * @author Den Technologies Inc
 */
library LibAccountAdmin {
    /**
     * @notice Emitted when an admin operation is rejected due to insufficient authorization
     * @param reason The reason for the rejection
     */
    error AdminOperationRejected(string reason);

    /**
     * @notice Error thrown when the organization address is not set
     */
    error OrganizationNotSet();

    /**
     * @notice Error thrown when the call to the organization contract fails
     */
    error OrganizationCallFailed();

    /**
     * @notice Gets the organization address that this account is associated with
     * @return The organization address
     */
    function getOrganizationAddress() internal view returns (address) {
        return LibAccountOrganizationAddressStorage.layout().organizationAddress;
    }

    /**
     * @notice Validates that the provided signatures meet the admin authorization requirements by forwarding to
     * organization
     * @dev This function forwards the call to the associated organization contract's validateAdminAuthorization
     * function
     * @param operationType The type of operation being performed
     * @param operationData The ABI-encoded data of the operation
     * @param salt A user-provided salt for nonce computation
     * @param signatures The signatures to validate
     */
    function validateAdminAuthorization(
        AdminOperationType operationType,
        bytes memory operationData,
        uint256 salt,
        bytes memory signatures
    )
        internal
    {
        LibAccountOrganizationAddressStorage.Layout storage accountOrgLayout =
            LibAccountOrganizationAddressStorage.layout();

        // Ensure organization address is set
        if (accountOrgLayout.organizationAddress == address(0)) {
            revert OrganizationNotSet();
        }

        // Forward the call to the organization contract
        try IAdminFacet(accountOrgLayout.organizationAddress).validateAdminAuthorization(
            operationType, operationData, salt, signatures
        ) {
            return;
            // Call succeeded - authorization is valid
        } catch Error(string memory reason) {
            // Re-throw the specific error from the organization
            revert AdminOperationRejected(reason);
        } catch {
            // Generic failure
            revert OrganizationCallFailed();
        }
    }
}
