// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @notice Enum to specify whether admin permission is granted to an individual member or a group
 */
enum AdminType {
    Member,
    Group
}

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
    UpgradeAccount,
    // Account transaction operations
    AccountTransaction,
    AccountTransactionRejection
}

/**
 * @title IOrganizationSignatureValidator
 * @notice Interface for validating ERC-1271 signatures on behalf of accounts
 */
interface IOrganizationSignatureValidator {
    /**
     * @notice Validates an ERC-1271 signature for a given account
     * @param account The account address on behalf of which the signature is being validated
     * @param hash The hash that was signed
     * @param signature The signature to validate (encoded with policyId, approver signatures, guardian signature)
     * @return magicValue 0x1626ba7e if valid, 0xffffffff otherwise
     */
    function isValidSignatureForAccount(
        address account,
        bytes32 hash,
        bytes memory signature
    )
        external
        view
        returns (bytes4 magicValue);
}
