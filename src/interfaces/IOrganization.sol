// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @notice Enum to specify the type of operation being performed
 * @dev Used for nonce computation and signature validation across all organization operations
 */
enum OperationType {
    // Admin/Organization operations
    UpdateAdmin,
    CreateGroup,
    ModifyGroup,
    RemoveGroup,
    AddMembers,
    ModifyMember,
    RemoveMembers,
    ModifyPolicies,
    UpdateGuardian,
    ModifyWhitelist,
    Upgrade,
    DeployAccount,
    // Account transaction operations
    AccountTransaction,
    AccountTransactionRejection
}
