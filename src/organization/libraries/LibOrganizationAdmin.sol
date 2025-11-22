// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { LibOrganizationAdminStorage } from "./storage/LibOrganizationAdminStorage.sol";
import { LibOrganizationMembersStorage } from "./storage/LibOrganizationMembersStorage.sol";
import { LibOrganizationGroupsStorage } from "./storage/LibOrganizationGroupsStorage.sol";
import { SignatureUtils } from "../../libraries/SignatureUtils.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { IAdminFacet, AdminType, AdminOperationType } from "../../interfaces/IAdminFacet.sol";
import { LibOrganizationMembers } from "./LibOrganizationMembers.sol";
import { LibOrganizationGroups } from "./LibOrganizationGroups.sol";

/**
 * @title Lib Organization Admin
 * @notice Library for admin-related operations for Organization contracts
 * @dev This library should ONLY be used by Organization contracts
 * @author Den Technologies Inc
 */
library LibOrganizationAdmin {
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
     * @notice Gets the current admin permission configuration
     * @return The current admin permission configuration
     */
    function adminPermission() internal view returns (LibOrganizationAdminStorage.AdminPermission memory) {
        return LibOrganizationAdminStorage.layout().adminPermission;
    }

    /**
     * @notice Checks if an admin nonce has been used
     * @param nonce The nonce to check
     * @return True if the nonce has been used, false otherwise
     */
    function isAdminNonceUsed(uint256 nonce) internal view returns (bool) {
        return LibOrganizationAdminStorage.layout().usedAdminNonces[nonce];
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
     * @notice Updates the admin permissions for the organization
     * @param newAdminType The new admin type (Member or Group)
     * @param newAdminId The new admin ID (member ID or group ID)
     * @param newVotingThreshold The new voting threshold (only used when newAdminType is Group)
     */
    function updateAdmin(
        AdminType newAdminType,
        uint8 newAdminId,
        uint256 newVotingThreshold
    )
        internal
    {

        // Validate the new admin configuration
        if (newAdminType == AdminType.Group && newVotingThreshold == 0) {
            revert AdminOperationRejected("Group admin must have a voting threshold greater than 0");
        }

        // Validate that the newAdminId points to a valid member or group
        if (newAdminType == AdminType.Member) {
            if (!LibOrganizationMembers.memberExists(newAdminId)) {
                revert AdminOperationRejected("Invalid member ID: member does not exist");
            }
        } else if (newAdminType == AdminType.Group) {
            if (!LibOrganizationGroups.isValidGroupWithMembers(newAdminId)) {
                revert AdminOperationRejected("Invalid group ID: group does not exist or has no members");
            }
        }

        LibOrganizationAdminStorage.Layout storage adminLayout = LibOrganizationAdminStorage.layout();

        // Store previous admin configuration for the event
        LibOrganizationAdminStorage.AdminPermission memory previousAdmin = adminLayout.adminPermission;

        // Update admin permissions
        adminLayout.adminPermission = LibOrganizationAdminStorage.AdminPermission({
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
            adminLayout.adminPermission.votingThreshold
        );
    }

    /**
     * @notice Validates that the provided signatures meet the admin authorization requirements
     * @dev This function computes the nonce, verifies that the signatures are from authorized admin members/group
     *      and meet the required voting threshold, checks nonce and chainId for replay protection, and marks the nonce
     *      as used. This function will revert if authorization fails.
     * @param operationType The type of operation being performed
     * @param operationData The ABI-encoded data of the operation
     * @param salt A user-provided salt for nonce computation
     * @param signatures The signatures to validate
     */
    function validateAdminAuthorization(
        AdminOperationType operationType,
        bytes memory operationData,
        uint256 salt,
        bytes memory signatures
    )
        internal
    {
        // Compute deterministic nonce from operation data and salt
        uint256 nonce = computeAdminNonce(operationType, operationData, salt);

        LibOrganizationAdminStorage.Layout storage adminLayout = LibOrganizationAdminStorage.layout();

        // Validate and check nonce for replay protection
        if (adminLayout.usedAdminNonces[nonce]) {
            revert AdminNonceAlreadyUsed(nonce);
        }

        // Get operation hash for signature verification
        bytes32 operationHash = _getAdminOperationHash(operationType, operationData, salt);

        bool isAuthorized = false;

        // Case: Admin is an individual member
        if (adminLayout.adminPermission.adminType == AdminType.Member) {
            isAuthorized = _hasValidAdminMemberSignature(signatures, operationHash);
        }
        // Case: Admin is a group
        else if (adminLayout.adminPermission.adminType == AdminType.Group) {
            uint256 validSignatures = _getValidAdminGroupSignatures(signatures, operationHash);
            isAuthorized = validSignatures >= adminLayout.adminPermission.votingThreshold;
        }

        // Revert if not authorized
        if (!isAuthorized) {
            revert AdminOperationRejected("Insufficient authorization for admin operation");
        }

        // Mark nonce as used after successful validation
        adminLayout.usedAdminNonces[nonce] = true;
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
        private
        view
        returns (bool)
    {
        // Check that we have exactly one signature (65 bytes: r: 32, s: 32, v: 1)
        if (signatures.length != 65) return false;

        LibOrganizationAdminStorage.Layout storage adminLayout = LibOrganizationAdminStorage.layout();
        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();

        // Get the admin member's address
        address adminMemberAddress = membersLayout.memberIdToAddress[adminLayout.adminPermission.adminId];
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
        private
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

        LibOrganizationAdminStorage.Layout storage adminLayout = LibOrganizationAdminStorage.layout();
        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();
        LibOrganizationGroupsStorage.Layout storage groupsLayout = LibOrganizationGroupsStorage.layout();

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
            uint8 memberId = membersLayout.addressToMemberId[signer];
            if (memberId != 0 && groupsLayout.groupIdToMemberIdToInGroup[adminLayout.adminPermission.adminId][memberId])
            {
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
    function _getAdminSigner(bytes memory signature) private pure returns (address) {
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
     * @return The hash of the admin operation formatted for ERC-1271 signature verification
     */
    function _getAdminOperationHash(
        AdminOperationType operationType,
        bytes memory operationData,
        uint256 salt
    )
        private
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
                block.chainid,
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
