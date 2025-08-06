// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Policies } from "./libraries/Policies.sol";

/**
 * @title Onchain Custody Organization
 * @notice A contract for managing an Onchain Custody organization
 * @author Den Technologies Inc
 */
contract OnchainCustodyOrganization {
    mapping(uint8 => address) private _memberIdToAddress;

    /**
     * @notice A mapping from member addresses to their IDs
     */
    mapping(address => uint8) public addressToMemberId;

    mapping(uint8 => uint8[]) private _groupIdToMemberIds;
    mapping(uint8 => uint8[]) private _memberIdToGroupIds;
    mapping(uint8 => mapping(uint8 => bool)) private _groupIdToMemberIdToInGroup;

    Policies.Policy[] private _policies;

    mapping(address => bool) private _whitelistedAddresses;

    /**
     * @notice Checks if a member is in a group
     * @param memberId The ID of the member
     * @param groupId The ID of the group
     * @return True if the member is in the group, false otherwise
     */
    function isMemberInGroup(uint8 memberId, uint8 groupId) public view returns (bool) {
        return _groupIdToMemberIdToInGroup[groupId][memberId];
    }

    /**
     * @notice Checks if a member is in a group
     * @param memberAddress The address of the member
     * @param groupId The ID of the group
     * @return True if the member is in the group, false otherwise
     */
    function isMemberInGroup(address memberAddress, uint8 groupId) public view returns (bool) {
        return _groupIdToMemberIdToInGroup[groupId][addressToMemberId[memberAddress]];
    }

    /**
     * @notice Gets the policies for the organization
     * @return The policies for the organization
     */
    function getPolicies() public view returns (Policies.Policy[] memory) {
        return _policies;
    }

    /**
     * @notice Checks if an address is whitelisted
     * @param addressToCheck The address to check
     * @return True if the address is whitelisted, false otherwise
     */
    function isAddressWhitelisted(address addressToCheck) public view returns (bool) {
        return _whitelistedAddresses[addressToCheck];
    }
}
