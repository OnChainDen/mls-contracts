// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IGuardianFacet } from "../../interfaces/IGuardianFacet.sol";

/**
 * @notice Interface for organization guardian facet operations
 * @dev This interface extends the base guardian functionality with organization-specific operations
 * @author Den Technologies Inc
 */
interface IOrganizationGuardianFacet is IGuardianFacet {
    /**
     * @notice Updates the guardian address for the organization
     * @dev This function can only be called by the current admin (individual or group with sufficient signatures)
     * @param newGuardian The new guardian address
     * @param salt A user-provided salt for nonce computation
     * @param chainId The chain ID for cross-chain replay protection - must match current chain ID
     * @param signatures The signatures from the current admin authorizing this operation
     */
    function updateGuardian(address newGuardian, uint256 salt, uint256 chainId, bytes memory signatures) external;
}
