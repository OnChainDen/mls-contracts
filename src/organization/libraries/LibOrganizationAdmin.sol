// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OperationType} from "../../interfaces/IOrganization.sol";
import {MerkleUtils} from "../../libraries/MerkleUtils.sol";
import {SignatureUtils} from "../../libraries/SignatureUtils.sol";
import {LibOrganizationEIP712} from "./LibOrganizationEIP712.sol";
import {LibOrganizationMembers} from "./LibOrganizationMembers.sol";
import {LibOrganizationSignatures} from "./LibOrganizationSignatures.sol";
import {LibOrganizationAdminStorage} from "./storage/LibOrganizationAdminStorage.sol";

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title Lib Organization Admin
 * @notice Library for admin-related operations for Organization contracts
 * @dev This library should ONLY be used by Organization contracts.
 *      Admin membership is verified via Merkle proofs.
 *      Admins are stored as a Merkle tree of member addresses.
 * @author Den Technologies Inc
 */
library LibOrganizationAdmin {
    /**
     * @notice Data needed to validate that all admins are members of the organization
     * @dev Used by setMembers, setAdmins, and initialize to prevent bricking
     * @param adminAddresses All admin addresses (must match adminCount, in ascending order)
     * @param adminInOrgAdminTreeProofs Merkle proofs that each address is in adminsRoot
     * @param adminInOrgMembersTreeProofs Merkle proofs that each address is in membersRoot
     */
    struct AdminMembershipValidation {
        address[] adminAddresses;
        bytes32[][] adminInOrgAdminTreeProofs;
        bytes32[][] adminInOrgMembersTreeProofs;
    }

    /**
     * @notice Proofs needed to verify admin authorization for signing operations
     * @dev Contains per-signer proofs for admin tree and organization membership
     * @param adminInOrgAdminTreeProofs Per-signer merkle proofs that each signer is in the adminsRoot
     * @param adminInOrgMembersTreeProofs Per-signer merkle proofs that each signer is in the organization's membersRoot
     */
    struct AdminProofs {
        bytes32[][] adminInOrgAdminTreeProofs;
        bytes32[][] adminInOrgMembersTreeProofs;
    }

    /**
     * @notice Emitted when admin permissions are updated
     * @param previousAdminsRoot The previous admins merkle root
     * @param previousAdminCount The previous admin count
     * @param previousVotingThreshold The previous voting threshold
     * @param newAdminsRoot The new admins merkle root
     * @param newAdminCount The new admin count
     * @param newVotingThreshold The new voting threshold
     * @param newAdminAddresses The new admin addresses (in ascending order)
     */
    event AdminPermissionUpdated(
        bytes32 previousAdminsRoot,
        uint256 previousAdminCount,
        uint256 previousVotingThreshold,
        bytes32 newAdminsRoot,
        uint256 newAdminCount,
        uint256 newVotingThreshold,
        address[] newAdminAddresses
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
     * @notice Emitted when admin configuration is invalid
     * @param reason The reason for the invalid configuration
     */
    error InvalidAdminConfiguration(string reason);

    /**
     * @notice Emitted when admin tree proofs length doesn't match signature count
     * @param expected The expected length (signature count)
     * @param actual The actual length of proofs array
     */
    error AdminTreeProofsLengthMismatch(uint256 expected, uint256 actual);

    /**
     * @notice Emitted when members tree proofs length doesn't match signature count
     * @param expected The expected length (signature count)
     * @param actual The actual length of proofs array
     */
    error MembersTreeProofsLengthMismatch(uint256 expected, uint256 actual);

    /**
     * @notice Sets the admin permissions for the organization
     * @dev Validates that all new admins are members before updating.
     *      Admin addresses must be in ascending order.
     * @param newAdminsRoot The new merkle root of admin addresses
     * @param newAdminCount The number of admins in the new tree
     * @param newVotingThreshold The new voting threshold
     * @param validation The validation data to verify all new admins are members
     * @param currentMembersRoot The current members root to validate against
     */
    function setAdmins(
        bytes32 newAdminsRoot,
        uint256 newAdminCount,
        uint256 newVotingThreshold,
        AdminMembershipValidation memory validation,
        bytes32 currentMembersRoot
    ) internal {
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
        emit AdminPermissionUpdated({
            previousAdminsRoot: previousAdmin.adminsRoot,
            previousAdminCount: previousAdmin.adminCount,
            previousVotingThreshold: previousAdmin.votingThreshold,
            newAdminsRoot: newAdminsRoot,
            newAdminCount: newAdminCount,
            newVotingThreshold: newVotingThreshold,
            newAdminAddresses: validation.adminAddresses
        });
    }

    /**
     * @notice Validates that the provided signatures meet the admin authorization requirements
     * @dev This function computes the nonce, verifies that the signatures are from authorized admins
     *      using Merkle proofs, meets the required voting threshold, checks nonce and chainId for replay protection,
     *      and marks the nonce as used. Reverts if authorization fails.
     * @param operationType The type of operation being performed
     * @param operationData The ABI-encoded data of the operation
     * @param salt A user-provided salt for nonce computation
     * @param expirationTimestamp The timestamp after which the signatures are no longer valid
     * @param isApproval Whether this is an approval (true) or rejection (false)
     * @param signatures The signatures to validate
     * @param adminProofs The Merkle proofs for admin membership verification
     */
    function validateAdminAuthorizationOrRevert(
        OperationType operationType,
        bytes memory operationData,
        uint256 salt,
        uint256 expirationTimestamp,
        bool isApproval,
        bytes memory signatures,
        AdminProofs memory adminProofs
    ) internal {
        // Check if the operation has expired
        if (block.timestamp > expirationTimestamp) {
            revert AdminOperationExpired(expirationTimestamp, block.timestamp);
        }

        // Compute deterministic nonce from operation data and salt
        uint256 nonce = LibOrganizationSignatures.computeNonce(operationType, operationData, salt);

        // Validate and consume nonce for replay protection (will revert if already used)
        LibOrganizationSignatures.validateAndConsumeNonceOrRevert(nonce);

        // Get operation hash for signature verification
        // Note: isApproval is included to ensure rejection signatures cannot be used for execution and vice versa
        bytes32 operationHash = _getAdminOperationHash({
            operationType: operationType,
            operationData: operationData,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            isApproval: isApproval
        });

        LibOrganizationAdminStorage.Layout storage adminLayout = LibOrganizationAdminStorage.layout();

        // Count valid signatures from admins
        uint256 validSignatures = _getValidAdminSignatures(signatures, operationHash, adminProofs);

        // Check if we have enough valid signatures
        if (validSignatures < adminLayout.adminPermission.votingThreshold) {
            revert AdminOperationRejected("Insufficient authorization for admin operation");
        }
    }

    /**
     * @notice Gets the current admin permission configuration
     * @return The current admin permission configuration
     */
    function getAdminPermission() internal view returns (LibOrganizationAdminStorage.AdminPermission memory) {
        return LibOrganizationAdminStorage.layout().adminPermission;
    }

    /**
     * @notice Validates that all admins are members of the organization
     * @dev Used by setMembers, setAdmins, and initialize to prevent bricking.
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
    ) internal pure {
        // Case: Admin addresses array does not match expected count
        if (validation.adminAddresses.length != expectedAdminCount) {
            revert AdminCountMismatch(expectedAdminCount, validation.adminAddresses.length);
        }

        // Track last admin address to ensure ascending order (prevents duplicates)
        address lastAdmin = address(0);

        for (uint256 i = 0; i < validation.adminAddresses.length; ++i) {
            address admin = validation.adminAddresses[i];

            // Case: Admin address is not in ascending order or has duplicates
            if (admin <= lastAdmin) {
                revert DuplicateOrUnorderedAdminAddress(admin);
            }
            lastAdmin = admin;

            // Case: Admin is not in the admin tree
            if (!_isAdminInTree(admin, adminsRoot, validation.adminInOrgAdminTreeProofs[i])) {
                revert AdminNotInTree(admin);
            }

            // Case: Admin is not a member in the members tree
            if (!LibOrganizationMembers.isMemberInTree(admin, membersRoot, validation.adminInOrgMembersTreeProofs[i])) {
                revert AdminNotMember(admin);
            }
        }
    }

    /**
     * @notice Validates the admin configuration parameters
     * @dev Used by initialize and setAdmins to ensure valid admin configuration.
     *      Validates that adminsRoot is not zero, adminCount is not zero, and votingThreshold is valid.
     * @param adminsRoot The merkle root of admin addresses
     * @param adminCount The number of admins
     * @param votingThreshold The voting threshold for admin operations
     */
    function validateAdminConfigurationOrRevert(bytes32 adminsRoot, uint256 adminCount, uint256 votingThreshold)
        internal
        pure
    {
        if (adminsRoot == bytes32(0)) {
            revert InvalidAdminConfiguration("Admin root cannot be zero");
        }
        if (adminCount == 0) {
            revert InvalidAdminConfiguration("Admin count cannot be zero");
        }
        if (votingThreshold == 0 || votingThreshold > adminCount) {
            revert InvalidAdminConfiguration("Invalid voting threshold");
        }
    }

    /**
     * @notice Counts valid signatures from admin members
     * @param signatures The signatures to verify
     * @param operationHash The hash of the admin operation
     * @param adminProofs The Merkle proofs for membership verification
     * @return The number of valid signatures from admins
     */
    function _getValidAdminSignatures(bytes memory signatures, bytes32 operationHash, AdminProofs memory adminProofs)
        private
        view
        returns (uint256)
    {
        // Case: No signatures provided
        if (signatures.length == 0) return 0;

        uint8 signatureCount = SignatureUtils.getSignatureCount(signatures);

        // Validate admin proofs lengths
        _validateAdminProofsOrRevert(adminProofs, signatureCount);

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

            // Recover signer address from signature (reverts on invalid signature)
            address signer = ECDSA.recover(operationHash, signature);

            // Case: Signer address is not in ascending order or has duplicates
            if (signer <= lastSigner) continue;

            // Update last signer for next iteration
            lastSigner = signer;

            // Case: Signer is not in the admin tree
            if (!_isAdminInTree(signer, adminsRoot, adminProofs.adminInOrgAdminTreeProofs[i])) {
                continue;
            }

            // Case: Signer is not a member in the members tree
            if (!LibOrganizationMembers.isMemberInTree(signer, membersRoot, adminProofs.adminInOrgMembersTreeProofs[i]))
            {
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
    ) private view returns (bytes32) {
        // Create EIP-712 structured data hash
        // Note: isApproval is included to differentiate execution signatures from rejection signatures
        bytes32 structHash = keccak256(
            abi.encode(
                LibOrganizationEIP712.ADMIN_OPERATION_TYPEHASH,
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
        return LibOrganizationEIP712.computeTypedDataHash(structHash);
    }

    /**
     * @notice Validates that admin proofs have correct lengths
     * @dev Reverts if proof arrays don't match signature count
     * @param adminProofs The proofs for admin membership verification
     * @param signatureCount The number of signatures provided
     */
    function _validateAdminProofsOrRevert(AdminProofs memory adminProofs, uint8 signatureCount) private pure {
        if (adminProofs.adminInOrgAdminTreeProofs.length != signatureCount) {
            revert AdminTreeProofsLengthMismatch(signatureCount, adminProofs.adminInOrgAdminTreeProofs.length);
        }

        if (adminProofs.adminInOrgMembersTreeProofs.length != signatureCount) {
            revert MembersTreeProofsLengthMismatch(signatureCount, adminProofs.adminInOrgMembersTreeProofs.length);
        }
    }

    /**
     * @notice Checks if an address is in the admin tree
     * @param admin The address to check
     * @param adminsRoot The merkle root of the admin tree
     * @param proof The merkle proof
     * @return True if the address is in the admin tree, false otherwise
     */
    function _isAdminInTree(address admin, bytes32 adminsRoot, bytes32[] memory proof) private pure returns (bool) {
        if (adminsRoot == bytes32(0)) return false;
        bytes32 leaf = MerkleUtils.computeAddressLeaf(admin);
        return MerkleProof.verify(proof, adminsRoot, leaf);
    }
}
