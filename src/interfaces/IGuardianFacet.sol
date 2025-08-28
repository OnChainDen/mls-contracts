// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @notice Interface for calling guardian enforcement functions
 * @dev This interface allows other contracts to interact with guardian facets
 * @author Den Technologies Inc
 */
interface IGuardianFacet {
    /**
     * @notice Enforces that the caller is the guardian address
     * @dev This function will revert if msg.sender is not the guardian
     */
    function enforceOnlyGuardian() external view;

    /**
     * @notice Gets the current guardian address
     * @return The current guardian address
     */
    function guardian() external view returns (address);
}
