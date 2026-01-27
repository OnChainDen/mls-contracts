// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

/**
 * @title Admin Types
 * @notice Data structures for admin-related operations in Organization contracts
 * @dev Admin membership is verified via Merkle proofs.
 *      Admins are stored as a Merkle tree of member addresses.
 * @author Den Technologies Inc
 */

/**
 * @dev Proofs that ALL admins are members of the organization (in both admin tree and members tree).
 *      Used by setMembers, setAdmins, and initialize to prevent bricking.
 *      Contains proofs for every admin in the organization, not just signers.
 * @param adminAddresses All admin addresses (must match adminCount, in ascending order)
 * @param adminInOrgAdminTreeProofs Merkle proofs that each address is in adminsRoot
 * @param adminInOrgMembersTreeProofs Merkle proofs that each address is in membersRoot
 */
struct AllAdminsInOrgProofs {
    address[] adminAddresses;
    bytes32[][] adminInOrgAdminTreeProofs;
    bytes32[][] adminInOrgMembersTreeProofs;
}

/**
 * @dev Proofs that the SIGNING admins are members of the organization (in both admin tree and members tree).
 *      Contains per-signer proofs for admin tree and organization membership.
 *      Only contains proofs for admins who signed the operation, not all admins.
 * @param adminInOrgAdminTreeProofs Per-signer merkle proofs that each signer is in the adminsRoot
 * @param adminInOrgMembersTreeProofs Per-signer merkle proofs that each signer is in the organization's membersRoot
 */
struct SigningAdminsInOrgProofs {
    bytes32[][] adminInOrgAdminTreeProofs;
    bytes32[][] adminInOrgMembersTreeProofs;
}

/**
 * @dev Parameters for authorizing admin operations.
 *      Groups common authorization parameters to reduce function parameter count.
 * @param salt A user-provided salt for nonce computation
 * @param expirationTimestamp The timestamp after which the signatures are no longer valid
 * @param signatures The signatures from admin(s) authorizing this operation
 * @param signingAdminsInOrgProofs Proofs that the signing admins are in the organization
 */
struct AdminAuthParams {
    uint256 salt;
    uint256 expirationTimestamp;
    bytes signatures;
    SigningAdminsInOrgProofs signingAdminsInOrgProofs;
}

/**
 * @dev Structure to define admin permissions.
 *      Admins are stored as a Merkle tree of member addresses.
 * @param adminsRoot Merkle root of admin member addresses
 * @param adminCount Number of admins in the tree (for completeness validation)
 * @param votingThreshold Number of signatures required for admin operations
 */
struct AdminConfig {
    bytes32 adminsRoot;
    uint256 adminCount;
    uint256 votingThreshold;
}
