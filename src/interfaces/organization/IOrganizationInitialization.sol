// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {InitializationParams} from "types/CommonTypes.sol";

/**
 * @title IOrganizationInitialization
 * @notice Interface for initialization-related operations in Organization contracts
 * @dev Maps to LibOrganizationInitialization library functionality.
 *      Members, admins, and groups are stored in onchain mappings.
 * @author Den Technologies Inc
 */
interface IOrganizationInitialization {
    // ═══════════════════════════════════════════════════════════════════════════
    // Events
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Emitted when organization is successfully initialized
     * @param adminAddresses The admin addresses set during initialization
     * @param votingThreshold The voting threshold for admin operations
     * @param guardian The guardian address set during initialization
     * @param accountImplementation The account implementation address set during initialization
     * @param adminOperationTimelockDurationSeconds The organization-wide admin operation timelock duration in seconds
     * @param transactionAndERC1271RecoveryAddress The tx/signature recovery address (zero if deferred)
     * @param txRecoveryTimelockDurationSeconds The tx/ERC1271 recovery timelock duration in seconds
     * @param guardianRecoveryAddress The guardian recovery address (zero if deferred)
     * @param guardianRecoveryTimelockDurationSeconds The guardian recovery timelock duration in seconds
     */
    event OrganizationInitialized(
        address[] adminAddresses,
        uint256 votingThreshold,
        address guardian,
        address accountImplementation,
        uint256 adminOperationTimelockDurationSeconds,
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
     * @notice Error thrown when no members are provided during initialization
     */
    error NoMembersProvided();

    // ═══════════════════════════════════════════════════════════════════════════
    // Functions
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize the organization with mapping-based members, admins, and groups
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
