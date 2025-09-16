// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccountOrganizationAddressStorage } from "./AccountOrganizationAddressStorage.sol";
import { IGuardianFacet } from "../../interfaces/IGuardianFacet.sol";

/**
 * @title Account Guardian Facet
 * @notice Handles guardian-related operations for the OnchainCustodyAccount diamond by forwarding to the organization
 * @author Den Technologies Inc
 */
contract AccountGuardianFacet is IGuardianFacet {
    using AccountOrganizationAddressStorage for AccountOrganizationAddressStorage.Layout;

    /**
     * @notice Error thrown when the organization address is not set
     */
    error OrganizationNotSet();

    /**
     * @notice Error thrown when the call to the organization contract fails
     */
    error OrganizationCallFailed();

    /**
     * @notice Enforces that the caller is the guardian address by forwarding to the organization
     * @dev This function forwards the call to the associated organization contract's enforceOnlyGuardian function
     */
    function enforceOnlyGuardian() external view {
        AccountOrganizationAddressStorage.Layout storage layout = AccountOrganizationAddressStorage.layout();

        // Ensure organization address is set
        if (layout.organizationAddress == address(0)) {
            revert OrganizationNotSet();
        }

        // Forward the call to the organization contract
        try IGuardianFacet(layout.organizationAddress).enforceOnlyGuardian() {
            return;
            // Call succeeded - caller is authorized
        } catch Error(string memory reason) {
            // Re-throw the specific error from the organization
            revert(reason);
        } catch {
            // Generic failure
            revert OrganizationCallFailed();
        }
    }

    /**
     * @notice Gets the organization address that this account is associated with
     * @return The organization address
     */
    function getOrganizationAddress() external view returns (address) {
        return AccountOrganizationAddressStorage.layout().organizationAddress;
    }

    /**
     * @notice Gets the guardian address by forwarding to the organization
     * @return The guardian address from the organization contract
     */
    function guardian() external view returns (address) {
        AccountOrganizationAddressStorage.Layout storage layout = AccountOrganizationAddressStorage.layout();

        // Ensure organization address is set
        if (layout.organizationAddress == address(0)) {
            revert OrganizationNotSet();
        }

        // Forward the call to get guardian from organization contract
        return IGuardianFacet(layout.organizationAddress).guardian();
    }
}
