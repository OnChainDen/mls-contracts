// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibOrganizationAdmin} from "./LibOrganizationAdmin.sol";
import {LibOrganizationGuardianStorage} from "./storage/LibOrganizationGuardianStorage.sol";

/**
 * @title Lib Organization Guardian
 * @notice Library for guardian-related operations for Organization contracts
 * @dev This library should ONLY be used by Organization contracts
 * @author Den Technologies Inc
 */
library LibOrganizationGuardian {
    /**
     * @notice Emitted when the guardian address is updated
     * @param previousGuardian The previous guardian address
     * @param newGuardian The new guardian address
     */
    event GuardianUpdated(address indexed previousGuardian, address indexed newGuardian);

    /**
     * @notice Emitted when a function is called by an unauthorized address (not the guardian)
     * @param caller The address that attempted to call the function
     * @param guardian The current guardian address
     */
    error UnauthorizedCaller(address caller, address guardian);

    /**
     * @notice Sets the guardian address for the organization
     * @param newGuardian The new guardian address
     */
    function setGuardian(address newGuardian) internal {
        // Validate input parameters
        if (newGuardian == address(0)) {
            revert LibOrganizationAdmin.AdminOperationRejected("Guardian address cannot be zero address");
        }

        LibOrganizationGuardianStorage.Layout storage guardianLayout = LibOrganizationGuardianStorage.layout();

        // Store previous guardian for the event
        address previousGuardian = guardianLayout.guardian;

        // Update guardian address
        guardianLayout.guardian = newGuardian;

        // Emit event
        emit GuardianUpdated(previousGuardian, newGuardian);
    }

    /**
     * @notice Enforces that the caller is the guardian address
     * @dev This function will revert if msg.sender is not the guardian
     */
    function enforceOnlyGuardian() internal view {
        LibOrganizationGuardianStorage.Layout storage guardianLayout = LibOrganizationGuardianStorage.layout();
        if (msg.sender != guardianLayout.guardian) {
            revert UnauthorizedCaller(msg.sender, guardianLayout.guardian);
        }
    }

    /**
     * @notice Gets the current guardian address
     * @return The current guardian address
     */
    function getGuardian() internal view returns (address) {
        return LibOrganizationGuardianStorage.layout().guardian;
    }
}
