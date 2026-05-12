// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

/**
 * @title Common Types
 * @notice Shared data structures and enums used across Organization contracts
 * @author Den Technologies Inc
 */

/**
 * @notice Enum to specify the contract type for implementation whitelisting
 */
enum ContractType {
    Account,
    Organization
}

/**
 * @notice Enum to specify the type of operation being performed
 * @dev Used for nonce computation and signature validation across all organization operations
 */
enum OperationType {
    // Admin/Organization operations
    ModifyAdmins,
    ModifyGroups,
    ModifyMembers,
    ModifyPolicies,
    InitiateUpdateGuardian,
    FinalizeUpdateGuardian,
    CancelUpdateGuardian,
    Upgrade,
    DeployAccount,
    UpgradeAccount,
    InitiateInitializeGuardianRecovery,
    FinalizeInitializeGuardianRecovery,
    CancelInitializeGuardianRecovery,
    InitiateInitializeTransactionRecovery,
    FinalizeInitializeTransactionRecovery,
    CancelInitializeTransactionRecovery,
    // Account transaction operations
    AccountTransaction
}

/**
 * @notice Enum to specify the type of group modification being performed
 */
enum GroupModificationType {
    Create, // Create a new group (group must not already exist)
    Update, // Update an existing group's membership (group must already exist)
    Delete // Delete an existing group (group must already exist, member arrays must be empty)
}

/**
 * @notice Represents a single group modification operation
 * @dev Create: creates a new group (reverts if already exists, was deleted, or membersToRemove is non-empty).
 *      Update: modifies an existing group's membership (reverts if group does not exist).
 *      Delete: deletes an existing group (reverts if group does not exist or member arrays are non-empty).
 *      Group IDs are not reusable after deletion -- recreating a deleted group ID will revert.
 * @param groupId The unique identifier for the group
 * @param modificationType The type of modification to perform (Create, Update, or Delete)
 * @param membersToAdd Addresses to add to the group (no-op on duplicates; must be empty for Delete)
 * @param membersToRemove Addresses to remove from the group (reverts if not in group; must be empty for Create and
 * Delete)
 */
struct GroupModification {
    uint256 groupId;
    GroupModificationType modificationType;
    address[] membersToAdd;
    address[] membersToRemove;
}

/**
 * @notice Parameters for organization initialization
 * @dev Packed into a struct to avoid stack too deep errors.
 *      Members and admins are provided as address arrays and stored directly in mappings.
 *      Groups are provided as GroupModification structs for batch creation.
 * @param members Initial member addresses (must have at least one)
 * @param admins Initial admin addresses (must all be members)
 * @param votingThreshold Number of admin signatures required for admin operations
 * @param groups Initial group configurations
 * @param guardian Guardian address for the organization
 * @param accountImplementation Initial account implementation address (must be whitelisted)
 * @param adminOperationTimelockDurationSeconds The organization-wide admin operation timelock duration in seconds
 * @param transactionAndERC1271RecoveryAddress The privileged address for tx/signature recovery (zero to defer setup)
 * @param txRecoveryTimelockDurationSeconds The duration in seconds for tx/ERC1271 recovery enable timelocks
 * @param guardianRecoveryAddress The privileged address for guardian recovery (zero to defer setup)
 * @param guardianRecoveryTimelockDurationSeconds The duration in seconds for guardian recovery timelocks
 */
struct InitializationParams {
    address[] members;
    address[] admins;
    uint256 votingThreshold;
    GroupModification[] groups;
    address guardian;
    address accountImplementation;
    uint256 adminOperationTimelockDurationSeconds;
    // Recovery configuration (zero addresses defer setup to post-deployment)
    address transactionAndERC1271RecoveryAddress;
    uint256 txRecoveryTimelockDurationSeconds;
    address guardianRecoveryAddress;
    uint256 guardianRecoveryTimelockDurationSeconds;
}
