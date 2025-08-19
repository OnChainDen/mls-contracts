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
        ModifyGroup
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
     * @notice Emitted when a group operation is rejected due to invalid parameters
     * @param reason The reason for the rejection
     */
    error GroupOperationRejected(string reason);

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
    {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(newAdminType, newAdminId, newVotingThreshold);

        // Compute deterministic nonce from operation data and salt
        AdminOperationType operationType = AdminOperationType.UpdateAdmin;
        uint256 nonce = computeAdminNonce(operationType, operationData, salt);

        // Validate and consume nonce for replay protection
        if (_usedAdminNonces[nonce]) {
            revert AdminNonceAlreadyUsed(nonce);
        }

        // Mark nonce as used
        _usedAdminNonces[nonce] = true;

        // Validate that the current admin has authorized this change
        bool isAuthorized = _validateAdminAuthorization(operationType, operationData, salt, chainId, signatures);
        if (!isAuthorized) {
            revert AdminOperationRejected("Insufficient authorization to update admin permissions");
        }

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

        // Compute deterministic nonce from operation data and salt
        AdminOperationType operationType = AdminOperationType.CreateGroup;
        uint256 nonce = computeAdminNonce(operationType, operationData, salt);

        // Validate and consume nonce for replay protection
        if (_usedAdminNonces[nonce]) {
            revert AdminNonceAlreadyUsed(nonce);
        }

        // Mark nonce as used
        _usedAdminNonces[nonce] = true;

        // Validate that the current admin has authorized this operation
        bool isAuthorized = _validateAdminAuthorization(operationType, operationData, salt, chainId, signatures);
        if (!isAuthorized) {
            revert AdminOperationRejected("Insufficient authorization to create group");
        }

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

        // Compute deterministic nonce from operation data and salt
        AdminOperationType operationType = AdminOperationType.ModifyGroup;
        uint256 nonce = computeAdminNonce(operationType, operationData, salt);

        // Validate and consume nonce for replay protection
        if (_usedAdminNonces[nonce]) {
            revert AdminNonceAlreadyUsed(nonce);
        }

        // Mark nonce as used
        _usedAdminNonces[nonce] = true;

        // Validate that the current admin has authorized this operation
        bool isAuthorized = _validateAdminAuthorization(operationType, operationData, salt, chainId, signatures);
        if (!isAuthorized) {
            revert AdminOperationRejected("Insufficient authorization to modify group");
        }

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
     * @notice Validates that the provided signatures meet the admin authorization requirements
     * @dev This function verifies that the signatures are from authorized admin members/group
     *      and meet the required voting threshold
     * @param operationType The type of operation being performed
     * @param operationData The ABI-encoded data of the operation
     * @param salt A user-provided salt for nonce computation
     * @param chainId The chain ID for cross-chain replay protection - must match current chain ID
     * @param signatures The signatures to validate
     * @return True if the signatures are valid and meet the threshold, false otherwise
     */
    function _validateAdminAuthorization(
        AdminOperationType operationType,
        bytes memory operationData,
        uint256 salt,
        uint256 chainId,
        bytes memory signatures
    )
        internal
        view
        returns (bool)
    {
        // Validate chain ID for cross-chain replay protection
        if (chainId != block.chainid) {
            revert InvalidAdminChainId(block.chainid, chainId);
        }

        // Get operation hash for signature verification
        bytes32 operationHash = _getAdminOperationHash(operationType, operationData, salt, chainId);

        // Case: Admin is an individual member
        if (adminPermission.adminType == AdminType.Member) {
            return _hasValidAdminMemberSignature(signatures, operationHash);
        }

        // Case: Admin is a group
        if (adminPermission.adminType == AdminType.Group) {
            uint256 validSignatures = _getValidAdminGroupSignatures(signatures, operationHash);
            return validSignatures >= adminPermission.votingThreshold;
        }

        return false;
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
