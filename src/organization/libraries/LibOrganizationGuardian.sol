// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
import {LibOrganizationGuardianStorage} from "organization/libraries/storage/LibOrganizationGuardianStorage.sol";

/**
 * @title Lib Organization Guardian
 * @dev Library for guardian-related operations for Organization contracts.
 *      This library should ONLY be used by Organization contracts.
 * @author Den Technologies Inc
 */
library LibOrganizationGuardian {
    /**
     * @dev Sets the guardian address for the organization
     * @param newGuardian The new guardian address
     */
    function setGuardian(address newGuardian) internal {
        // Validate input parameters
        if (newGuardian == address(0)) {
            revert IOrganizationGuardian.InvalidGuardianAddress();
        }

        LibOrganizationGuardianStorage.Layout storage guardianLayout = LibOrganizationGuardianStorage.layout();

        // Store previous guardian for the event
        address previousGuardian = guardianLayout.guardian;

        // Update guardian address
        guardianLayout.guardian = newGuardian;

        // Emit event
        emit IOrganizationGuardian.GuardianUpdated(previousGuardian, newGuardian);
    }

    /**
     * @dev Enforces that the caller is the guardian address.
     *      This function will revert if msg.sender is not the guardian.
     */
    function enforceOnlyGuardian() internal view {
        LibOrganizationGuardianStorage.Layout storage guardianLayout = LibOrganizationGuardianStorage.layout();
        if (msg.sender != guardianLayout.guardian) {
            revert IOrganizationGuardian.UnauthorizedGuardian(msg.sender, guardianLayout.guardian);
        }
    }

    /**
     * @dev Gets the current guardian address
     * @return The current guardian address
     */
    function getGuardian() internal view returns (address) {
        return LibOrganizationGuardianStorage.layout().guardian;
    }
}
