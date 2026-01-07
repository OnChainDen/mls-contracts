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
 * @param adminTreeProofs Merkle proofs that each admin address is in adminsRoot
 * @param adminMemberProofs Merkle proofs that each admin address is in membersRoot
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
    bytes32[][] adminTreeProofs;
    bytes32[][] adminMemberProofs;
    address guardian;
    bytes32 membersRoot;
    bytes32 groupsRoot;
    string membersIpfsCid;
    string groupsIpfsCid;
}

/**
 * @title IOrganizationSignatureValidator
 * @notice Interface for validating ERC-1271 signatures on behalf of accounts
 */
interface IOrganizationSignatureValidator {
    /**
     * @notice Validates an ERC-1271 signature for a given account
     * @dev Note: Time-based policy limits are NOT supported for ERC-1271 signatures because the standard
     *      requires isValidSignature to be a view function (cannot modify storage to track usage).
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
