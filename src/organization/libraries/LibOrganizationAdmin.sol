// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {IOrganizationMembers} from "interfaces/organization/IOrganizationMembers.sol";
import {SignatureUtils} from "libraries/SignatureUtils.sol";
import {LibOrganizationEIP712} from "organization/libraries/LibOrganizationEIP712.sol";
import {LibOrganizationMembers} from "organization/libraries/LibOrganizationMembers.sol";
import {LibOrganizationSignatures} from "organization/libraries/LibOrganizationSignatures.sol";
import {LibOrganizationAdminStorage} from "organization/libraries/storage/LibOrganizationAdminStorage.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @title Lib Organization Admin
 * @dev Library for admin-related operations for Organization contracts.
 *      This library should ONLY be used by Organization contracts.
 *      Admin membership is verified via mapping lookups (O(1)).
 *      Admins are stored in a mapping with a counter and voting threshold.
 * @author Den Technologies Inc
 */
library LibOrganizationAdmin {
    /**
     * @dev Validates that the provided signatures meet the admin authorization requirements.
     *      This function computes the nonce, verifies that the signatures are from authorized admins
     *      via mapping lookups, meets the required voting threshold, checks nonce and chainId for
     *      replay protection, and marks the nonce as used. Reverts if authorization fails.
     * @param operationType The type of operation being performed
     * @param operationData The ABI-encoded data of the operation
     * @param isApproval Whether this is an approval (true) or rejection (false)
     * @param authParams The authorization parameters (salt, expiration, signatures)
     * @return nonce The consumed nonce derived for the operation
     */
    function validateAdminAuthAndConsumeNonceOrRevert(
        OperationType operationType,
        bytes memory operationData,
        bool isApproval,
        AdminAuthParams memory authParams
    ) public returns (uint256 nonce) {
        // Check if the operation has expired
        if (block.timestamp > authParams.expirationTimestamp) {
            revert IOrganizationAdmin.AdminOperationExpired(authParams.expirationTimestamp, block.timestamp);
        }

        // Compute deterministic nonce from operation data and salt
        nonce = LibOrganizationSignatures.computeNonce(operationType, operationData, authParams.salt);

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

        // Check if there are enough valid signatures from admins
        if (!_areAdminSignaturesValid(authParams.signatures, operationHash)) {
            revert IOrganizationAdmin.InsufficientAdminAuthorization();
        }
    }

    /**
     * @dev Adds and/or removes admins and updates the voting threshold.
     *      All new admins must be current members. Adding a duplicate admin reverts.
     *      Removing a non-existent admin reverts. The voting threshold must always be
     *      explicitly provided as a non-zero value and must be <= adminCount after modifications.
     * @param adminsToAdd Addresses to add as admins
     * @param adminsToRemove Addresses to remove from admins
     * @param newVotingThreshold The new voting threshold (must be non-zero and <= final admin count)
     */
    function modifyAdmins(address[] calldata adminsToAdd, address[] calldata adminsToRemove, uint256 newVotingThreshold)
        public
    {
        LibOrganizationAdminStorage.Layout storage adminLayout = LibOrganizationAdminStorage.layout();

        // Cache admin count in memory to avoid repeated SSTORE operations in the loops
        uint256 adminCount = adminLayout.adminCount;

        // Process additions
        for (uint256 i = 0; i < adminsToAdd.length; ++i) {
            address admin = adminsToAdd[i];
            if (admin == address(0)) {
                revert IOrganizationMembers.InvalidMemberAddress(admin);
            }

            // Case: Admin already exists — revert (not a no-op, unlike members)
            if (adminLayout.isAdmin[admin]) {
                revert IOrganizationAdmin.AdminAlreadyExists(admin);
            }

            // Case: Admin is not a member of the organization
            if (!LibOrganizationMembers.isMember(admin)) {
                revert IOrganizationAdmin.AdminNotMember(admin);
            }

            adminLayout.isAdmin[admin] = true;
            ++adminCount;
            emit IOrganizationAdmin.AdminAdded(admin);
        }

        // Process removals
        for (uint256 i = 0; i < adminsToRemove.length; ++i) {
            address admin = adminsToRemove[i];

            // Case: Admin does not exist
            if (!adminLayout.isAdmin[admin]) {
                revert IOrganizationAdmin.AdminDoesNotExist(admin);
            }

            adminLayout.isAdmin[admin] = false;
            --adminCount;
            emit IOrganizationAdmin.AdminRemoved(admin);
        }

        // Case: change would result in no admins
        if (adminCount == 0) {
            revert IOrganizationAdmin.InvalidAdminConfig();
        }

        // Case: invalid admin voting threshold
        if (newVotingThreshold == 0 || newVotingThreshold > adminCount) {
            revert IOrganizationAdmin.InvalidAdminVotingThreshold(newVotingThreshold, adminCount);
        }

        // Write the final admin count to storage once
        adminLayout.adminCount = adminCount;

        // Case: New voting threshold
        if (adminLayout.votingThreshold != newVotingThreshold) {
            uint256 previousThreshold = adminLayout.votingThreshold;
            adminLayout.votingThreshold = newVotingThreshold;
            emit IOrganizationAdmin.VotingThresholdUpdated(previousThreshold, newVotingThreshold);
        }
    }

    /**
     * @dev Checks if an address is an admin of the organization
     * @param adminAddress The address to check
     * @return True if the address is an admin, false otherwise
     */
    function isAdmin(address adminAddress) internal view returns (bool) {
        return LibOrganizationAdminStorage.layout().isAdmin[adminAddress];
    }

    /**
     * @dev Returns the total number of admins in the organization
     * @return The admin count
     */
    function getAdminCount() internal view returns (uint256) {
        return LibOrganizationAdminStorage.layout().adminCount;
    }

    /**
     * @dev Returns the current voting threshold for admin operations
     * @return The voting threshold
     */
    function getVotingThreshold() internal view returns (uint256) {
        return LibOrganizationAdminStorage.layout().votingThreshold;
    }

    /**
     * @dev Checks if there are enough valid signatures from admins.
     *      Supports both EOA (ECDSA) and ERC-1271 (smart contract) signatures.
     *      Iterates using while(offset < signatures.length) — no proof arrays needed.
     * @param signatures The signatures to verify (variable length, hybrid format)
     * @param operationHash The hash of the admin operation
     * @return True if there are enough valid signatures, false otherwise
     */
    function _areAdminSignaturesValid(bytes memory signatures, bytes32 operationHash) internal view returns (bool) {
        // Case: No signatures provided
        if (signatures.length == 0) {
            return false;
        }

        LibOrganizationAdminStorage.Layout storage adminLayout = LibOrganizationAdminStorage.layout();
        uint256 requiredSignatures = adminLayout.votingThreshold;

        uint256 validSignatures = 0;
        address lastSigner = address(0);
        uint256 offset = 0;

        // Iterate over all signatures in the packed bytes
        while (offset < signatures.length) {
            // Recover signer at current offset (handles both EOA and ERC-1271)
            // Reverts if signature is malformed
            (address signer, uint256 nextOffset) =
                SignatureUtils.recoverSignerAtOffsetOrRevert(signatures, offset, operationHash);

            offset = nextOffset;

            // Case: Signer address is not in ascending order or has duplicates
            if (signer <= lastSigner) {
                revert IOrganizationAdmin.DuplicateOrOutOfOrderAdminSigner(signer, lastSigner);
            }
            lastSigner = signer;

            // Case: Signer is not an admin — revert (strict validation for admin operations)
            if (!adminLayout.isAdmin[signer]) {
                revert IOrganizationAdmin.SignerIsNotAdmin(signer);
            }

            ++validSignatures;

            // Case: Early exit if we have enough valid signatures
            if (validSignatures >= requiredSignatures) {
                return true;
            }
        }

        return false;
    }

    /**
     * @dev Creates a hash of the admin operation for signature verification using EIP-712 typed data
     * @param operationType The type of operation being performed
     * @param operationData The ABI-encoded data of the operation
     * @param salt The user-provided salt for nonce computation
     * @param expirationTimestamp The timestamp after which the signatures are no longer valid
     * @param isApproval Whether this is an approval (true) or rejection (false) signature
     * @return The EIP-712 typed data hash of the admin operation for signature verification
     */
    function _getAdminOperationHash(
        OperationType operationType,
        bytes memory operationData,
        uint256 salt,
        uint256 expirationTimestamp,
        bool isApproval
    ) internal view returns (bytes32) {
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

        // Return EIP-712 typed data hash for signature verification
        return LibOrganizationEIP712.computeTypedDataHash(structHash);
    }
}
