// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { LibAccountOrganizationAddressStorage } from "./storage/LibAccountOrganizationAddressStorage.sol";
import { IGuardianFacet } from "../../interfaces/IGuardianFacet.sol";

/**
 * @title Lib Account Guardian
 * @notice Library for guardian-related operations for Account contracts by forwarding to the organization
 * @dev This library should ONLY be used by Account contracts
 * @author Den Technologies Inc
 */
library LibAccountGuardian {
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
    function enforceOnlyGuardian() internal view {
        LibAccountOrganizationAddressStorage.Layout storage accountOrgLayout =
            LibAccountOrganizationAddressStorage.layout();

        // Ensure organization address is set
        if (accountOrgLayout.organizationAddress == address(0)) {
            revert OrganizationNotSet();
        }

        // Forward the call to the organization contract
        try IGuardianFacet(accountOrgLayout.organizationAddress).enforceOnlyGuardian() {
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
    function getOrganizationAddress() internal view returns (address) {
        return LibAccountOrganizationAddressStorage.layout().organizationAddress;
    }

    /**
     * @notice Gets the guardian address by forwarding to the organization
     * @return The guardian address from the organization contract
     */
    function guardian() internal view returns (address) {
        LibAccountOrganizationAddressStorage.Layout storage accountOrgLayout =
            LibAccountOrganizationAddressStorage.layout();

        // Ensure organization address is set
        if (accountOrgLayout.organizationAddress == address(0)) {
            revert OrganizationNotSet();
        }

        // Forward the call to get guardian from organization contract
        return IGuardianFacet(accountOrgLayout.organizationAddress).guardian();
    }
}
