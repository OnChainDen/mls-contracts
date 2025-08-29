// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { OrganizationStorage } from "../OrganizationStorage.sol";
import { IOrganizationGuardianFacet } from "../interfaces/IOrganizationGuardianFacet.sol";
import { IGuardianFacet } from "../../interfaces/IGuardianFacet.sol";
import { IAdminFacet } from "../../interfaces/IAdminFacet.sol";

/**
 * @title Organization Guardian Facet
 * @notice Handles guardian-related operations for the OnchainCustodyOrganization diamond
 * @author Den Technologies Inc
 */
contract OrganizationGuardianFacet is IOrganizationGuardianFacet {
    using OrganizationStorage for OrganizationStorage.Layout;

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

    /**
     * @notice Updates the guardian address for the organization
     * @dev This function can only be called by the current admin (individual or group with sufficient signatures)
     * @param newGuardian The new guardian address
     * @param salt A user-provided salt for nonce computation
     * @param chainId The chain ID for cross-chain replay protection - must match current chain ID
     * @param signatures The signatures from the current admin authorizing this operation
     */
    function updateGuardian(address newGuardian, uint256 salt, uint256 chainId, bytes memory signatures) public {
        IGuardianFacet(address(this)).enforceOnlyGuardian();

        // Validate input parameters
        if (newGuardian == address(0)) {
            revert AdminOperationRejected("Guardian address cannot be zero address");
        }

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(newGuardian);

        // Validate that the current admin has authorized this operation
        IAdminFacet(address(this)).validateAdminAuthorization(
            OrganizationStorage.AdminOperationType.UpdateGuardian, operationData, salt, chainId, signatures
        );

        OrganizationStorage.Layout storage l = OrganizationStorage.layout();

        // Store previous guardian for the event
        address previousGuardian = l.guardian;

        // Update guardian address
        l.guardian = newGuardian;

        // Emit event
        emit GuardianUpdated(previousGuardian, newGuardian);
    }
}
