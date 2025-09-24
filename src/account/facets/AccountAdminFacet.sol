// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccountOrganizationAddressStorage } from "./AccountOrganizationAddressStorage.sol";
import { IAdminFacet, AdminOperationType } from "../../interfaces/IAdminFacet.sol";

/**
 * @title Account Admin Facet
 * @notice Handles admin-related operations for the OnchainCustodyAccount diamond by forwarding to the organization
 * @author Den Technologies Inc
 */
contract AccountAdminFacet is IAdminFacet {
    using AccountOrganizationAddressStorage for AccountOrganizationAddressStorage.Layout;

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
    function getOrganizationAddress() external view returns (address) {
        return AccountOrganizationAddressStorage.layout().organizationAddress;
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
        public
    {
        AccountOrganizationAddressStorage.Layout storage layout = AccountOrganizationAddressStorage.layout();

        // Ensure organization address is set
        if (layout.organizationAddress == address(0)) {
            revert OrganizationNotSet();
        }

        // Forward the call to the organization contract
        try IAdminFacet(layout.organizationAddress).validateAdminAuthorization(
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
