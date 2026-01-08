// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { LibOrganizationAdminStorage } from "./storage/LibOrganizationAdminStorage.sol";
import { LibOrganizationSignatures } from "./LibOrganizationSignatures.sol";
import { LibOrganizationMembers } from "./LibOrganizationMembers.sol";
import { SignatureUtils } from "../../libraries/SignatureUtils.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { OperationType } from "../../interfaces/IOrganization.sol";
import { MerkleUtils } from "../../libraries/MerkleUtils.sol";

/**
 * @title Lib Organization Admin
 * @notice Library for admin-related operations for Organization contracts
 * @dev This library should ONLY be used by Organization contracts.
 *      Admin membership is verified via Merkle proofs.
 *      Admins are stored as a Merkle tree of member addresses.
 * @author Den Technologies Inc
 */
library LibOrganizationAdmin {
    // ================================
    // STRUCTS
    // ================================

    /**
     * @notice Data needed to validate that all admins are members of the organization
     * @dev Used by modifyMembers, modifyAdmins, and initialize to prevent bricking
     * @param adminAddresses All admin addresses (must match adminCount, in ascending order)
     * @param adminTreeProofs Merkle proofs that each address is in adminsRoot
     * @param memberTreeProofs Merkle proofs that each address is in membersRoot
     */
    struct AdminMembershipValidation {
        address[] adminAddresses;
        bytes32[][] adminTreeProofs;
        bytes32[][] memberTreeProofs;
    }

    /**
     * @notice Proofs needed to verify admin authorization for signing operations
     * @dev Contains per-signer proofs for admin tree and organization membership
     * @param adminTreeProofs Per-signer merkle proofs that each signer is in the adminsRoot
     * @param memberProofs Per-signer merkle proofs that each signer is in the organization's membersRoot
     */
    struct AdminProofs {
        bytes32[][] adminTreeProofs;
        bytes32[][] memberProofs;
    }

    // ================================
    // EVENTS
    // ================================

    /**
     * @notice Emitted when admin permissions are updated
     * @param previousAdminsRoot The previous admins merkle root
     * @param previousAdminCount The previous admin count
     * @param previousVotingThreshold The previous voting threshold
     * @param newAdminsRoot The new admins merkle root
     * @param newAdminCount The new admin count
     * @param newVotingThreshold The new voting threshold
     */
    event AdminPermissionUpdated(
        bytes32 previousAdminsRoot,
        uint256 previousAdminCount,
        uint256 previousVotingThreshold,
        bytes32 newAdminsRoot,
        uint256 newAdminCount,
        uint256 newVotingThreshold
    );

    // ================================
    // ERRORS
    // ================================

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
     * @notice Emitted when admin count doesn't match expected
     * @param expected The expected admin count
     * @param provided The provided admin count
     */
    error AdminCountMismatch(uint256 expected, uint256 provided);

    /**
     * @notice Emitted when admin addresses are not in ascending order or have duplicates
     * @param address_ The duplicate or out-of-order address
     */
    error DuplicateOrUnorderedAdminAddress(address address_);

    /**
     * @notice Emitted when an admin is not in the admin tree
     * @param admin The address that is not in the admin tree
     */
    error AdminNotInTree(address admin);

    /**
     * @notice Emitted when an admin is not a member of the organization
     * @param admin The address that is not a member
     */
    error AdminNotMember(address admin);

    /**
     * @notice Emitted when voting threshold is invalid
     * @param votingThreshold The invalid voting threshold
     * @param adminCount The admin count
     */
    error InvalidVotingThreshold(uint256 votingThreshold, uint256 adminCount);

    /**
     * @notice Emitted when admin count is zero
     */
    error AdminCountCannotBeZero();

    /**
     * @notice Emitted when admin root is zero
     */
    error AdminRootCannotBeZero();

    // ================================
    // ADMIN TREE VERIFICATION
    // ================================

    /**
     * @notice Checks if an address is in the admin tree
     * @param admin The address to check
     * @param adminsRoot The merkle root of the admin tree
     * @param proof The merkle proof
     * @return True if the address is in the admin tree, false otherwise
     */
    function isAdminInTree(address admin, bytes32 adminsRoot, bytes32[] memory proof) internal pure returns (bool) {
        if (adminsRoot == bytes32(0)) return false;
        bytes32 leaf = MerkleUtils.computeAddressLeaf(admin);
        return MerkleProof.verify(proof, adminsRoot, leaf);
    }

    // ================================
    // SHARED VALIDATION HELPER
    // ================================

    /**
     * @notice Validates that all admins are members of the organization
     * @dev Used by modifyMembers, modifyAdmins, and initialize to prevent bricking.
     *      Admin addresses must be in strictly ascending order to prevent duplicates.
     * @param validation The validation data containing admin addresses and proofs
     * @param adminsRoot The merkle root of the admin tree
     * @param membersRoot The merkle root of the members tree
     * @param expectedAdminCount The expected number of admins (for completeness check)
     */
    function validateAllAdminsAreMembersOrRevert(
        AdminMembershipValidation memory validation,
        bytes32 adminsRoot,
        bytes32 membersRoot,
        uint256 expectedAdminCount
    )
        internal
        pure
    {
        // Check completeness: admin addresses array must match expected count
        if (validation.adminAddresses.length != expectedAdminCount) {
            revert AdminCountMismatch(expectedAdminCount, validation.adminAddresses.length);
        }

        // Track last admin address to ensure ascending order (prevents duplicates)
        address lastAdmin = address(0);

        for (uint256 i = 0; i < validation.adminAddresses.length; ++i) {
            address admin = validation.adminAddresses[i];

            // Check for duplicates and ascending order
            if (admin <= lastAdmin) {
                revert DuplicateOrUnorderedAdminAddress(admin);
            }
            lastAdmin = admin;

            // Verify admin is in the admin tree
            if (!isAdminInTree(admin, adminsRoot, validation.adminTreeProofs[i])) {
                revert AdminNotInTree(admin);
            }

            // Verify admin is a member of the organization
            if (!LibOrganizationMembers.isMemberInTree(admin, membersRoot, validation.memberTreeProofs[i])) {
                revert AdminNotMember(admin);
            }
        }
    }

    /**
     * @notice Validates the admin configuration parameters
     * @dev Used by initialize and modifyAdmins to ensure valid admin configuration.
     *      Validates that adminsRoot is not zero, adminCount is not zero, and votingThreshold is valid.
     * @param adminsRoot The merkle root of admin addresses
     * @param adminCount The number of admins
     * @param votingThreshold The voting threshold for admin operations
     */
    function validateAdminConfigurationOrRevert(
        bytes32 adminsRoot,
        uint256 adminCount,
        uint256 votingThreshold
    )
        internal
        pure
    {
        if (adminsRoot == bytes32(0)) {
            revert AdminRootCannotBeZero();
        }
        if (adminCount == 0) {
            revert AdminCountCannotBeZero();
        }
        if (votingThreshold == 0 || votingThreshold > adminCount) {
            revert InvalidVotingThreshold(votingThreshold, adminCount);
        }
    }

    // ================================
    // ADMIN PERMISSION MANAGEMENT
    // ================================

    /**
     * @notice Gets the current admin permission configuration
     * @return The current admin permission configuration
     */
    function adminPermission() internal view returns (LibOrganizationAdminStorage.AdminPermission memory) {
        return LibOrganizationAdminStorage.layout().adminPermission;
    }

    /**
     * @notice Updates the admin permissions for the organization
     * @dev Validates that all new admins are members before updating.
     *      Admin addresses must be in ascending order.
     * @param newAdminsRoot The new merkle root of admin addresses
     * @param newAdminCount The number of admins in the new tree
     * @param newVotingThreshold The new voting threshold
     * @param validation The validation data to verify all new admins are members
     * @param currentMembersRoot The current members root to validate against
     */
    function modifyAdmins(
        bytes32 newAdminsRoot,
        uint256 newAdminCount,
        uint256 newVotingThreshold,
        AdminMembershipValidation memory validation,
        bytes32 currentMembersRoot
    )
        internal
    {
        // Validate admin configuration (root, count, threshold)
        validateAdminConfigurationOrRevert(newAdminsRoot, newAdminCount, newVotingThreshold);

        // Validate all new admins are current members of the organization
        validateAllAdminsAreMembersOrRevert(validation, newAdminsRoot, currentMembersRoot, newAdminCount);

        LibOrganizationAdminStorage.Layout storage adminLayout = LibOrganizationAdminStorage.layout();

        // Store previous admin configuration for the event
        LibOrganizationAdminStorage.AdminPermission memory previousAdmin = adminLayout.adminPermission;

        // Update admin permissions
        adminLayout.adminPermission = LibOrganizationAdminStorage.AdminPermission({
            adminsRoot: newAdminsRoot,
            adminCount: newAdminCount,
            votingThreshold: newVotingThreshold
        });

        // Emit event
        emit AdminPermissionUpdated(
            previousAdmin.adminsRoot,
            previousAdmin.adminCount,
            previousAdmin.votingThreshold,
            newAdminsRoot,
            newAdminCount,
            newVotingThreshold
        );
    }

    // ================================
    // ADMIN AUTHORIZATION
    // ================================

    /**
     * @notice Validates that the provided signatures meet the admin authorization requirements
     * @dev This function computes the nonce, verifies that the signatures are from authorized admins
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

        // Count valid signatures from admins
        uint256 validSignatures = _getValidAdminSignatures(signatures, operationHash, adminProofs);

        // Check if we have enough valid signatures
        if (validSignatures < adminLayout.adminPermission.votingThreshold) {
            revert AdminOperationRejected("Insufficient authorization for admin operation");
        }
    }

    /**
     * @notice Counts valid signatures from admin members
     * @param signatures The signatures to verify
     * @param operationHash The hash of the admin operation
     * @param adminProofs The Merkle proofs for membership verification
     * @return The number of valid signatures from admins
     */
    function _getValidAdminSignatures(
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
        bytes32 adminsRoot = adminLayout.adminPermission.adminsRoot;

        // Cache membersRoot to avoid repeated storage reads in the loop
        bytes32 membersRoot = LibOrganizationMembers.getMembersRoot();

        // Iterate over signatures to count valid ones from admin members
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
            if (i >= adminProofs.adminTreeProofs.length || i >= adminProofs.memberProofs.length) {
                continue;
            }

            // Verify the signer is in the admin tree
            if (!isAdminInTree(signer, adminsRoot, adminProofs.adminTreeProofs[i])) {
                continue;
            }

            // Verify the signer is a member of the organization (using cached root)
            if (!LibOrganizationMembers.isMemberInTree(signer, membersRoot, adminProofs.memberProofs[i])) {
                continue;
            }

            ++validSignatures;
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
