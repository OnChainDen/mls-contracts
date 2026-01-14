// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AdminAuthParams} from "../../types/AdminTypes.sol";

/**
 * @title IOrganizationGuardian
 * @notice Interface for guardian-related operations in Organization contracts
 * @dev Maps to LibOrganizationGuardian library functionality
 * @author Den Technologies Inc
 */
interface IOrganizationGuardian {
    // ═══════════════════════════════════════════════════════════════════════════
    // Events
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Emitted when the guardian address is updated
     * @param previousGuardian The previous guardian address
     * @param newGuardian The new guardian address
     */
    event GuardianUpdated(address indexed previousGuardian, address indexed newGuardian);

    // ═══════════════════════════════════════════════════════════════════════════
    // Errors
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Thrown when a function is called by an unauthorized address (not the guardian)
     * @param caller The address that attempted to call the function
     * @param guardian The current guardian address
     */
    error UnauthorizedGuardian(address caller, address guardian);

    // ═══════════════════════════════════════════════════════════════════════════
    // Functions
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Sets a new guardian address for the organization
     * @param newGuardian The address of the new guardian
     * @param authParams The authorization parameters (salt, expiration, signatures, and admin proofs)
     */
    function setGuardian(address newGuardian, AdminAuthParams calldata authParams) external;

    /**
     * @notice Returns the current guardian address
     * @return The address of the guardian
     */
    function guardian() external view returns (address);

    /**
     * @notice Reverts if the caller is not the guardian
     */
    function enforceOnlyGuardian() external view;
}
