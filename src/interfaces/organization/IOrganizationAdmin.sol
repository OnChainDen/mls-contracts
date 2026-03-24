// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @title IOrganizationAdmin
 * @notice Interface for admin-related operations in Organization contracts
 * @dev Maps to LibOrganizationAdmin library functionality.
 *      Admins are stored in a mapping for O(1) admin checks.
 * @author Den Technologies Inc
 */
interface IOrganizationAdmin {
    // ═══════════════════════════════════════════════════════════════════════════
    // Events
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Emitted when an admin is added to the organization
     * @param admin The address of the added admin
     */
    event AdminAdded(address indexed admin);

    /**
     * @notice Emitted when an admin is removed from the organization
     * @param admin The address of the removed admin
     */
    event AdminRemoved(address indexed admin);

    /**
     * @notice Emitted when the voting threshold is updated
     * @param previousVotingThreshold The previous voting threshold
     * @param newVotingThreshold The new voting threshold
     */
    // solhint-disable-next-line gas-indexed-events
    event VotingThresholdUpdated(uint256 previousVotingThreshold, uint256 newVotingThreshold);

    /**
     * @notice Emitted when an admin operation is rejected by authorized admins
     * @param operationType The type of admin operation that was rejected
     * @param operationData The encoded operation data
     * @param nonce The nonce that was consumed/burned
     */
    event AdminOperationRejected(OperationType indexed operationType, bytes operationData, uint256 indexed nonce);

    // ═══════════════════════════════════════════════════════════════════════════
    // Errors
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Thrown when an admin operation has insufficient valid signatures to meet threshold
     */
    error InsufficientAdminAuthorization();

    /**
     * @notice Thrown when admin signatures are not in ascending order by signer address or contain duplicates
     * @param signer The signer address that violated ordering
     * @param lastSigner The previous signer address
     */
    error DuplicateOrOutOfOrderAdminSigner(address signer, address lastSigner);

    /**
     * @notice Thrown when an admin operation has expired
     * @param expirationTimestamp The expiration timestamp that was exceeded
     * @param currentTimestamp The current block timestamp
     */
    error AdminOperationExpired(uint256 expirationTimestamp, uint256 currentTimestamp);

    /**
     * @notice Thrown when `rejectAdminOperation` is used for a non-admin operation domain
     * @param operationType The unsupported operation type
     */
    error InvalidAdminOperationType(OperationType operationType);

    /**
     * @notice Thrown when trying to add an admin that already exists
     * @param admin The address that is already an admin
     */
    error AdminAlreadyExists(address admin);

    /**
     * @notice Thrown when trying to remove an admin that does not exist
     * @param admin The address that is not an admin
     */
    error AdminDoesNotExist(address admin);

    /**
     * @notice Thrown when an admin is not a member of the organization
     * @param admin The address that is not a member
     */
    error AdminNotMember(address admin);

    /**
     * @notice Thrown when the voting threshold is invalid (zero or exceeds admin count)
     * @param votingThreshold The invalid voting threshold
     * @param adminCount The current admin count
     */
    error InvalidAdminVotingThreshold(uint256 votingThreshold, uint256 adminCount);

    /**
     * @notice Thrown when admin configuration is invalid (zero count or invalid threshold)
     */
    error InvalidAdminConfig();

    /**
     * @notice Thrown when a signer is not an admin of the organization
     * @param signer The address that is not an admin
     */
    error SignerIsNotAdmin(address signer);

    // ═══════════════════════════════════════════════════════════════════════════
    // Functions
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Adds and/or removes admins and updates the voting threshold
     * @dev All new admins must be current members. Adding a duplicate admin reverts.
     *      Removing a non-existent admin reverts. The voting threshold must always be
     *      explicitly provided as a non-zero value and must be <= adminCount after modifications.
     * @param adminsToAdd Addresses to add as admins
     * @param adminsToRemove Addresses to remove from admins
     * @param newVotingThreshold The new voting threshold (must be non-zero and <= final admin count)
     * @param authParams The authorization parameters (salt, expiration, signatures)
     */
    function modifyAdmins(
        address[] calldata adminsToAdd,
        address[] calldata adminsToRemove,
        uint256 newVotingThreshold,
        AdminAuthParams calldata authParams
    ) external;

    /**
     * @notice Rejects an admin operation by burning its nonce
     * @dev This allows admins to explicitly cancel a previously signed operation
     *      by consuming its nonce without executing the operation logic
     * @param operationType The type of admin operation to reject
     * @param operationData The ABI-encoded data of the operation
     * @param authParams The authorization parameters (salt, expiration, signatures)
     */
    function rejectAdminOperation(
        OperationType operationType,
        bytes calldata operationData,
        AdminAuthParams calldata authParams
    ) external;

    /**
     * @notice Checks if an address is an admin of the organization
     * @param adminAddress The address to check
     * @return True if the address is an admin, false otherwise
     */
    function isAdmin(address adminAddress) external view returns (bool);

    /**
     * @notice Returns the total number of admins in the organization
     * @return The admin count
     */
    function adminCount() external view returns (uint256);

    /**
     * @notice Returns the current voting threshold for admin operations
     * @return The voting threshold
     */
    function votingThreshold() external view returns (uint256);
}
