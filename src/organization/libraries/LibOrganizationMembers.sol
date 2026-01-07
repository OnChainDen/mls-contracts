// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { LibOrganizationMembersStorage } from "./storage/LibOrganizationMembersStorage.sol";
import { LibOrganizationAdminStorage } from "./storage/LibOrganizationAdminStorage.sol";
import { LibOrganizationAdmin } from "./LibOrganizationAdmin.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title Lib Organization Members
 * @notice Library for merkle-based member operations for Organization contracts
 * @dev Members are stored in a merkle tree. Only the root is stored on-chain.
 *      Full member data is stored off-chain (IPFS) and provided via calldata at validation time.
 *      This approach drastically reduces gas costs for member management (1 SSTORE)
 *      while keeping verification costs reasonable (O(log n) hash operations).
 * @author Den Technologies Inc
 */
library LibOrganizationMembers {
    /**
     * @notice Emitted when the members merkle root is updated
     * @param newRoot The new merkle root
     * @param ipfsCid The IPFS CID where full member data is stored for disaster recovery
     */
    event MembersUpdated(bytes32 indexed newRoot, string ipfsCid);

    /**
     * @notice Emitted when membership verification fails
     * @param memberAddress The address that failed verification
     */
    error MemberVerificationFailed(address memberAddress);

    // ================================
    // MERKLE HELPERS
    // ================================

    /**
     * @notice Computes the merkle leaf for a member address
     * @dev Uses double hashing (hash of hash) for security against second preimage attacks
     * @param memberAddress The member's address
     * @return The computed merkle leaf
     */
    function computeMemberLeaf(address memberAddress) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(memberAddress))));
    }

    // ================================
    // MEMBERSHIP VERIFICATION
    // ================================

    /**
     * @notice Checks if an address is in a member tree given an explicit root
     * @dev Used to verify against potentially different roots (current vs new)
     * @param memberAddress The address to verify
     * @param membersRoot The merkle root to verify against
     * @param proof The merkle proof
     * @return True if the address is in the member tree, false otherwise
     */
    function isMemberInTree(
        address memberAddress,
        bytes32 membersRoot,
        bytes32[] memory proof
    )
        internal
        pure
        returns (bool)
    {
        if (membersRoot == bytes32(0)) return false;
        bytes32 leaf = computeMemberLeaf(memberAddress);
        return MerkleProof.verify(proof, membersRoot, leaf);
    }

    /**
     * @notice Verifies that an address is a member of the organization
     * @param memberAddress The address to verify
     * @param proof The merkle proof for the address
     * @return True if the address is a verified member, false otherwise
     */
    function isMemberInOrg(address memberAddress, bytes32[] memory proof) internal view returns (bool) {
        bytes32 root = LibOrganizationMembersStorage.layout().membersRoot;
        return isMemberInTree(memberAddress, root, proof);
    }

    /**
     * @notice Verifies membership and reverts if verification fails
     * @param memberAddress The address to verify
     * @param proof The merkle proof for the address
     */
    function verifyMemberInOrgOrRevert(address memberAddress, bytes32[] memory proof) internal view {
        if (!isMemberInOrg(memberAddress, proof)) {
            revert MemberVerificationFailed(memberAddress);
        }
    }

    // ================================
    // MODIFY MEMBERS
    // ================================

    /**
     * @notice Updates the global members merkle root
     * @dev This is the only way to modify members. All member data is stored off-chain (IPFS).
     *      Validates that ALL admins remain members in the new tree to prevent bricking.
     *      Emits MembersUpdated event with the IPFS CID for disaster recovery.
     * @param newMembersRoot The new merkle root containing all members
     * @param ipfsCid The IPFS CID where full member data is stored
     * @param adminValidation The validation data to verify all admins are in the new members tree
     */
    function modifyMembers(
        bytes32 newMembersRoot,
        string calldata ipfsCid,
        LibOrganizationAdmin.AdminMembershipValidation memory adminValidation
    )
        internal
    {
        // Get current admin configuration
        LibOrganizationAdminStorage.AdminPermission memory admin = LibOrganizationAdminStorage.layout().adminPermission;

        // Validate that ALL admins are still members in the NEW members tree
        // This prevents accidentally bricking the organization by removing admins from membership
        LibOrganizationAdmin.validateAllAdminsAreMembersOrRevert(
            adminValidation, admin.adminsRoot, newMembersRoot, admin.adminCount
        );

        // Update the members root
        LibOrganizationMembersStorage.layout().membersRoot = newMembersRoot;
        emit MembersUpdated(newMembersRoot, ipfsCid);
    }

    // ================================
    // GETTERS
    // ================================

    /**
     * @notice Returns the current members merkle root
     * @return The members merkle root
     */
    function getMembersRoot() internal view returns (bytes32) {
        return LibOrganizationMembersStorage.layout().membersRoot;
    }
}
