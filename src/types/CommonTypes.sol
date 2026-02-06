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
    Upgrade,
    DeployAccount,
    UpgradeAccount,
    InitiateInitializeGuardianRecovery,
    FinalizeInitializeGuardianRecovery,
    InitiateInitializeTransactionRecovery,
    FinalizeInitializeTransactionRecovery,
    // Account transaction operations
    AccountTransaction,
    AccountTransactionRejection
}

/**
 * @notice Parameters for organization initialization
 * @dev Packed into a struct to avoid stack too deep errors
 * @param adminsRoot Merkle root of admin member addresses
 * @param adminCount Number of admins in the admin tree (for completeness validation)
 * @param votingThreshold Number of admin signatures required
 * @param adminAddresses All admin addresses (must match adminCount, in ascending order)
 * @param adminInAdminTreeProofs Merkle proofs that each admin address is in adminsRoot
 * @param adminInMembersTreeProofs Merkle proofs that each admin address is in membersRoot
 * @param guardian Guardian address for the organization
 * @param secureTimelockDurationSeconds The organization-wide secure timelock duration in seconds for sensitive
 * operations
 * @param membersRoot The initial Merkle root for all members
 * @param groupsRoot The initial Merkle root for all groups
 * @param membersIpfsCid The IPFS CID where full members data is stored
 * @param groupsIpfsCid The IPFS CID where full groups data is stored
 * @param transactionAndERC1271RecoveryAddress The privileged address for tx/signature recovery (zero to defer setup)
 * @param txRecoveryTimelockDurationSeconds The duration in seconds for tx/ERC1271 recovery enable timelocks
 * @param guardianRecoveryAddress The privileged address for guardian recovery (zero to defer setup)
 * @param guardianRecoveryTimelockDurationSeconds The duration in seconds for guardian recovery timelocks
 */
struct InitializationParams {
    bytes32 adminsRoot;
    uint256 adminCount;
    uint256 votingThreshold;
    address[] adminAddresses;
    bytes32[][] adminInAdminTreeProofs;
    bytes32[][] adminInMembersTreeProofs;
    address guardian;
    uint256 secureTimelockDurationSeconds;
    bytes32 membersRoot;
    bytes32 groupsRoot;
    string membersIpfsCid;
    string groupsIpfsCid;
    // Recovery configuration (zero addresses defer setup to post-deployment)
    address transactionAndERC1271RecoveryAddress;
    uint256 txRecoveryTimelockDurationSeconds;
    address guardianRecoveryAddress;
    uint256 guardianRecoveryTimelockDurationSeconds;
}
