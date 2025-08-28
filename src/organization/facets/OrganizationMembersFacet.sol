// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { OrganizationStorage } from "../OrganizationStorage.sol";
import { IAdminFacet } from "../../interfaces/IAdminFacet.sol";
import { IGuardianFacet } from "../../interfaces/IGuardianFacet.sol";

/**
 * @title Organization Members Facet
 * @notice Handles member-related operations for the OnchainCustodyOrganization diamond
 * @author Den Technologies Inc
 */
contract OrganizationMembersFacet {
    using OrganizationStorage for OrganizationStorage.Layout;

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
     * @notice Emitted when an admin operation is rejected due to insufficient authorization
     * @param reason The reason for the rejection
     */
    error AdminOperationRejected(string reason);

    /**
     * @notice Emitted when an admin operation uses a nonce that has already been used
     * @param nonce The nonce that was attempted to be used
     */
    error AdminNonceAlreadyUsed(uint256 nonce);

    /**
     * @notice Emitted when an admin operation has wrong chain ID
     * @param expected The expected chain ID
     * @param provided The provided chain ID
     */
    error InvalidAdminChainId(uint256 expected, uint256 provided);

    /**
     * @notice A mapping from member addresses to their IDs
     * @param memberAddress The address to look up
     * @return The member ID (0 if not a member)
     */
    function addressToMemberId(address memberAddress) external view returns (uint8) {
        return OrganizationStorage.layout().addressToMemberId[memberAddress];
    }

    /**
     * @notice Gets the address of a member by their ID
     * @param memberId The ID of the member
     * @return The address of the member
     */
    function getMemberAddress(uint8 memberId) external view returns (address) {
        return OrganizationStorage.layout().memberIdToAddress[memberId];
    }

    /**
     * @notice Checks if a member exists
     * @param memberId The ID of the member to check
     * @return True if the member exists, false otherwise
     */
    function memberExists(uint8 memberId) external view returns (bool) {
        return OrganizationStorage.layout().memberIdToAddress[memberId] != address(0);
    }

    /**
     * @notice Computes a deterministic nonce for admin operations from operation data and salt
     * @param operationType The type of operation being performed
     * @param operationData The ABI-encoded data of the operation
     * @param salt A user-provided salt for nonce computation
     * @return The computed nonce
     */
    function computeAdminNonce(
        OrganizationStorage.AdminOperationType operationType,
        bytes memory operationData,
        uint256 salt
    )
        public
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
     * @param chainId The chain ID for cross-chain replay protection - must match current chain ID
     * @param signatures The signatures from the current admin authorizing this operation
     * @return memberIds The auto-generated IDs of the added members
     */
    function addMembers(
        address[] memory memberAddresses,
        uint256 salt,
        uint256 chainId,
        bytes memory signatures
    )
        public
        returns (uint8[] memory memberIds)
    {
        IGuardianFacet(address(this)).enforceOnlyGuardian();

        // Validate input parameters
        if (memberAddresses.length == 0) {
            revert MemberOperationRejected("Must specify at least one member address");
        }

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(memberAddresses, memberIds);

        // Validate that the current admin has authorized this operation
        IAdminFacet(address(this)).validateAdminAuthorization(
            OrganizationStorage.AdminOperationType.AddMembers, operationData, salt, chainId, signatures
        );

        OrganizationStorage.Layout storage l = OrganizationStorage.layout();

        // Pre-allocate member IDs array for event and return value
        memberIds = new uint8[](memberAddresses.length);

        // Add members to mappings
        for (uint256 i = 0; i < memberAddresses.length; ++i) {
            // Get current member ID and address
            address memberAddress = memberAddresses[i];
            uint8 memberId = l.nextMemberId;

            // Increment next member ID
            l.nextMemberId++;

            // Pre-allocate member IDs array for event and return value
            memberIds[i] = memberId;

            // Validate member address
            if (memberAddress == address(0)) {
                revert MemberOperationRejected("Invalid member address provided");
            }

            // Check if address is already a member
            if (l.addressToMemberId[memberAddress] != 0) {
                revert MemberOperationRejected("Address is already a member");
            }

            // Update mappings
            l.memberIdToAddress[memberId] = memberAddress;
            l.addressToMemberId[memberAddress] = memberId;
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
     * @param chainId The chain ID for cross-chain replay protection - must match current chain ID
     * @param signatures The signatures from the current admin authorizing this operation
     */
    function modifyMember(
        uint8 memberId,
        address newAddress,
        uint256 salt,
        uint256 chainId,
        bytes memory signatures
    )
        public
    {
        IGuardianFacet(address(this)).enforceOnlyGuardian();

        // Validate input parameters
        if (newAddress == address(0)) {
            revert MemberOperationRejected("Invalid new address provided");
        }

        OrganizationStorage.Layout storage l = OrganizationStorage.layout();

        // Check if member exists
        address previousAddress = l.memberIdToAddress[memberId];
        if (previousAddress == address(0)) {
            revert MemberOperationRejected("Member does not exist");
        }

        // Check if new address is already a member (and it's not the same member)
        uint8 existingMemberId = l.addressToMemberId[newAddress];
        if (existingMemberId != 0 && existingMemberId != memberId) {
            revert MemberOperationRejected("New address is already assigned to another member");
        }

        // Check if new address is already a member (and it's not the same member)
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(memberId, newAddress);

        // Validate that the current admin has authorized this operation
        IAdminFacet(address(this)).validateAdminAuthorization(
            OrganizationStorage.AdminOperationType.ModifyMember, operationData, salt, chainId, signatures
        );

        // Update mappings
        // Remove old address mapping
        l.addressToMemberId[previousAddress] = 0;
        // Add new address mapping
        l.addressToMemberId[newAddress] = memberId;
        // Update member address
        l.memberIdToAddress[memberId] = newAddress;

        // Emit event
        emit MemberModified(memberId, previousAddress, newAddress);
    }

    /**
     * @notice Removes members from the organization
     * @dev This function can only be called by the current admin (individual or group with sufficient signatures)
     *      Members are also automatically removed from all groups they belong to.
     * @param memberIds The array of member IDs to remove
     * @param salt A user-provided salt for nonce computation
     * @param chainId The chain ID for cross-chain replay protection - must match current chain ID
     * @param signatures The signatures from the current admin authorizing this operation
     */
    function removeMembers(uint8[] memory memberIds, uint256 salt, uint256 chainId, bytes memory signatures) public {
        IGuardianFacet(address(this)).enforceOnlyGuardian();

        // Validate input parameters
        if (memberIds.length == 0) {
            revert MemberOperationRejected("Must specify at least one member ID");
        }

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(memberIds);

        // Validate that the current admin has authorized this operation
        IAdminFacet(address(this)).validateAdminAuthorization(
            OrganizationStorage.AdminOperationType.RemoveMembers, operationData, salt, chainId, signatures
        );

        OrganizationStorage.Layout storage l = OrganizationStorage.layout();

        // Preallocate member addresses for event
        address[] memory memberAddresses = new address[](memberIds.length);

        // Remove members from organization and all groups
        for (uint256 i = 0; i < memberIds.length; ++i) {
            // Get member ID and address
            uint8 memberId = memberIds[i];
            address memberAddress = l.memberIdToAddress[memberId];

            // Case: Member does not exist
            if (memberAddress == address(0)) {
                revert MemberOperationRejected("Member does not exist");
            }

            // Preallocate member addresses for event
            memberAddresses[i] = memberAddress;

            // Remove member from all groups they belong to
            for (uint8 groupId = 0; groupId < l.nextGroupId; ++groupId) {
                if (l.groupIdToExists[groupId] && l.groupIdToMemberIdToInGroup[groupId][memberId]) {
                    l.groupIdToMemberIdToInGroup[groupId][memberId] = false;
                    l.groupIdToMemberCount[groupId]--;
                }
            }

            // Remove member from organization mappings
            l.memberIdToAddress[memberId] = address(0);
            l.addressToMemberId[memberAddress] = 0;
        }

        // Emit event
        emit MembersRemoved(memberIds, memberAddresses);
    }
}
