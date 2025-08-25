// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Policies } from "./libraries/Policies.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title Onchain Custody Organization
 * @notice A contract for managing an Onchain Custody organization
 * @author Den Technologies Inc
 */
contract OnchainCustodyOrganization {
    /**
     * @notice Enum to specify whether admin permission is granted to an individual member or a group
     */
    enum AdminType {
        Member,
        Group
    }

    /**
     * @notice Enum to specify the type of admin operation being performed
     */
    enum AdminOperationType {
        UpdateAdmin,
        CreateGroup,
        ModifyGroup,
        RemoveGroup,
        AddMembers,
        ModifyMember,
        RemoveMembers,
        ModifyPolicies,
        UpdateGuardian,
        ModifyWhitelist
    }

    /**
     * @notice Structure to define admin permissions
     */
    struct AdminPermission {
        AdminType adminType;
        uint8 adminId; // Member ID or Group ID
        uint256 votingThreshold; // Number of signatures required (only used when adminType == Group)
    }

    /**
     * @notice The current admin permission configuration
     */
    AdminPermission public adminPermission;

    /**
     * @notice The guardian address that can execute functions on both organization and account contracts
     */
    address public guardian;

    /**
     * @notice Mapping of nonces for replay protection in admin operations. Each nonce can only be used once.
     */
    mapping(uint256 => bool) private _usedAdminNonces;

    /**
     * @notice Emitted when admin permissions are updated
     * @param previousAdminType The previous admin type (Member or Group)
     * @param previousAdminId The previous admin ID
     * @param previousVotingThreshold The previous voting threshold
     * @param newAdminType The new admin type (Member or Group)
     * @param newAdminId The new admin ID
     * @param newVotingThreshold The new voting threshold
     */
    event AdminPermissionUpdated(
        AdminType previousAdminType,
        uint8 previousAdminId,
        uint256 previousVotingThreshold,
        AdminType newAdminType,
        uint8 newAdminId,
        uint256 newVotingThreshold
    );

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
     * @notice Emitted when the organization's policies are modified
     * @param previousPoliciesHash The hash of the previous policies array
     * @param newPoliciesHash The hash of the new policies array
     * @param newPoliciesCount The number of policies in the new policies array
     */
    event PoliciesModified(bytes32 previousPoliciesHash, bytes32 newPoliciesHash, uint256 newPoliciesCount);

    /**
     * @notice Emitted when the organization's address whitelist is modified
     * @param addedAddresses The addresses that were added to the whitelist
     * @param removedAddresses The addresses that were removed from the whitelist
     */
    event WhitelistModified(address[] addedAddresses, address[] removedAddresses);

    /**
     * @notice Emitted when a group operation is rejected due to invalid parameters
     * @param reason The reason for the rejection
     */
    error GroupOperationRejected(string reason);

    /**
     * @notice Emitted when a member operation is rejected due to invalid parameters
     * @param reason The reason for the rejection
     */
    error MemberOperationRejected(string reason);

    /**
     * @notice Emitted when a whitelist operation is rejected due to invalid parameters
     * @param reason The reason for the rejection
     */
    error WhitelistOperationRejected(string reason);

    mapping(uint8 => address) private _memberIdToAddress;

    /**
     * @notice A mapping from member addresses to their IDs
     */
    mapping(address => uint8) public addressToMemberId;

    mapping(uint8 => mapping(uint8 => bool)) private _groupIdToMemberIdToInGroup;
    mapping(uint8 => bool) private _groupIdToExists;

    /**
     * @notice Counter for auto-incrementing group IDs
     */
    uint8 private _nextGroupId = 1;

    /**
     * @notice Counter for auto-incrementing member IDs
     */
    uint8 private _nextMemberId = 1;

    Policies.Policy[] private _policies;

    mapping(address => bool) private _whitelistedAddresses;

    /**
     * @notice Modifier to restrict function access to the guardian address only
     */
    modifier onlyGuardian() {
        if (msg.sender != guardian) {
            revert UnauthorizedCaller(msg.sender, guardian);
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
        // Case: Member does not exist
        if (_memberIdToAddress[memberId] == address(0)) return false;

        return _groupIdToMemberIdToInGroup[groupId][memberId];
    }

    /**
     * @notice Checks if a member is in a group
     * @param memberAddress The address of the member
     * @param groupId The ID of the group
     * @return True if the member is in the group, false otherwise
     */
    function isMemberInGroup(address memberAddress, uint8 groupId) public view returns (bool) {
        uint8 memberId = addressToMemberId[memberAddress];

        // Case: Member does not exist
        if (memberId == 0) return false;

        return _groupIdToMemberIdToInGroup[groupId][memberId];
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

    /**
     * @notice Checks if an admin nonce has been used
     * @param nonce The nonce to check
     * @return True if the nonce has been used, false otherwise
     */
    function isAdminNonceUsed(uint256 nonce) external view returns (bool) {
        return _usedAdminNonces[nonce];
    }

    /**
     * @notice Gets the address of a member by their ID
     * @param memberId The ID of the member
     * @return The address of the member
     */
    function getMemberAddress(uint8 memberId) external view returns (address) {
        return _memberIdToAddress[memberId];
    }

    /**
     * @notice Checks if a group exists
     * @param groupId The ID of the group to check
     * @return True if the group exists, false otherwise
     */
    function groupExists(uint8 groupId) external view returns (bool) {
        return _groupIdToExists[groupId];
    }

    /**
     * @notice Checks if a member exists
     * @param memberId The ID of the member to check
     * @return True if the member exists, false otherwise
     */
    function memberExists(uint8 memberId) external view returns (bool) {
        return _memberIdToAddress[memberId] != address(0);
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
        public
        view
        returns (uint256)
    {
        return uint256(keccak256(abi.encode(address(this), operationType, keccak256(operationData), salt)));
    }

    /**
     * @notice Updates the admin permissions for the organization
     * @dev This function can only be called by the current admin (individual or group with sufficient signatures)
     * @param newAdminType The new admin type (Member or Group)
     * @param newAdminId The new admin ID (member ID or group ID)
     * @param newVotingThreshold The new voting threshold (only used when newAdminType is Group)
     * @param salt A user-provided salt for nonce computation
     * @param chainId The chain ID for cross-chain replay protection - must match current chain ID
     * @param signatures The signatures from the current admin authorizing this change
     */
    function updateAdmin(
        AdminType newAdminType,
        uint8 newAdminId,
        uint256 newVotingThreshold,
        uint256 salt,
        uint256 chainId,
        bytes memory signatures
    )
        public
        onlyGuardian
    {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(newAdminType, newAdminId, newVotingThreshold);

        // Validate that the current admin has authorized this change
        _validateAdminAuthorization(AdminOperationType.UpdateAdmin, operationData, salt, chainId, signatures);

        // Validate the new admin configuration
        if (newAdminType == AdminType.Group && newVotingThreshold == 0) {
            revert AdminOperationRejected("Group admin must have a voting threshold greater than 0");
        }

        // Store previous admin configuration for the event
        AdminPermission memory previousAdmin = adminPermission;

        // Update admin permissions
        adminPermission = AdminPermission({
            adminType: newAdminType,
            adminId: newAdminId,
            votingThreshold: newAdminType == AdminType.Group ? newVotingThreshold : 0
        });

        // Emit event
        emit AdminPermissionUpdated(
            previousAdmin.adminType,
            previousAdmin.adminId,
            previousAdmin.votingThreshold,
            newAdminType,
            newAdminId,
            adminPermission.votingThreshold
        );
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

        // Auto-increment group ID
        groupId = _nextGroupId;
        _nextGroupId++;

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(groupId, memberIds);

        // Validate that the current admin has authorized this operation
        _validateAdminAuthorization(AdminOperationType.CreateGroup, operationData, salt, chainId, signatures);

        // Update member-to-group mappings and group membership flags
        for (uint256 i = 0; i < memberIds.length; ++i) {
            uint8 memberId = memberIds[i];
            if (_memberIdToAddress[memberId] == address(0)) {
                revert GroupOperationRejected("Invalid member ID provided");
            }

            // Mark member as being in the group
            _groupIdToMemberIdToInGroup[groupId][memberId] = true;
        }

        // Mark group as existing
        _groupIdToExists[groupId] = true;

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
        // Check if group exists
        if (!_groupIdToExists[groupId]) {
            revert GroupOperationRejected("Group does not exist");
        }

        // Validate that we're actually making changes
        if (membersToAdd.length == 0 && membersToRemove.length == 0) {
            revert GroupOperationRejected("Must specify members to add or remove");
        }

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(groupId, membersToAdd, membersToRemove);

        // Validate that the current admin has authorized this operation
        _validateAdminAuthorization(AdminOperationType.ModifyGroup, operationData, salt, chainId, signatures);

        // Add new members
        for (uint256 i = 0; i < membersToAdd.length; ++i) {
            uint8 memberId = membersToAdd[i];
            if (_memberIdToAddress[memberId] == address(0)) {
                revert GroupOperationRejected("Invalid member ID provided");
            }

            // Mark member as being in the group
            _groupIdToMemberIdToInGroup[groupId][memberId] = true;
        }

        // Remove members
        for (uint256 i = 0; i < membersToRemove.length; ++i) {
            _groupIdToMemberIdToInGroup[groupId][membersToRemove[i]] = false;
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
        // Check if group exists
        if (!_groupIdToExists[groupId]) {
            revert GroupOperationRejected("Group does not exist");
        }

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(groupId);

        // Validate that the current admin has authorized this operation
        _validateAdminAuthorization(AdminOperationType.RemoveGroup, operationData, salt, chainId, signatures);

        // Mark group as not existing
        _groupIdToExists[groupId] = false;

        // Emit event
        emit GroupRemoved(groupId);
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
        onlyGuardian
        returns (uint8[] memory memberIds)
    {
        // Validate input parameters
        if (memberAddresses.length == 0) {
            revert MemberOperationRejected("Must specify at least one member address");
        }

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(memberAddresses, memberIds);

        // Validate that the current admin has authorized this operation
        _validateAdminAuthorization(AdminOperationType.AddMembers, operationData, salt, chainId, signatures);

        // Pre-allocate member IDs array for event and return value
        memberIds = new uint8[](memberAddresses.length);

        // Add members to mappings
        for (uint256 i = 0; i < memberAddresses.length; ++i) {
            // Get current member ID and address
            address memberAddress = memberAddresses[i];
            uint8 memberId = _nextMemberId;

            // Increment next member ID
            _nextMemberId++;

            // Pre-allocate member IDs array for event and return value
            memberIds[i] = memberId;

            // Validate member address
            if (memberAddress == address(0)) {
                revert MemberOperationRejected("Invalid member address provided");
            }

            // Check if address is already a member
            if (addressToMemberId[memberAddress] != 0) {
                revert MemberOperationRejected("Address is already a member");
            }

            // Update mappings
            _memberIdToAddress[memberId] = memberAddress;
            addressToMemberId[memberAddress] = memberId;
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
        onlyGuardian
    {
        // Validate input parameters
        if (newAddress == address(0)) {
            revert MemberOperationRejected("Invalid new address provided");
        }

        // Check if member exists
        address previousAddress = _memberIdToAddress[memberId];
        if (previousAddress == address(0)) {
            revert MemberOperationRejected("Member does not exist");
        }

        // Check if new address is already a member (and it's not the same member)
        uint8 existingMemberId = addressToMemberId[newAddress];
        if (existingMemberId != 0 && existingMemberId != memberId) {
            revert MemberOperationRejected("New address is already assigned to another member");
        }

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(memberId, newAddress);

        // Validate that the current admin has authorized this operation
        _validateAdminAuthorization(AdminOperationType.ModifyMember, operationData, salt, chainId, signatures);

        // Update mappings
        // Remove old address mapping
        addressToMemberId[previousAddress] = 0;
        // Add new address mapping
        addressToMemberId[newAddress] = memberId;
        // Update member address
        _memberIdToAddress[memberId] = newAddress;

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
    function removeMembers(
        uint8[] memory memberIds,
        uint256 salt,
        uint256 chainId,
        bytes memory signatures
    )
        public
        onlyGuardian
    {
        // Validate input parameters
        if (memberIds.length == 0) {
            revert MemberOperationRejected("Must specify at least one member ID");
        }

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(memberIds);

        // Validate that the current admin has authorized this operation
        _validateAdminAuthorization(AdminOperationType.RemoveMembers, operationData, salt, chainId, signatures);

        // Preallocate member addresses for event
        address[] memory memberAddresses = new address[](memberIds.length);

        // Remove members from organization and all groups
        for (uint256 i = 0; i < memberIds.length; ++i) {
            // Get member ID and address
            uint8 memberId = memberIds[i];
            address memberAddress = _memberIdToAddress[memberId];

            // Case: Member does not exist
            if (memberAddress == address(0)) {
                revert MemberOperationRejected("Member does not exist");
            }

            // Preallocate member addresses for event
            memberAddresses[i] = memberAddress;

            // Remove member from organization mappings
            _memberIdToAddress[memberId] = address(0);
            addressToMemberId[memberAddress] = 0;
        }

        // Emit event
        emit MembersRemoved(memberIds, memberAddresses);
    }

    /**
     * @notice Modifies the organization's policies
     * @dev This function can only be called by the current admin (individual or group with sufficient signatures)
     *      The new policies array completely replaces the existing policies array, maintaining order importance.
     * @param newPolicies The new array of policies to set for the organization
     * @param salt A user-provided salt for nonce computation
     * @param chainId The chain ID for cross-chain replay protection - must match current chain ID
     * @param signatures The signatures from the current admin authorizing this operation
     */
    function modifyPolicies(
        Policies.Policy[] memory newPolicies,
        uint256 salt,
        uint256 chainId,
        bytes memory signatures
    )
        public
        onlyGuardian
    {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(newPolicies);

        // Validate that the current admin has authorized this operation
        _validateAdminAuthorization(AdminOperationType.ModifyPolicies, operationData, salt, chainId, signatures);

        // Store hash of previous policies for the event
        bytes32 previousPoliciesHash = _getPoliciesHash(_policies);

        // Replace the entire policies array with the new one
        delete _policies;
        for (uint256 i = 0; i < newPolicies.length; ++i) {
            _policies.push(newPolicies[i]);
        }

        // Compute hash of new policies for the event
        bytes32 newPoliciesHash = _getPoliciesHash(_policies);

        // Emit event
        emit PoliciesModified(previousPoliciesHash, newPoliciesHash, newPolicies.length);
    }

    /**
     * @notice Updates the guardian address for the organization
     * @dev This function can only be called by the current admin (individual or group with sufficient signatures)
     * @param newGuardian The new guardian address
     * @param salt A user-provided salt for nonce computation
     * @param chainId The chain ID for cross-chain replay protection - must match current chain ID
     * @param signatures The signatures from the current admin authorizing this operation
     */
    function updateGuardian(
        address newGuardian,
        uint256 salt,
        uint256 chainId,
        bytes memory signatures
    )
        public
        onlyGuardian
    {
        // Validate input parameters
        if (newGuardian == address(0)) {
            revert AdminOperationRejected("Guardian address cannot be zero address");
        }

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(newGuardian);

        // Validate that the current admin has authorized this operation
        _validateAdminAuthorization(AdminOperationType.UpdateGuardian, operationData, salt, chainId, signatures);

        // Store previous guardian for the event
        address previousGuardian = guardian;

        // Update guardian address
        guardian = newGuardian;

        // Emit event
        emit GuardianUpdated(previousGuardian, newGuardian);
    }

    /**
     * @notice Modifies the organization's address whitelist by adding and/or removing addresses
     * @dev This function can only be called by the current admin (individual or group with sufficient signatures)
     *      This is a batch operation that can add multiple addresses and remove multiple addresses in a single call.
     * @param addressesToAdd The array of addresses to add to the whitelist
     * @param addressesToRemove The array of addresses to remove from the whitelist
     * @param salt A user-provided salt for nonce computation
     * @param chainId The chain ID for cross-chain replay protection - must match current chain ID
     * @param signatures The signatures from the current admin authorizing this operation
     */
    function modifyWhitelist(
        address[] memory addressesToAdd,
        address[] memory addressesToRemove,
        uint256 salt,
        uint256 chainId,
        bytes memory signatures
    )
        public
        onlyGuardian
    {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(addressesToAdd, addressesToRemove);

        // Validate that the current admin has authorized this operation
        _validateAdminAuthorization(AdminOperationType.ModifyWhitelist, operationData, salt, chainId, signatures);

        // Add addresses to whitelist
        for (uint256 i = 0; i < addressesToAdd.length; ++i) {
            address addressToAdd = addressesToAdd[i];
            if (addressToAdd == address(0)) {
                revert WhitelistOperationRejected("Cannot add zero address to whitelist");
            }
            _whitelistedAddresses[addressToAdd] = true;
        }

        // Remove addresses from whitelist
        for (uint256 i = 0; i < addressesToRemove.length; ++i) {
            _whitelistedAddresses[addressesToRemove[i]] = false;
        }

        // Emit event
        emit WhitelistModified(addressesToAdd, addressesToRemove);
    }

    /**
     * @notice Computes a hash of the policies array for event logging and comparison
     * @param policies The policies array to hash
     * @return The hash of the policies array
     */
    function _getPoliciesHash(Policies.Policy[] memory policies) internal pure returns (bytes32) {
        return keccak256(abi.encode(policies));
    }

    /**
     * @notice Validates that the provided signatures meet the admin authorization requirements
     * @dev This function computes the nonce, verifies that the signatures are from authorized admin members/group
     *      and meet the required voting threshold, checks nonce and chainId for replay protection, and marks the nonce
     *      as used. This function will revert if authorization fails.
     * @param operationType The type of operation being performed
     * @param operationData The ABI-encoded data of the operation
     * @param salt A user-provided salt for nonce computation
     * @param chainId The chain ID for cross-chain replay protection - must match current chain ID
     * @param signatures The signatures to validate
     */
    function _validateAdminAuthorization(
        AdminOperationType operationType,
        bytes memory operationData,
        uint256 salt,
        uint256 chainId,
        bytes memory signatures
    )
        internal
    {
        // Compute deterministic nonce from operation data and salt
        uint256 nonce = computeAdminNonce(operationType, operationData, salt);

        // Validate and check nonce for replay protection
        if (_usedAdminNonces[nonce]) {
            revert AdminNonceAlreadyUsed(nonce);
        }

        // Validate chain ID for cross-chain replay protection
        if (chainId != block.chainid) {
            revert InvalidAdminChainId(block.chainid, chainId);
        }

        // Get operation hash for signature verification
        bytes32 operationHash = _getAdminOperationHash(operationType, operationData, salt, chainId);

        bool isAuthorized = false;

        // Case: Admin is an individual member
        if (adminPermission.adminType == AdminType.Member) {
            isAuthorized = _hasValidAdminMemberSignature(signatures, operationHash);
        }
        // Case: Admin is a group
        else if (adminPermission.adminType == AdminType.Group) {
            uint256 validSignatures = _getValidAdminGroupSignatures(signatures, operationHash);
            isAuthorized = validSignatures >= adminPermission.votingThreshold;
        }

        // Revert if not authorized
        if (!isAuthorized) {
            revert AdminOperationRejected("Insufficient authorization for admin operation");
        }

        // Mark nonce as used after successful validation
        _usedAdminNonces[nonce] = true;
    }

    /**
     * @notice Checks if there is a valid signature from the admin member
     * @param signatures The signatures to verify
     * @param operationHash The hash of the admin operation
     * @return True if there is a valid signature from the admin member, false otherwise
     */
    function _hasValidAdminMemberSignature(
        bytes memory signatures,
        bytes32 operationHash
    )
        internal
        view
        returns (bool)
    {
        // Check that we have exactly one signature (65 bytes: r: 32, s: 32, v: 1)
        if (signatures.length != 65) return false;

        // Get the admin member's address
        address adminMemberAddress = _memberIdToAddress[adminPermission.adminId];
        if (adminMemberAddress == address(0)) return false;

        // Extract signer address from signature using ERC-1271 compatible verification
        address signer = _getAdminSigner(signatures);

        // Check if signer is the admin member
        if (signer != adminMemberAddress) return false;

        // Verify the signature using ERC-1271
        return SignatureChecker.isValidSignatureNow(signer, operationHash, signatures);
    }

    /**
     * @notice Counts valid signatures from members of the admin group
     * @param signatures The signatures to verify
     * @param operationHash The hash of the admin operation
     * @return The number of valid signatures from admin group members
     */
    function _getValidAdminGroupSignatures(
        bytes memory signatures,
        bytes32 operationHash
    )
        internal
        view
        returns (uint256)
    {
        // Case: No signatures provided
        if (signatures.length == 0) return 0;

        // Each signature is 65 bytes (r: 32, s: 32, v: 1)
        uint8 signatureCount = uint8(signatures.length / 65);
        uint256 validSignatures = 0;

        // Track last signer to prevent duplicates (similar to Safe contracts)
        address lastSigner = address(0);

        // Iterate over signatures to count valid ones from admin group members
        for (uint8 i = 0; i < signatureCount; ++i) {
            bytes memory signature = _extractAdminSignature(signatures, i);

            // Extract signer address from signature using ERC-1271 compatible verification
            address signer = _getAdminSigner(signature);

            // Skip if signer is invalid
            if (signer == address(0)) continue;

            // Check for duplicate signers - signers must be unique and in ascending order
            // This prevents both duplicate signatures and replay attacks
            if (signer <= lastSigner) continue;

            // Update last signer for next iteration
            lastSigner = signer;

            // Verify the signature using ERC-1271
            if (!SignatureChecker.isValidSignatureNow(signer, operationHash, signature)) {
                continue;
            }

            // Check if signer is a member of the admin group
            if (isMemberInGroup(signer, adminPermission.adminId)) {
                ++validSignatures;
            }
        }

        return validSignatures;
    }

    /**
     * @notice Extracts a single signature from the signatures array for admin operations
     * @param signatures The signatures to extract from
     * @param index The index of the signature to extract
     * @return The extracted signature
     */
    function _extractAdminSignature(bytes memory signatures, uint256 index) internal pure returns (bytes memory) {
        // TODO: @ittai: Remove this function entirely and use the `_extractSignature` function from the
        // OnchainCustodyAccount
        // contract instead, when you eventually move the functions from that contract over here.
        // Initialize a new bytes array to store the signature
        // Note: The signature is 65 bytes (r: 32, s: 32, v: 1)
        bytes memory extractedSignature = new bytes(65);
        uint256 signatureStartPosition = index * 65;

        /* solhint-disable no-inline-assembly */
        assembly {
            // Initialize pointer to the start of the signatures array
            // Note: First 32 bytes (0x20) are the length of the array
            let signaturesPosition := add(signatures, 0x20)

            // Initialize pointer to the start of the extracted signature
            // Note: First 32 bytes (0x20) are the length of the array
            let extractedSignaturePosition := add(extractedSignature, 0x20)

            // Copy first 32 bytes (r)
            mstore(extractedSignaturePosition, mload(add(signaturesPosition, signatureStartPosition)))
            // Copy second 32 bytes (s)
            mstore(
                add(extractedSignaturePosition, 0x20), mload(add(signaturesPosition, add(signatureStartPosition, 0x20)))
            )
            // Copy last byte (v)
            mstore8(
                add(extractedSignaturePosition, 0x40),
                byte(0, mload(add(signaturesPosition, add(signatureStartPosition, 0x40))))
            )
        }

        return extractedSignature;
    }

    /**
     * @notice Gets the signer address from a signature for admin operations
     * @param signature The signature to extract the signer from
     * @return The signer address, or address(0) if invalid
     */
    function _getAdminSigner(bytes memory signature) internal pure returns (address) {
        // For ERC-1271, we assume the first 20 bytes of the signature contain the signer address
        // This is a common pattern where the signature is prefixed with the signer address
        if (signature.length < 20) {
            return address(0);
        }

        address signer;
        /* solhint-disable no-inline-assembly */
        assembly {
            signer := mload(add(signature, 20))
        }
        return signer;
    }

    /**
     * @notice Creates a hash of the admin operation for signature verification using EIP-712 typed data
     * @param operationType The type of operation being performed
     * @param operationData The ABI-encoded data of the operation
     * @param salt The user-provided salt for nonce computation
     * @param chainId The chain ID for cross-chain replay protection
     * @return The hash of the admin operation formatted for ERC-1271 signature verification
     */
    function _getAdminOperationHash(
        AdminOperationType operationType,
        bytes memory operationData,
        uint256 salt,
        uint256 chainId
    )
        internal
        view
        returns (bytes32)
    {
        // Create EIP-712 structured data hash
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "AdminOperation(uint8 operationType,bytes operationData,uint256 salt,uint256 chainId,address organization)"
                ),
                uint8(operationType),
                keccak256(operationData),
                salt,
                chainId,
                address(this)
            )
        );

        // Return EIP-712 compatible hash for ERC-1271 signature verification
        return MessageHashUtils.toTypedDataHash(
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256("OnchainCustodyOrganization"),
                    keccak256("1"),
                    block.chainid,
                    address(this)
                )
            ),
            structHash
        );
    }
}
