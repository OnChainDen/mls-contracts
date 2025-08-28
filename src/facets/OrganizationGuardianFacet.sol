// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { OrganizationStorage } from "../storage/OrganizationStorage.sol";
import { IGuardianFacet } from "./IGuardianFacet.sol";

/**
 * @title Organization Guardian Facet
 * @notice Handles guardian-related operations for the OnchainCustodyOrganization diamond
 * @author Den Technologies Inc
 */
contract OrganizationGuardianFacet is IGuardianFacet {
    using OrganizationStorage for OrganizationStorage.Layout;

    /**
     * @notice Emitted when a function is called by an unauthorized address (not the guardian)
     * @param caller The address that attempted to call the function
     * @param guardian The current guardian address
     */
    error UnauthorizedCaller(address caller, address guardian);

    /**
     * @notice Enforces that the caller is the guardian address
     * @dev This function will revert if msg.sender is not the guardian
     */
    function enforceOnlyGuardian() external view {
        OrganizationStorage.Layout storage l = OrganizationStorage.layout();
        if (msg.sender != l.guardian) {
            revert UnauthorizedCaller(msg.sender, l.guardian);
        }
    }

    /**
     * @notice Gets the current guardian address
     * @return The current guardian address
     */
    function guardian() external view returns (address) {
        return OrganizationStorage.layout().guardian;
    }
}
