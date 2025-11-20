// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { LibOrganizationGuardianStorage } from "./storage/LibOrganizationGuardianStorage.sol";
import { LibOrganizationAdmin } from "./LibOrganizationAdmin.sol";
import { IAdminFacet, AdminOperationType } from "../../interfaces/IAdminFacet.sol";

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
     * @notice Emitted when an admin operation is rejected due to insufficient authorization
     * @param reason The reason for the rejection
     */
    error AdminOperationRejected(string reason);

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
    function guardian() internal view returns (address) {
        return LibOrganizationGuardianStorage.layout().guardian;
    }

    /**
     * @notice Updates the guardian address for the organization
     * @dev This function can only be called by the current admin (individual or group with sufficient signatures)
     * @param newGuardian The new guardian address
     * @param salt A user-provided salt for nonce computation
     * @param signatures The signatures from the current admin authorizing this operation
     */
    function updateGuardian(address newGuardian, uint256 salt, bytes memory signatures) internal {
        enforceOnlyGuardian();

        // Validate input parameters
        if (newGuardian == address(0)) {
            revert AdminOperationRejected("Guardian address cannot be zero address");
        }

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(newGuardian);

        // Validate that the current admin has authorized this operation
        LibOrganizationAdmin.validateAdminAuthorization(
            AdminOperationType.UpdateGuardian, operationData, salt, signatures
        );

        LibOrganizationGuardianStorage.Layout storage guardianLayout = LibOrganizationGuardianStorage.layout();

        // Store previous guardian for the event
        address previousGuardian = guardianLayout.guardian;

        // Update guardian address
        guardianLayout.guardian = newGuardian;

        // Emit event
        emit GuardianUpdated(previousGuardian, newGuardian);
    }
}
