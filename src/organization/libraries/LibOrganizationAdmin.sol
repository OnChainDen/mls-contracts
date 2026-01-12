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
 * @dev Library for admin-related operations for Organization contracts
 * @dev This library should ONLY be used by Organization contracts.
 *      Admin membership is verified via Merkle proofs.
 *      Admins are stored as a Merkle tree of member addresses.
 * @author Den Technologies Inc
 */
library LibOrganizationAdmin {
    /**
     * @dev Proofs that ALL admins are members of the organization (in both admin tree and members tree)
     * @dev Used by setMembers, setAdmins, and initialize to prevent bricking.
     *      Contains proofs for every admin in the organization, not just signers.
     * @param adminAddresses All admin addresses (must match adminCount, in ascending order)
     * @param adminInOrgAdminTreeProofs Merkle proofs that each address is in adminsRoot
     * @param adminInOrgMembersTreeProofs Merkle proofs that each address is in membersRoot
     */
    struct AllAdminsInOrgProofs {
        address[] adminAddresses;
        bytes32[][] adminInOrgAdminTreeProofs;
        bytes32[][] adminInOrgMembersTreeProofs;
    }

    /**
     * @dev Proofs that the SIGNING admins are members of the organization (in both admin tree and members tree)
     * @dev Contains per-signer proofs for admin tree and organization membership.
     *      Only contains proofs for admins who signed the operation, not all admins.
     * @param adminInOrgAdminTreeProofs Per-signer merkle proofs that each signer is in the adminsRoot
     * @param adminInOrgMembersTreeProofs Per-signer merkle proofs that each signer is in the organization's membersRoot
     */
    struct SigningAdminsInOrgProofs {
        bytes32[][] adminInOrgAdminTreeProofs;
        bytes32[][] adminInOrgMembersTreeProofs;
    }

    /**
     * @dev Parameters for authorizing admin operations
     * @dev Groups common authorization parameters to reduce function parameter count
     * @param salt A user-provided salt for nonce computation
     * @param expirationTimestamp The timestamp after which the signatures are no longer valid
     * @param signatures The signatures from admin(s) authorizing this operation
     * @param signingAdminsInOrgProofs Proofs that the signing admins are in the organization
     */
    struct AdminAuthParams {
        uint256 salt;
        uint256 expirationTimestamp;
        bytes signatures;
        SigningAdminsInOrgProofs signingAdminsInOrgProofs;
    }

    /**
     * @dev Emitted when admin permissions are updated
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
     * @dev Thrown when an admin operation is rejected due to insufficient authorization
     * @param reason The reason for the rejection
     */
    error AdminOperationRejected(string reason);

    /**
     * @dev Thrown when an admin operation has insufficient signatures
     * @param required The number of required signatures
     * @param provided The number of provided signatures
     */
    error InsufficientAdminSignatures(uint256 required, uint256 provided);

    /**
     * @dev Thrown when an admin operation has an invalid signature
     */
    error InvalidAdminSignature();

    /**
     * @dev Thrown when an admin operation has wrong chain ID
     * @param expected The expected chain ID
     * @param provided The provided chain ID
     */
    error InvalidAdminChainId(uint256 expected, uint256 provided);

    /**
     * @dev Thrown when an admin operation has expired
     * @param expirationTimestamp The expiration timestamp that was exceeded
     * @param currentTimestamp The current block timestamp
     */
    error AdminOperationExpired(uint256 expirationTimestamp, uint256 currentTimestamp);

    /**
     * @dev Thrown when admin count doesn't match expected
     * @param expected The expected admin count
     * @param provided The provided admin count
     */
    error AdminCountMismatch(uint256 expected, uint256 provided);

    /**
     * @dev Thrown when admin addresses are not in ascending order or have duplicates
     * @param address_ The duplicate or out-of-order address
     */
    error DuplicateOrUnorderedAdminAddress(address address_);

    /**
     * @notice Thrown when an admin is not in the admin tree
     * @param admin The address that is not in the admin tree
     */
    error AdminNotInTree(address admin);

    /**
     * @dev Thrown when an admin is not a member of the organization
     * @param admin The address that is not a member
     */
    error AdminNotMember(address admin);

    /**
     * @dev Thrown when admin configuration is invalid
     * @param reason The reason for the invalid configuration
     */
    error InvalidAdminConfiguration(string reason);

    /**
     * @dev Thrown when admin tree proofs length doesn't match signature count
     * @param expected The expected length (signature count)
     * @param actual The actual length of proofs array
     */
    error AdminTreeProofsLengthMismatch(uint256 expected, uint256 actual);

    /**
     * @dev Thrown when members tree proofs length doesn't match signature count
     * @param expected The expected length (signature count)
     * @param actual The actual length of proofs array
     */
    error MembersTreeProofsLengthMismatch(uint256 expected, uint256 actual);

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
        LibOrganizationAdminStorage.AdminPermission memory previousAdmin = adminLayout.adminPermission;

        // Update admin permissions
        adminLayout.adminPermission = LibOrganizationAdminStorage.AdminPermission({
            adminsRoot: newAdminsRoot, adminCount: newAdminCount, votingThreshold: newVotingThreshold
        });

        // Emit event
        emit AdminPermissionUpdated({
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
    function validateAdminAuthorizationOrRevert(
        OperationType operationType,
        bytes memory operationData,
        bool isApproval,
        AdminAuthParams memory authParams
    ) internal {
        // Check if the operation has expired
        if (block.timestamp > authParams.expirationTimestamp) {
            revert AdminOperationExpired(authParams.expirationTimestamp, block.timestamp);
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
        if (validSignatures < adminLayout.adminPermission.votingThreshold) {
            revert AdminOperationRejected("Insufficient authorization for admin operation");
        }
    }

    /**
     * @dev Gets the current admin permission configuration
     * @return The current admin permission configuration
     */
    function getAdminPermission() internal view returns (LibOrganizationAdminStorage.AdminPermission memory) {
        return LibOrganizationAdminStorage.layout().adminPermission;
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
            revert AdminCountMismatch(expectedAdminCount, allAdminsInOrgProofs.adminAddresses.length);
        }

        // Track last admin address to ensure ascending order (prevents duplicates)
        address lastAdmin = address(0);

        for (uint256 i = 0; i < allAdminsInOrgProofs.adminAddresses.length; ++i) {
            address admin = allAdminsInOrgProofs.adminAddresses[i];

            // Case: Admin address is not in ascending order or has duplicates
            if (admin <= lastAdmin) {
                revert DuplicateOrUnorderedAdminAddress(admin);
            }
            lastAdmin = admin;

            // Case: Admin is not in the admin tree
            if (!_isAdminInTree(admin, adminsRoot, allAdminsInOrgProofs.adminInOrgAdminTreeProofs[i])) {
                revert AdminNotInTree(admin);
            }

            // Case: Admin is not a member in the members tree
            bytes32[] memory memberProof = allAdminsInOrgProofs.adminInOrgMembersTreeProofs[i];
            if (!LibOrganizationMembers.isMemberInTree(admin, membersRoot, memberProof)) {
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
            revert AdminTreeProofsLengthMismatch(signatureCount, adminTreeProofsLength);
        }

        uint256 membersTreeProofsLength = signingAdminsInOrgProofs.adminInOrgMembersTreeProofs.length;
        if (membersTreeProofsLength != signatureCount) {
            revert MembersTreeProofsLengthMismatch(signatureCount, membersTreeProofsLength);
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
