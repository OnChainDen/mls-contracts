// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {AdminAuthParams, AllAdminsInOrgProofs} from "types/AdminTypes.sol";

/**
 * @title IOrganizationMembers
 * @notice Interface for member-related operations in Organization contracts
 * @dev Maps to LibOrganizationMembers library functionality
 * @author Den Technologies Inc
 */
interface IOrganizationMembers {
    // ═══════════════════════════════════════════════════════════════════════════
    // Events
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Emitted when the members merkle root is updated
     * @param newRoot The new merkle root
     * @param ipfsCid The IPFS CID where full member data is stored for disaster recovery
     */
    event MembersUpdated(bytes32 indexed newRoot, string ipfsCid);

    // ═══════════════════════════════════════════════════════════════════════════
    // Functions
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Updates the global members merkle root
     * @dev This is the only way to set members. All member data is stored off-chain (IPFS).
     *      Validates that all admins remain members in the new tree to prevent bricking.
     * @param newMembersRoot The new merkle root containing all members
     * @param ipfsCid The IPFS CID where full member data is stored for disaster recovery
     * @param authParams The authorization parameters (salt, expiration, signatures, and admin proofs)
     * @param allAdminsInOrgProofs Proofs that all admins are in the new members tree
     */
    function setMembers(
        bytes32 newMembersRoot,
        string calldata ipfsCid,
        AdminAuthParams calldata authParams,
        AllAdminsInOrgProofs calldata allAdminsInOrgProofs
    ) external;

    /**
     * @notice Returns the current members merkle root
     * @return The members merkle root
     */
    function membersRoot() external view returns (bytes32);

    /**
     * @notice Verifies that an address is a member of the organization
     * @param memberAddress The address to verify
     * @param proof The merkle proof for the address
     * @return True if the address is a verified member, false otherwise
     */
    function isMemberInOrg(address memberAddress, bytes32[] calldata proof) external view returns (bool);
}
