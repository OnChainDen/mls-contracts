// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IOrganizationMembersFacet
 * @notice Interface for Organization Members Facet
 * @author Den Technologies Inc
 */
interface IOrganizationMembersFacet {
    /**
     * @notice Checks if a member exists
     * @param memberId The ID of the member to check
     * @return True if the member exists, false otherwise
     */
    function memberExists(uint8 memberId) external view returns (bool);

    /**
     * @notice A mapping from member addresses to their IDs
     * @param memberAddress The address to look up
     * @return The member ID (0 if not a member)
     */
    function addressToMemberId(address memberAddress) external view returns (uint8);
}
