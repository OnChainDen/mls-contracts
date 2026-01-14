// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AdminAuthParams, AdminConfig, AllAdminsInOrgProofs} from "../../types/AdminTypes.sol";
import {OperationType} from "../../types/CommonTypes.sol";

/**
 * @title IOrganizationAdmin
 * @notice Interface for admin-related operations in Organization contracts
 * @dev Maps to LibOrganizationAdmin library functionality
 * @author Den Technologies Inc
 */
interface IOrganizationAdmin {
    // ═══════════════════════════════════════════════════════════════════════════
    // Events
    // ═══════════════════════════════════════════════════════════════════════════

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
    event AdminConfigUpdated(
        bytes32 previousAdminsRoot,
        uint256 previousAdminCount,
        uint256 previousVotingThreshold,
        bytes32 newAdminsRoot,
        uint256 newAdminCount,
        uint256 newVotingThreshold,
        address[] newAdminAddresses
    );

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
     * @notice Thrown when an admin operation fails authorization
     * @param reason The reason for the failure
     */
    error AdminAuthorizationFailed(string reason);

    /**
     * @notice Thrown when an admin operation has insufficient signatures
     * @param required The number of required signatures
     * @param provided The number of provided signatures
     */
    error InsufficientAdminSignatures(uint256 required, uint256 provided);

    /**
     * @notice Thrown when an admin operation has an invalid signature
     */
    error InvalidAdminSignature();

    /**
     * @notice Thrown when an admin operation has wrong chain ID
     * @param expected The expected chain ID
     * @param provided The provided chain ID
     */
    error InvalidAdminChainId(uint256 expected, uint256 provided);

    /**
     * @notice Thrown when an admin operation has expired
     * @param expirationTimestamp The expiration timestamp that was exceeded
     * @param currentTimestamp The current block timestamp
     */
    error AdminOperationExpired(uint256 expirationTimestamp, uint256 currentTimestamp);

    /**
     * @notice Thrown when admin count doesn't match expected
     * @param expected The expected admin count
     * @param provided The provided admin count
     */
    error AdminCountMismatch(uint256 expected, uint256 provided);

    /**
     * @notice Thrown when admin addresses are not in ascending order or have duplicates
     * @param address_ The duplicate or out-of-order address
     */
    error DuplicateOrUnorderedAdminAddress(address address_);

    /**
     * @notice Thrown when an admin is not in the admin tree
     * @param admin The address that is not in the admin tree
     */
    error AdminNotInTree(address admin);

    /**
     * @notice Thrown when an admin is not a member of the organization
     * @param admin The address that is not a member
     */
    error AdminNotMember(address admin);

    /**
     * @notice Thrown when admin configuration is invalid
     * @param reason The reason for the invalid configuration
     */
    error InvalidAdminConfiguration(string reason);

    /**
     * @notice Thrown when admin tree proofs length doesn't match signature count
     * @param expected The expected length (signature count)
     * @param actual The actual length of proofs array
     */
    error AdminTreeProofsLengthMismatch(uint256 expected, uint256 actual);

    /**
     * @notice Thrown when members tree proofs length doesn't match signature count
     * @param expected The expected length (signature count)
     * @param actual The actual length of proofs array
     */
    error MembersTreeProofsLengthMismatch(uint256 expected, uint256 actual);

    // ═══════════════════════════════════════════════════════════════════════════
    // Functions
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Sets the admin permissions for the organization
     * @dev Validates that all new admins are current members before updating.
     * @param newAdminsRoot The new merkle root of admin addresses
     * @param newAdminCount The number of admins in the new tree
     * @param newVotingThreshold The new voting threshold
     * @param authParams The authorization parameters (salt, expiration, signatures, and admin proofs)
     * @param newAdminsInOrgProofs Proofs that all new admins are in the organization (admin tree and members tree)
     */
    function setAdmins(
        bytes32 newAdminsRoot,
        uint256 newAdminCount,
        uint256 newVotingThreshold,
        AdminAuthParams calldata authParams,
        AllAdminsInOrgProofs calldata newAdminsInOrgProofs
    ) external;

    /**
     * @notice Rejects an admin operation by burning its nonce
     * @dev This allows admins to explicitly cancel a previously signed operation
     *      by consuming its nonce without executing the operation logic
     * @param operationType The type of admin operation to reject
     * @param operationData The ABI-encoded data of the operation
     * @param authParams The authorization parameters (salt, expiration, signatures, and admin proofs)
     */
    function rejectAdminOperation(
        OperationType operationType,
        bytes calldata operationData,
        AdminAuthParams calldata authParams
    ) external;

    /**
     * @notice Returns the current admin permission settings for the organization
     * @return The admin permission configuration including admins root, count, and voting threshold
     */
    function adminConfig() external view returns (AdminConfig memory);
}
