// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { OrganizationStorage } from "../storage/OrganizationStorage.sol";
import { IOrganizationAdminFacet } from "./IOrganizationAdminFacet.sol";

/**
 * @title Groups Facet
 * @notice Handles group-related operations for the OnchainCustodyOrganization diamond
 * @author Den Technologies Inc
 */
contract GroupsFacet {
    using OrganizationStorage for OrganizationStorage.Layout;

    /**
     * @notice Emitted when a group is created
     * @param groupId The ID of the created group
     * @param memberIds The initial member IDs in the group
     */
    event GroupCreated(uint8 indexed groupId, uint8[] memberIds);

    /**
     * @notice Emitted when a group is modified (members added or removed)
     * @param groupId The ID of the modified group
     * @param addedMemberIds The member IDs that were added to the group
     * @param removedMemberIds The member IDs that were removed from the group
     */
    event GroupModified(uint8 indexed groupId, uint8[] addedMemberIds, uint8[] removedMemberIds);

    /**
     * @notice Emitted when a group is removed
     * @param groupId The ID of the removed group
     */
    event GroupRemoved(uint8 indexed groupId);

    /**
     * @notice Emitted when an admin operation is rejected due to insufficient authorization
     * @param reason The reason for the rejection
     */
    error AdminOperationRejected(string reason);

    /**
     * @notice Emitted when an admin operation has insufficient signatures
     * @param required The number of required signatures
     * @param provided The number of provided signatures
     */
    error InsufficientAdminSignatures(uint256 required, uint256 provided);

    /**
     * @notice Emitted when an admin operation has an invalid signature
     */
    error InvalidAdminSignature();

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
     * @notice Emitted when a function is called by an unauthorized address (not the guardian)
     * @param caller The address that attempted to call the function
     * @param guardian The current guardian address
     */
    error UnauthorizedCaller(address caller, address guardian);

    /**
     * @notice Emitted when a group operation is rejected due to invalid parameters
     * @param reason The reason for the rejection
     */
    error GroupOperationRejected(string reason);

    /**
     * @notice Modifier to restrict function access to the guardian address only
     */
    modifier onlyGuardian() {
        OrganizationStorage.Layout storage l = OrganizationStorage.layout();
        if (msg.sender != l.guardian) {
            revert UnauthorizedCaller(msg.sender, l.guardian);
        }
        _;
    }

    /**
     * @notice Checks if a member is in a group
     * @param memberId The ID of the member
     * @param groupId The ID of the group
     * @return True if the member is in the group, false otherwise
     */
    function isMemberInGroup(uint8 memberId, uint8 groupId) public view returns (bool) {
        OrganizationStorage.Layout storage l = OrganizationStorage.layout();

        // Case: Member does not exist
        if (l.memberIdToAddress[memberId] == address(0)) return false;

        return l.groupIdToMemberIdToInGroup[groupId][memberId];
    }

    /**
     * @notice Checks if a member is in a group
     * @param memberAddress The address of the member
     * @param groupId The ID of the group
     * @return True if the member is in the group, false otherwise
     */
    function isMemberInGroup(address memberAddress, uint8 groupId) public view returns (bool) {
        OrganizationStorage.Layout storage l = OrganizationStorage.layout();
        uint8 memberId = l.addressToMemberId[memberAddress];

        // Case: Member does not exist
        if (memberId == 0) return false;

        return l.groupIdToMemberIdToInGroup[groupId][memberId];
    }

    /**
     * @notice Checks if a group exists
     * @param groupId The ID of the group to check
     * @return True if the group exists, false otherwise
     */
    function groupExists(uint8 groupId) external view returns (bool) {
        return OrganizationStorage.layout().groupIdToExists[groupId];
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
     * @notice Creates a new group with the specified member IDs
     * @dev This function can only be called by the current admin (individual or group with sufficient signatures)
     * @param memberIds The array of member IDs to include in the group
     * @param salt A user-provided salt for nonce computation
     * @param chainId The chain ID for cross-chain replay protection - must match current chain ID
     * @param signatures The signatures from the current admin authorizing this operation
     * @return groupId The auto-generated ID of the created group
     */
    function createGroup(
        uint8[] memory memberIds,
        uint256 salt,
        uint256 chainId,
        bytes memory signatures
    )
        public
        onlyGuardian
        returns (uint8 groupId)
    {
        // Validate input parameters
        if (memberIds.length == 0) {
            revert GroupOperationRejected("Group must have at least one member");
        }

        OrganizationStorage.Layout storage l = OrganizationStorage.layout();

        // Auto-increment group ID
        groupId = l.nextGroupId;
        l.nextGroupId++;

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(groupId, memberIds);

        // Validate that the current admin has authorized this operation
        IOrganizationAdminFacet(address(this)).validateAdminAuthorization(
            OrganizationStorage.AdminOperationType.CreateGroup, operationData, salt, chainId, signatures
        );

        // Update member-to-group mappings and group membership flags
        for (uint256 i = 0; i < memberIds.length; ++i) {
            uint8 memberId = memberIds[i];
            if (l.memberIdToAddress[memberId] == address(0)) {
                revert GroupOperationRejected("Invalid member ID provided");
            }

            // Mark member as being in the group
            l.groupIdToMemberIdToInGroup[groupId][memberId] = true;
        }

        // Mark group as existing
        l.groupIdToExists[groupId] = true;

        // Emit event
        emit GroupCreated(groupId, memberIds);
    }

    /**
     * @notice Modifies an existing group by adding or removing members
     * @dev This function can only be called by the current admin (individual or group with sufficient signatures)
     * @param groupId The ID of the group to modify
     * @param membersToAdd Array of member IDs to add to the group
     * @param membersToRemove Array of member IDs to remove from the group
     * @param salt A user-provided salt for nonce computation
     * @param chainId The chain ID for cross-chain replay protection - must match current chain ID
     * @param signatures The signatures from the current admin authorizing this operation
     */
    function modifyGroup(
        uint8 groupId,
        uint8[] memory membersToAdd,
        uint8[] memory membersToRemove,
        uint256 salt,
        uint256 chainId,
        bytes memory signatures
    )
        public
        onlyGuardian
    {
        OrganizationStorage.Layout storage l = OrganizationStorage.layout();

        // Check if group exists
        if (!l.groupIdToExists[groupId]) {
            revert GroupOperationRejected("Group does not exist");
        }

        // Validate that we're actually making changes
        if (membersToAdd.length == 0 && membersToRemove.length == 0) {
            revert GroupOperationRejected("Must specify members to add or remove");
        }

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(groupId, membersToAdd, membersToRemove);

        // Validate that the current admin has authorized this operation
        IOrganizationAdminFacet(address(this)).validateAdminAuthorization(
            OrganizationStorage.AdminOperationType.ModifyGroup, operationData, salt, chainId, signatures
        );

        // Add new members
        for (uint256 i = 0; i < membersToAdd.length; ++i) {
            uint8 memberId = membersToAdd[i];
            if (l.memberIdToAddress[memberId] == address(0)) {
                revert GroupOperationRejected("Invalid member ID provided");
            }

            // Mark member as being in the group
            l.groupIdToMemberIdToInGroup[groupId][memberId] = true;
        }

        // Remove members
        for (uint256 i = 0; i < membersToRemove.length; ++i) {
            l.groupIdToMemberIdToInGroup[groupId][membersToRemove[i]] = false;
        }

        // Emit event
        emit GroupModified(groupId, membersToAdd, membersToRemove);
    }

    /**
     * @notice Removes an existing group by marking it as not existing
     * @dev This function can only be called by the current admin (individual or group with sufficient signatures)
     * @param groupId The ID of the group to remove
     * @param salt A user-provided salt for nonce computation
     * @param chainId The chain ID for cross-chain replay protection - must match current chain ID
     * @param signatures The signatures from the current admin authorizing this operation
     */
    function removeGroup(uint8 groupId, uint256 salt, uint256 chainId, bytes memory signatures) public onlyGuardian {
        OrganizationStorage.Layout storage l = OrganizationStorage.layout();

        // Check if group exists
        if (!l.groupIdToExists[groupId]) {
            revert GroupOperationRejected("Group does not exist");
        }

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(groupId);

        // Validate that the current admin has authorized this operation
        IOrganizationAdminFacet(address(this)).validateAdminAuthorization(
            OrganizationStorage.AdminOperationType.RemoveGroup, operationData, salt, chainId, signatures
        );

        // Mark group as not existing
        l.groupIdToExists[groupId] = false;

        // Emit event
        emit GroupRemoved(groupId);
    }
}
