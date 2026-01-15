// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Interfaces
import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";

// Types
import {AdminAuthParams, AdminConfig, AllAdminsInOrgProofs, SigningAdminsInOrgProofs} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

// Libraries
import {MerkleUtils} from "libraries/MerkleUtils.sol";
import {SignatureUtils} from "libraries/SignatureUtils.sol";
import {LibOrganizationEIP712} from "organization/libraries/LibOrganizationEIP712.sol";
import {LibOrganizationMembers} from "organization/libraries/LibOrganizationMembers.sol";
import {LibOrganizationSignatures} from "organization/libraries/LibOrganizationSignatures.sol";
import {LibOrganizationAdminStorage} from "organization/libraries/storage/LibOrganizationAdminStorage.sol";

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title Lib Organization Admin
 * @dev Library for admin-related operations for Organization contracts
 * @dev This library should ONLY be used by Organization contracts.
 *      Admin membership is verified via Merkle proofs.
 *      Admins are stored as a Merkle tree of member addresses.
 * @author Den Technologies Inc
 */
library LibOrganizationAdmin {
    /**
     * @dev Sets the admin permissions for the organization
     * @dev Validates that all new admins are members before updating.
     *      Admin addresses must be in ascending order.
     * @param newAdminsRoot The new merkle root of admin addresses
     * @param newAdminCount The number of admins in the new tree
     * @param newVotingThreshold The new voting threshold
     * @param newAdminsInOrgProofs Proofs that all new admins are in the organization (admin tree and members tree)
     * @param currentMembersRoot The current members root to validate against
     */
    function setAdmins(
        bytes32 newAdminsRoot,
        uint256 newAdminCount,
        uint256 newVotingThreshold,
        AllAdminsInOrgProofs memory newAdminsInOrgProofs,
        bytes32 currentMembersRoot
    ) internal {
        // Validate admin configuration (root, count, threshold)
        validateAdminConfigurationOrRevert(newAdminsRoot, newAdminCount, newVotingThreshold);

        // Validate all new admins are current members of the organization
        validateAllAdminsAreMembersOrRevert(newAdminsInOrgProofs, newAdminsRoot, currentMembersRoot, newAdminCount);

        LibOrganizationAdminStorage.Layout storage adminLayout = LibOrganizationAdminStorage.layout();

        // Store previous admin configuration for the event
        AdminConfig memory previousAdmin = adminLayout.adminConfig;

        // Update admin permissions
        adminLayout.adminConfig.adminsRoot = newAdminsRoot;
        adminLayout.adminConfig.adminCount = newAdminCount;
        adminLayout.adminConfig.votingThreshold = newVotingThreshold;

        // Emit event
        emit IOrganizationAdmin.AdminConfigUpdated({
            previousAdminsRoot: previousAdmin.adminsRoot,
            previousAdminCount: previousAdmin.adminCount,
            previousVotingThreshold: previousAdmin.votingThreshold,
            newAdminsRoot: newAdminsRoot,
            newAdminCount: newAdminCount,
            newVotingThreshold: newVotingThreshold,
            newAdminAddresses: newAdminsInOrgProofs.adminAddresses
        });
    }

    /**
     * @dev Validates that the provided signatures meet the admin authorization requirements
     * @dev This function computes the nonce, verifies that the signatures are from authorized admins
     *      using Merkle proofs, meets the required voting threshold, checks nonce and chainId for replay protection,
     *      and marks the nonce as used. Reverts if authorization fails.
     * @param operationType The type of operation being performed
     * @param operationData The ABI-encoded data of the operation
     * @param isApproval Whether this is an approval (true) or rejection (false)
     * @param authParams The authorization parameters (salt, expiration, signatures, and admin proofs)
     */
    function validateAdminAuthAndConsumeNonceOrRevert(
        OperationType operationType,
        bytes memory operationData,
        bool isApproval,
        AdminAuthParams memory authParams
    ) internal {
        // Check if the operation has expired
        if (block.timestamp > authParams.expirationTimestamp) {
            revert IOrganizationAdmin.AdminOperationExpired(authParams.expirationTimestamp, block.timestamp);
        }

        // Compute deterministic nonce from operation data and salt
        uint256 nonce = LibOrganizationSignatures.computeNonce(operationType, operationData, authParams.salt);

        // Validate and consume nonce for replay protection (will revert if already used)
        LibOrganizationSignatures.validateAndConsumeNonceOrRevert(nonce);

        // Get operation hash for signature verification
        // Note: isApproval is included to ensure rejection signatures cannot be used for execution and vice versa
        bytes32 operationHash = _getAdminOperationHash({
            operationType: operationType,
            operationData: operationData,
            salt: authParams.salt,
            expirationTimestamp: authParams.expirationTimestamp,
            isApproval: isApproval
        });

        LibOrganizationAdminStorage.Layout storage adminLayout = LibOrganizationAdminStorage.layout();

        // Count valid signatures from admins
        // forgefmt: disable-next-item
        uint256 validSignatures = _getValidAdminSignatures(
            authParams.signatures, 
            operationHash, 
            authParams.signingAdminsInOrgProofs
        );

        // Check if we have enough valid signatures
        if (validSignatures < adminLayout.adminConfig.votingThreshold) {
            revert IOrganizationAdmin.InsufficientAdminAuthorization();
        }
    }

    /**
     * @dev Gets the current admin permission configuration
     * @return The current admin permission configuration
     */
    function getAdminConfig() internal view returns (AdminConfig memory) {
        return LibOrganizationAdminStorage.layout().adminConfig;
    }

    /**
     * @dev Validates that all admins are members of the organization
     * @dev Used by setMembers, setAdmins, and initialize to prevent bricking.
     *      Admin addresses must be in strictly ascending order to prevent duplicates.
     * @param allAdminsInOrgProofs Proofs that all admins are in the organization (admin tree and members tree)
     * @param adminsRoot The merkle root of the admin tree
     * @param membersRoot The merkle root of the members tree
     * @param expectedAdminCount The expected number of admins (for completeness check)
     */
    function validateAllAdminsAreMembersOrRevert(
        AllAdminsInOrgProofs memory allAdminsInOrgProofs,
        bytes32 adminsRoot,
        bytes32 membersRoot,
        uint256 expectedAdminCount
    ) internal pure {
        // Case: Admin addresses array does not match expected count
        if (allAdminsInOrgProofs.adminAddresses.length != expectedAdminCount) {
            // forgefmt: disable-next-item
            revert IOrganizationAdmin.AdminCountMismatch(
                    expectedAdminCount, 
                    allAdminsInOrgProofs.adminAddresses.length
                );
        }

        // Track last admin address to ensure ascending order (prevents duplicates)
        address lastAdmin = address(0);

        for (uint256 i = 0; i < allAdminsInOrgProofs.adminAddresses.length; ++i) {
            address admin = allAdminsInOrgProofs.adminAddresses[i];

            // Case: Admin address is not in ascending order or has duplicates
            if (admin <= lastAdmin) {
                revert IOrganizationAdmin.DuplicateOrUnorderedAdminAddress(admin);
            }
            lastAdmin = admin;

            // Case: Admin is not in the admin tree
            if (!_isAdminInTree(admin, adminsRoot, allAdminsInOrgProofs.adminInOrgAdminTreeProofs[i])) {
                revert IOrganizationAdmin.AdminNotInTree(admin);
            }

            // Case: Admin is not a member in the members tree
            bytes32[] memory memberProof = allAdminsInOrgProofs.adminInOrgMembersTreeProofs[i];
            if (!LibOrganizationMembers.isMemberInTree(admin, membersRoot, memberProof)) {
                revert IOrganizationAdmin.AdminNotMember(admin);
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
        if (adminsRoot == bytes32(0) || adminCount == 0 || votingThreshold == 0 || votingThreshold > adminCount) {
            revert IOrganizationAdmin.InvalidAdminConfig();
        }
    }

    /**
     * @dev Counts valid signatures from admin members
     * @param signatures The signatures to verify
     * @param operationHash The hash of the admin operation
     * @param signingAdminsInOrgProofs Proofs that the signing admins are in the organization
     * @return The number of valid signatures from admins
     */
    function _getValidAdminSignatures(
        bytes memory signatures,
        bytes32 operationHash,
        SigningAdminsInOrgProofs memory signingAdminsInOrgProofs
    ) private view returns (uint256) {
        // Case: No signatures provided
        if (signatures.length == 0) return 0;

        uint8 signatureCount = SignatureUtils.getSignatureCount(signatures);

        // Validate admin proofs lengths
        _validateSigningAdminsProofsOrRevert(signingAdminsInOrgProofs, signatureCount);

        uint256 validSignatures = 0;

        // Track last signer to prevent duplicates
        address lastSigner = address(0);

        LibOrganizationAdminStorage.Layout storage adminLayout = LibOrganizationAdminStorage.layout();
        bytes32 adminsRoot = adminLayout.adminConfig.adminsRoot;

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
            if (!_isAdminInTree(signer, adminsRoot, signingAdminsInOrgProofs.adminInOrgAdminTreeProofs[i])) {
                continue;
            }

            // Case: Signer is not a member in the members tree
            if (!LibOrganizationMembers.isMemberInTree(
                    signer, membersRoot, signingAdminsInOrgProofs.adminInOrgMembersTreeProofs[i]
                )) {
                continue;
            }

            ++validSignatures;
        }

        return validSignatures;
    }

    /**
     * @dev Creates a hash of the admin operation for signature verification using EIP-712 typed data
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
     * @dev Validates that signing admin proofs have correct lengths
     * @dev Reverts if proof arrays don't match signature count
     * @param signingAdminsInOrgProofs Proofs that the signing admins are in the organization
     * @param signatureCount The number of signatures provided
     */
    function _validateSigningAdminsProofsOrRevert(
        SigningAdminsInOrgProofs memory signingAdminsInOrgProofs,
        uint8 signatureCount
    ) private pure {
        uint256 adminTreeProofsLength = signingAdminsInOrgProofs.adminInOrgAdminTreeProofs.length;
        if (adminTreeProofsLength != signatureCount) {
            revert IOrganizationAdmin.AdminTreeProofsLengthMismatch(signatureCount, adminTreeProofsLength);
        }

        uint256 membersTreeProofsLength = signingAdminsInOrgProofs.adminInOrgMembersTreeProofs.length;
        if (membersTreeProofsLength != signatureCount) {
            revert IOrganizationAdmin.MembersTreeProofsLengthMismatch(signatureCount, membersTreeProofsLength);
        }
    }

    /**
     * @dev Checks if an address is in the admin tree
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
