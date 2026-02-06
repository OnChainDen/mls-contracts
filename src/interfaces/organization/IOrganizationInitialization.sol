// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {InitializationParams} from "types/CommonTypes.sol";

/**
 * @title IOrganizationInitialization
 * @notice Interface for initialization-related operations in Organization contracts
 * @dev Maps to LibOrganizationInitialization library functionality
 * @author Den Technologies Inc
 */
interface IOrganizationInitialization {
    // ═══════════════════════════════════════════════════════════════════════════
    // Events
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Emitted when organization is successfully initialized
     * @param adminsRoot The merkle root of admin addresses
     * @param adminCount The number of admins
     * @param votingThreshold The voting threshold for admin operations
     * @param adminAddresses The admin addresses (in ascending order)
     * @param guardian The guardian address set during initialization
     * @param adminOperationTimelockDurationSeconds The organization-wide admin operation timelock duration in seconds
     * @param membersRoot The initial members Merkle root
     * @param groupsRoot The initial groups Merkle root
     * @param membersIpfsCid The IPFS CID for members data
     * @param groupsIpfsCid The IPFS CID for groups data
     * @param transactionAndERC1271RecoveryAddress The tx/signature recovery address (zero if deferred)
     * @param txRecoveryTimelockDurationSeconds The tx/ERC1271 recovery timelock duration in seconds
     * @param guardianRecoveryAddress The guardian recovery address (zero if deferred)
     * @param guardianRecoveryTimelockDurationSeconds The guardian recovery timelock duration in seconds
     */
    event OrganizationInitialized(
        bytes32 adminsRoot,
        uint256 adminCount,
        uint256 votingThreshold,
        address[] adminAddresses,
        address guardian,
        uint256 adminOperationTimelockDurationSeconds,
        bytes32 membersRoot,
        bytes32 groupsRoot,
        string membersIpfsCid,
        string groupsIpfsCid,
        address transactionAndERC1271RecoveryAddress,
        uint256 txRecoveryTimelockDurationSeconds,
        address guardianRecoveryAddress,
        uint256 guardianRecoveryTimelockDurationSeconds
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // Errors
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Error thrown when caller is not the authorized deployer
     */
    error UnauthorizedDeployer();

    /**
     * @notice Error thrown when the organization is already initialized
     */
    error AlreadyInitialized();

    /**
     * @notice Error thrown when the members root is invalid
     */
    error InvalidMembersRoot();

    // ═══════════════════════════════════════════════════════════════════════════
    // Functions
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize the organization implementation with Merkle-based members and groups
     * @param params The initialization parameters struct containing all required configuration
     */
    function initialize(InitializationParams calldata params) external;

    /**
     * @notice Returns the address that deployed this organization
     * @return The deployer address
     */
    function getDeployerAddress() external view returns (address);

    /**
     * @notice Checks if the organization has been initialized
     * @return True if initialized, false otherwise
     */
    function isInitialized() external view returns (bool);
}
