// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IOrganizationGroupsFacet
 * @notice Interface for Organization Groups Facet
 * @author Den Technologies Inc
 */
interface IOrganizationGroupsFacet {
    /**
     * @notice Checks if a group ID is valid and has at least one member
     * @param groupId The group ID to validate
     * @return True if the group exists and has members, false otherwise
     */
    function isValidGroupWithMembers(uint256 groupId) external view returns (bool);
}
