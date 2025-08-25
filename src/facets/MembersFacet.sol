// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { OrganizationStorage } from "../storage/OrganizationStorage.sol";
import { SignatureUtils } from "../libraries/SignatureUtils.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title Members Facet
 * @notice Handles member-related operations for the OnchainCustodyOrganization diamond
 * @author Den Technologies Inc
 */
contract MembersFacet {
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
     * @notice Emitted when a function is called by an unauthorized address (not the guardian)
     * @param caller The address that attempted to call the function
     * @param guardian The current guardian address
     */
    error UnauthorizedCaller(address caller, address guardian);

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
        _validateAdminAuthorization(
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
        onlyGuardian
    {
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

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(memberId, newAddress);

        // Validate that the current admin has authorized this operation
        _validateAdminAuthorization(
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
        _validateAdminAuthorization(
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

            // Remove member from organization mappings
            l.memberIdToAddress[memberId] = address(0);
            l.addressToMemberId[memberAddress] = 0;
        }

        // Emit event
        emit MembersRemoved(memberIds, memberAddresses);
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
        OrganizationStorage.AdminOperationType operationType,
        bytes memory operationData,
        uint256 salt,
        uint256 chainId,
        bytes memory signatures
    )
        internal
    {
        // Compute deterministic nonce from operation data and salt
        uint256 nonce = computeAdminNonce(operationType, operationData, salt);

        OrganizationStorage.Layout storage l = OrganizationStorage.layout();

        // Validate and check nonce for replay protection
        if (l.usedAdminNonces[nonce]) {
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
        if (l.adminPermission.adminType == OrganizationStorage.AdminType.Member) {
            isAuthorized = _hasValidAdminMemberSignature(signatures, operationHash);
        }
        // Case: Admin is a group
        else if (l.adminPermission.adminType == OrganizationStorage.AdminType.Group) {
            uint256 validSignatures = _getValidAdminGroupSignatures(signatures, operationHash);
            isAuthorized = validSignatures >= l.adminPermission.votingThreshold;
        }

        // Revert if not authorized
        if (!isAuthorized) {
            revert AdminOperationRejected("Insufficient authorization for admin operation");
        }

        // Mark nonce as used after successful validation
        l.usedAdminNonces[nonce] = true;
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

        OrganizationStorage.Layout storage l = OrganizationStorage.layout();

        // Get the admin member's address
        address adminMemberAddress = l.memberIdToAddress[l.adminPermission.adminId];
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

        OrganizationStorage.Layout storage l = OrganizationStorage.layout();

        // Iterate over signatures to count valid ones from admin group members
        for (uint8 i = 0; i < signatureCount; ++i) {
            bytes memory signature = SignatureUtils.extractSignature(signatures, i);

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
            uint8 memberId = l.addressToMemberId[signer];
            if (memberId != 0 && l.groupIdToMemberIdToInGroup[l.adminPermission.adminId][memberId]) {
                ++validSignatures;
            }
        }

        return validSignatures;
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
        OrganizationStorage.AdminOperationType operationType,
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
