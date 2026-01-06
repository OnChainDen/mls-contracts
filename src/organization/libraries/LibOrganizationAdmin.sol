// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { LibOrganizationAdminStorage } from "./storage/LibOrganizationAdminStorage.sol";
import { LibOrganizationSignatures } from "./LibOrganizationSignatures.sol";
import { LibOrganizationMembers } from "./LibOrganizationMembers.sol";
import { LibOrganizationGroups } from "./LibOrganizationGroups.sol";
import { SignatureUtils } from "../../libraries/SignatureUtils.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { AdminType, OperationType } from "../../interfaces/IOrganization.sol";
import { Policies } from "../../libraries/Policies.sol";

/**
 * @title Lib Organization Admin
 * @notice Library for admin-related operations for Organization contracts
 * @dev This library should ONLY be used by Organization contracts.
 *      Admin membership is verified via Merkle proofs.
 * @author Den Technologies Inc
 */
library LibOrganizationAdmin {
    /**
     * @notice Proofs needed to verify admin authorization
     * @dev Contains per-signer proofs for organization membership and optional group membership
     * @param memberProofs Per-signer merkle proofs that each signer is in the organization's membersRoot
     * @param group Admin group data if admin is a group (ignored for Member admin type)
     * @param groupExistenceProof Merkle proof that the admin group exists in groupsRoot
     * @param memberInGroupProofs Per-signer merkle proofs that each signer is in the admin group's tree
     */
    struct AdminProofs {
        bytes32[][] memberProofs;
        Policies.GroupData group;
        bytes32[] groupExistenceProof;
        bytes32[][] memberInGroupProofs;
    }

    /**
     * @notice Emitted when admin permissions are updated
     * @param previousAdminType The previous admin type (Member or Group)
     * @param previousAdminMember The previous admin member address (if Member type)
     * @param previousAdminGroupId The previous admin group ID (if Group type)
     * @param previousVotingThreshold The previous voting threshold
     * @param newAdminType The new admin type (Member or Group)
     * @param newAdminMember The new admin member address (if Member type)
     * @param newAdminGroupId The new admin group ID (if Group type)
     * @param newVotingThreshold The new voting threshold
     */
    event AdminPermissionUpdated(
        AdminType previousAdminType,
        address previousAdminMember,
        bytes32 previousAdminGroupId,
        uint256 previousVotingThreshold,
        AdminType newAdminType,
        address newAdminMember,
        bytes32 newAdminGroupId,
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
     * @notice Emitted when an admin operation has wrong chain ID
     * @param expected The expected chain ID
     * @param provided The provided chain ID
     */
    error InvalidAdminChainId(uint256 expected, uint256 provided);

    /**
     * @notice Emitted when an admin operation has expired
     * @param expirationTimestamp The expiration timestamp that was exceeded
     * @param currentTimestamp The current block timestamp
     */
    error AdminOperationExpired(uint256 expirationTimestamp, uint256 currentTimestamp);

    /**
     * @notice Gets the current admin permission configuration
     * @return The current admin permission configuration
     */
    function adminPermission() internal view returns (LibOrganizationAdminStorage.AdminPermission memory) {
        return LibOrganizationAdminStorage.layout().adminPermission;
    }

    /**
     * @notice Updates the admin permissions for the organization
     * @dev For Member admin, provide the member address. For Group admin, provide the group ID.
     * @param newAdminType The new admin type (Member or Group)
     * @param newAdminMember The new admin member address (only used when newAdminType is Member)
     * @param newAdminGroupId The new admin group ID (only used when newAdminType is Group)
     * @param newVotingThreshold The new voting threshold (only used when newAdminType is Group)
     */
    function updateAdmin(
        AdminType newAdminType,
        address newAdminMember,
        bytes32 newAdminGroupId,
        uint256 newVotingThreshold
    )
        internal
    {
        // Validate the new admin configuration
        if (newAdminType == AdminType.Group && newVotingThreshold == 0) {
            revert AdminOperationRejected("Group admin must have a voting threshold greater than 0");
        }

        // Validate that the newAdminMember is a non-zero address for Member type
        if (newAdminType == AdminType.Member && newAdminMember == address(0)) {
            revert AdminOperationRejected("Invalid admin member: address cannot be zero");
        }

        // Validate that newAdminGroupId is non-zero for Group type
        if (newAdminType == AdminType.Group && newAdminGroupId == bytes32(0)) {
            revert AdminOperationRejected("Invalid admin group: group ID cannot be zero");
        }

        LibOrganizationAdminStorage.Layout storage adminLayout = LibOrganizationAdminStorage.layout();

        // Store previous admin configuration for the event
        LibOrganizationAdminStorage.AdminPermission memory previousAdmin = adminLayout.adminPermission;

        // Update admin permissions
        adminLayout.adminPermission = LibOrganizationAdminStorage.AdminPermission({
            adminType: newAdminType,
            adminMember: newAdminType == AdminType.Member ? newAdminMember : address(0),
            adminGroupId: newAdminType == AdminType.Group ? newAdminGroupId : bytes32(0),
            votingThreshold: newAdminType == AdminType.Group ? newVotingThreshold : 0
        });

        // Emit event
        emit AdminPermissionUpdated(
            previousAdmin.adminType,
            previousAdmin.adminMember,
            previousAdmin.adminGroupId,
            previousAdmin.votingThreshold,
            newAdminType,
            adminLayout.adminPermission.adminMember,
            adminLayout.adminPermission.adminGroupId,
            adminLayout.adminPermission.votingThreshold
        );
    }

    /**
     * @notice Validates that the provided signatures meet the admin authorization requirements
     * @dev This function computes the nonce, verifies that the signatures are from authorized admin members/group
     *      using Merkle proofs, meets the required voting threshold, checks nonce and chainId for replay protection,
     *      and marks the nonce as used. This function will revert if authorization fails.
     * @param operationType The type of operation being performed
     * @param operationData The ABI-encoded data of the operation
     * @param salt A user-provided salt for nonce computation
     * @param expirationTimestamp The timestamp after which the signatures are no longer valid
     * @param isApproval Whether this is an approval (true) or rejection (false)
     * @param signatures The signatures to validate
     * @param adminProofs The Merkle proofs for admin membership verification
     */
    function validateAdminAuthorization(
        OperationType operationType,
        bytes memory operationData,
        uint256 salt,
        uint256 expirationTimestamp,
        bool isApproval,
        bytes memory signatures,
        AdminProofs memory adminProofs
    )
        internal
    {
        // Check if the operation has expired
        if (block.timestamp > expirationTimestamp) {
            revert AdminOperationExpired(expirationTimestamp, block.timestamp);
        }

        // Compute deterministic nonce from operation data and salt
        uint256 nonce = LibOrganizationSignatures.computeNonce(operationType, operationData, salt);

        // Validate and consume nonce for replay protection (will revert if already used)
        LibOrganizationSignatures.validateAndConsumeNonce(nonce);

        // Get operation hash for signature verification
        // Note: isApproval is included to ensure rejection signatures cannot be used for execution and vice versa
        bytes32 operationHash =
            _getAdminOperationHash(operationType, operationData, salt, expirationTimestamp, isApproval);

        LibOrganizationAdminStorage.Layout storage adminLayout = LibOrganizationAdminStorage.layout();

        bool isAuthorized = false;

        // Case: Admin is an individual member
        if (adminLayout.adminPermission.adminType == AdminType.Member) {
            isAuthorized = _hasValidAdminMemberSignature(signatures, operationHash, adminProofs);
        }
        // Case: Admin is a group
        else if (adminLayout.adminPermission.adminType == AdminType.Group) {
            uint256 validSignatures = _getValidAdminGroupSignatures(signatures, operationHash, adminProofs);
            isAuthorized = validSignatures >= adminLayout.adminPermission.votingThreshold;
        }

        // Revert if not authorized
        if (!isAuthorized) {
            revert AdminOperationRejected("Insufficient authorization for admin operation");
        }
    }

    /**
     * @notice Checks if there is a valid signature from the admin member
     * @param signatures The signatures to verify
     * @param operationHash The hash of the admin operation
     * @param adminProofs The Merkle proofs for membership verification
     * @return True if there is a valid signature from the admin member, false otherwise
     */
    function _hasValidAdminMemberSignature(
        bytes memory signatures,
        bytes32 operationHash,
        AdminProofs memory adminProofs
    )
        private
        view
        returns (bool)
    {
        // Check that we have exactly one signature (65 bytes: r: 32, s: 32, v: 1)
        if (signatures.length != 65) return false;

        // Check that we have a member proof
        if (adminProofs.memberProofs.length == 0) return false;

        LibOrganizationAdminStorage.Layout storage adminLayout = LibOrganizationAdminStorage.layout();

        // Get the admin member's address directly from storage
        address adminMemberAddress = adminLayout.adminPermission.adminMember;
        if (adminMemberAddress == address(0)) return false;

        // Extract signer address from signature
        address signer = LibOrganizationSignatures.extractSigner(signatures);

        // Check if signer is the admin member
        if (signer != adminMemberAddress) return false;

        // Verify the signer is still a member of the organization using Merkle proof
        if (!LibOrganizationMembers.verifyMembership(signer, adminProofs.memberProofs[0])) {
            return false;
        }

        // Verify the signature using ERC-1271
        return SignatureChecker.isValidSignatureNow(signer, operationHash, signatures);
    }

    /**
     * @notice Counts valid signatures from members of the admin group
     * @param signatures The signatures to verify
     * @param operationHash The hash of the admin operation
     * @param adminProofs The Merkle proofs for membership verification
     * @return The number of valid signatures from admin group members
     */
    function _getValidAdminGroupSignatures(
        bytes memory signatures,
        bytes32 operationHash,
        AdminProofs memory adminProofs
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

        // Verify the admin group matches what's stored
        if (adminProofs.group.groupId != adminLayout.adminPermission.adminGroupId) {
            return 0;
        }

        // Verify the admin group exists
        if (!LibOrganizationGroups.verifyGroupExists(adminProofs.group, adminProofs.groupExistenceProof)) {
            return 0;
        }

        // Iterate over signatures to count valid ones from admin group members
        for (uint8 i = 0; i < signatureCount; ++i) {
            bytes memory signature = SignatureUtils.extractSignature(signatures, i);

            // Extract signer address from signature
            address signer = LibOrganizationSignatures.extractSigner(signature);

            // Skip if signer is invalid
            if (signer == address(0)) continue;

            // Check for duplicate signers - signers must be unique and in ascending order
            if (signer <= lastSigner) continue;

            // Update last signer for next iteration
            lastSigner = signer;

            // Verify the signature using ERC-1271
            if (!SignatureChecker.isValidSignatureNow(signer, operationHash, signature)) {
                continue;
            }

            // Check proofs arrays have enough entries
            if (i >= adminProofs.memberProofs.length || i >= adminProofs.memberInGroupProofs.length) {
                continue;
            }

            // Verify the signer is a member of the organization
            if (!LibOrganizationMembers.verifyMembership(signer, adminProofs.memberProofs[i])) {
                continue;
            }

            // Verify the signer is in the admin group
            if (
                LibOrganizationGroups.verifyMemberInGroup(
                    signer, adminProofs.group.groupMembersRoot, adminProofs.memberInGroupProofs[i]
                )
            ) {
                ++validSignatures;
            }
        }

        return validSignatures;
    }

    /**
     * @notice Creates a hash of the admin operation for signature verification using EIP-712 typed data
     * @param operationType The type of operation being performed
     * @param operationData The ABI-encoded data of the operation
     * @param salt The user-provided salt for nonce computation
     * @param expirationTimestamp The timestamp after which the signatures are no longer valid
     * @param isApproval Whether this is an approval (true) or rejection (false) signature
     * @return The hash of the admin operation formatted for ERC-1271 signature verification
     */
    function _getAdminOperationHash(
        OperationType operationType,
        bytes memory operationData,
        uint256 salt,
        uint256 expirationTimestamp,
        bool isApproval
    )
        private
        view
        returns (bytes32)
    {
        // Create EIP-712 structured data hash
        // Note: isApproval is included to differentiate execution signatures from rejection signatures
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "AdminOperation(uint8 operationType,bytes operationData,uint256 salt,uint256 expirationTimestamp,bool isApproval,uint256 chainId,address organization)"
                ),
                uint8(operationType),
                keccak256(operationData),
                salt,
                expirationTimestamp,
                isApproval,
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
