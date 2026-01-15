// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

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
 * @param membersRoot The initial Merkle root for all members
 * @param groupsRoot The initial Merkle root for all groups
 * @param membersIpfsCid The IPFS CID where full members data is stored
 * @param groupsIpfsCid The IPFS CID where full groups data is stored
 */
struct InitializationParams {
    bytes32 adminsRoot;
    uint256 adminCount;
    uint256 votingThreshold;
    address[] adminAddresses;
    bytes32[][] adminInAdminTreeProofs;
    bytes32[][] adminInMembersTreeProofs;
    address guardian;
    bytes32 membersRoot;
    bytes32 groupsRoot;
    string membersIpfsCid;
    string groupsIpfsCid;
}
