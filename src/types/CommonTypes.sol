// SPDX-License-Identifier: MIT
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
    UpdateGuardian,
    Upgrade,
    DeployAccount,
    UpgradeAccount,
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
 * @param guardianTimelockDuration The duration in seconds for normal guardian update timelocks
 * @param membersRoot The initial Merkle root for all members
 * @param groupsRoot The initial Merkle root for all groups
 * @param membersIpfsCid The IPFS CID where full members data is stored
 * @param groupsIpfsCid The IPFS CID where full groups data is stored
 * @param isRecoverySupportedForTransactionsAndERC1271 Whether recovery is supported for tx/signatures
 * @param transactionAndERC1271RecoveryAddress The privileged address for tx/signature recovery (must be set if
 * supported)
 * @param txRecoveryTimelockDuration The duration in seconds for tx/ERC1271 recovery enable timelocks
 * @param guardianRecoveryAddress The privileged address for guardian recovery (must always be set)
 * @param guardianRecoveryTimelockDuration The duration in seconds for guardian recovery timelocks
 */
struct InitializationParams {
    bytes32 adminsRoot;
    uint256 adminCount;
    uint256 votingThreshold;
    address[] adminAddresses;
    bytes32[][] adminInAdminTreeProofs;
    bytes32[][] adminInMembersTreeProofs;
    address guardian;
    uint256 guardianTimelockDuration;
    bytes32 membersRoot;
    bytes32 groupsRoot;
    string membersIpfsCid;
    string groupsIpfsCid;
    // Recovery configuration
    bool isRecoverySupportedForTransactionsAndERC1271;
    address transactionAndERC1271RecoveryAddress;
    uint256 txRecoveryTimelockDuration;
    address guardianRecoveryAddress;
    uint256 guardianRecoveryTimelockDuration;
}
