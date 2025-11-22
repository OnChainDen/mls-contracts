// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { LibOrganizationMembersStorage } from "./storage/LibOrganizationMembersStorage.sol";
import { LibOrganizationGroupsStorage } from "./storage/LibOrganizationGroupsStorage.sol";
import { LibOrganizationGuardian } from "./LibOrganizationGuardian.sol";
import { LibOrganizationAdmin } from "./LibOrganizationAdmin.sol";
import { IAdminFacet, AdminOperationType } from "../../interfaces/IAdminFacet.sol";

/**
 * @title Lib Organization Members
 * @notice Library for member-related operations for Organization contracts
 * @dev This library should ONLY be used by Organization contracts
 * @author Den Technologies Inc
 */
library LibOrganizationMembers {
    /**
     * @notice Emitted when members are added
     * @param memberIds The IDs of the added members
     * @param memberAddresses The addresses of the added members
     */
    event MembersAdded(uint8[] memberIds, address[] memberAddresses);

    /**
     * @notice Emitted when a member's address is modified
     * @param memberId The ID of the modified member
     * @param previousAddress The previous address of the member
     * @param newAddress The new address of the member
     */
    event MemberModified(uint8 indexed memberId, address previousAddress, address newAddress);

    /**
     * @notice Emitted when members are removed
     * @param memberIds The IDs of the removed members
     * @param memberAddresses The addresses of the removed members
     */
    event MembersRemoved(uint8[] memberIds, address[] memberAddresses);

    /**
     * @notice Emitted when a member operation is rejected due to invalid parameters
     * @param reason The reason for the rejection
     */
    error MemberOperationRejected(string reason);

    /**
     * @notice A mapping from member addresses to their IDs
     * @param memberAddress The address to look up
     * @return The member ID (0 if not a member)
     */
    function addressToMemberId(address memberAddress) internal view returns (uint8) {
        return LibOrganizationMembersStorage.layout().addressToMemberId[memberAddress];
    }

    /**
     * @notice Gets the address of a member by their ID
     * @param memberId The ID of the member
     * @return The address of the member
     */
    function getMemberAddress(uint8 memberId) internal view returns (address) {
        return LibOrganizationMembersStorage.layout().memberIdToAddress[memberId];
    }

    /**
     * @notice Checks if a member exists
     * @param memberId The ID of the member to check
     * @return True if the member exists, false otherwise
     */
    function memberExists(uint8 memberId) internal view returns (bool) {
        return LibOrganizationMembersStorage.layout().memberIdToAddress[memberId] != address(0);
    }

    /**
     * @notice Computes a deterministic nonce for admin operations from operation data and salt
     * @param operationType The type of operation being performed
     * @param operationData The ABI-encoded data of the operation
     * @param salt A user-provided salt for nonce computation
     * @return The computed nonce
     */
    function computeAdminNonce(
        AdminOperationType operationType,
        bytes memory operationData,
        uint256 salt
    )
        internal
        view
        returns (uint256)
    {
        return uint256(keccak256(abi.encode(address(this), operationType, keccak256(operationData), salt)));
    }

    /**
     * @notice Adds new members to the organization
     * @dev This function can only be called by the current admin (individual or group with sufficient signatures)
     * @param memberAddresses The array of addresses to add as new members
     * @param salt A user-provided salt for nonce computation
     * @param signatures The signatures from the current admin authorizing this operation
     * @return memberIds The auto-generated IDs of the added members
     */
    function addMembers(
        address[] memory memberAddresses,
        uint256 salt,
        bytes memory signatures
    )
        internal
        returns (uint8[] memory memberIds)
    {
        LibOrganizationGuardian.enforceOnlyGuardian();

        // Validate input parameters
        if (memberAddresses.length == 0) {
            revert MemberOperationRejected("Must specify at least one member address");
        }

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(memberAddresses);

        // Validate that the current admin has authorized this operation
        LibOrganizationAdmin.validateAdminAuthorization(AdminOperationType.AddMembers, operationData, salt, signatures);

        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();

        // Pre-allocate member IDs array for event and return value
        memberIds = new uint8[](memberAddresses.length);

        // Add members to mappings
        for (uint256 i = 0; i < memberAddresses.length; ++i) {
            // Get current member ID and address
            address memberAddress = memberAddresses[i];
            uint8 memberId = membersLayout.nextMemberId;

            // Increment next member ID
            membersLayout.nextMemberId++;

            // Pre-allocate member IDs array for event and return value
            memberIds[i] = memberId;

            // Validate member address
            if (memberAddress == address(0)) {
                revert MemberOperationRejected("Invalid member address provided");
            }

            // Check if address is already a member
            if (membersLayout.addressToMemberId[memberAddress] != 0) {
                revert MemberOperationRejected("Address is already a member");
            }

            // Update mappings
            membersLayout.memberIdToAddress[memberId] = memberAddress;
            membersLayout.addressToMemberId[memberAddress] = memberId;
        }

        // Emit event
        emit MembersAdded(memberIds, memberAddresses);
    }

    /**
     * @notice Modifies a member's address
     * @dev This function can only be called by the current admin (individual or group with sufficient signatures)
     * @param memberId The ID of the member to modify
     * @param newAddress The new address for the member
     * @param salt A user-provided salt for nonce computation
     * @param signatures The signatures from the current admin authorizing this operation
     */
    function modifyMember(uint8 memberId, address newAddress, uint256 salt, bytes memory signatures) internal {
        LibOrganizationGuardian.enforceOnlyGuardian();

        // Validate input parameters
        if (newAddress == address(0)) {
            revert MemberOperationRejected("Invalid new address provided");
        }

        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();

        // Check if member exists
        address previousAddress = membersLayout.memberIdToAddress[memberId];
        if (previousAddress == address(0)) {
            revert MemberOperationRejected("Member does not exist");
        }

        // Check if new address is already a member (and it's not the same member)
        uint8 existingMemberId = membersLayout.addressToMemberId[newAddress];
        if (existingMemberId != 0 && existingMemberId != memberId) {
            revert MemberOperationRejected("New address is already assigned to another member");
        }

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(memberId, newAddress);

        // Validate that the current admin has authorized this operation
        LibOrganizationAdmin.validateAdminAuthorization(
            AdminOperationType.ModifyMember, operationData, salt, signatures
        );

        // Update mappings
        // Remove old address mapping
        membersLayout.addressToMemberId[previousAddress] = 0;
        // Add new address mapping
        membersLayout.addressToMemberId[newAddress] = memberId;
        // Update member address
        membersLayout.memberIdToAddress[memberId] = newAddress;

        // Emit event
        emit MemberModified(memberId, previousAddress, newAddress);
    }

    /**
     * @notice Removes members from the organization
     * @dev This function can only be called by the current admin (individual or group with sufficient signatures)
     *      Members are also automatically removed from all groups they belong to.
     * @param memberIds The array of member IDs to remove
     * @param salt A user-provided salt for nonce computation
     * @param signatures The signatures from the current admin authorizing this operation
     */
    function removeMembers(uint8[] memory memberIds, uint256 salt, bytes memory signatures) internal {
        LibOrganizationGuardian.enforceOnlyGuardian();

        // Validate input parameters
        if (memberIds.length == 0) {
            revert MemberOperationRejected("Must specify at least one member ID");
        }

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(memberIds);

        // Validate that the current admin has authorized this operation
        LibOrganizationAdmin.validateAdminAuthorization(
            AdminOperationType.RemoveMembers, operationData, salt, signatures
        );

        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();
        LibOrganizationGroupsStorage.Layout storage groupsLayout = LibOrganizationGroupsStorage.layout();

        // Preallocate member addresses for event
        address[] memory memberAddresses = new address[](memberIds.length);

        // Remove members from organization and all groups
        for (uint256 i = 0; i < memberIds.length; ++i) {
            // Get member ID and address
            uint8 memberId = memberIds[i];
            address memberAddress = membersLayout.memberIdToAddress[memberId];

            // Case: Member does not exist
            if (memberAddress == address(0)) {
                revert MemberOperationRejected("Member does not exist");
            }

            // Preallocate member addresses for event
            memberAddresses[i] = memberAddress;

            // Remove member from all groups they belong to
            for (uint8 groupId = 0; groupId < groupsLayout.nextGroupId; ++groupId) {
                if (groupsLayout.groupIdToExists[groupId] && groupsLayout.groupIdToMemberIdToInGroup[groupId][memberId])
                {
                    groupsLayout.groupIdToMemberIdToInGroup[groupId][memberId] = false;
                    groupsLayout.groupIdToMemberCount[groupId]--;
                }
            }

            // Remove member from organization mappings
            membersLayout.memberIdToAddress[memberId] = address(0);
            membersLayout.addressToMemberId[memberAddress] = 0;
        }

        // Emit event
        emit MembersRemoved(memberIds, memberAddresses);
    }
}
