// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MerkleUtils} from "../../libraries/MerkleUtils.sol";
import {LibOrganizationAdmin} from "./LibOrganizationAdmin.sol";
import {LibOrganizationAdminStorage} from "./storage/LibOrganizationAdminStorage.sol";
import {LibOrganizationMembersStorage} from "./storage/LibOrganizationMembersStorage.sol";

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title Lib Organization Members
 * @dev Library for merkle-based member operations for Organization contracts
 * @dev Members are stored in a merkle tree. Only the root is stored on-chain.
 *      Full member data is stored off-chain (IPFS) and provided via calldata at validation time.
 *      This approach drastically reduces gas costs for member management (1 SSTORE)
 *      while keeping verification costs reasonable (O(log n) hash operations).
 * @author Den Technologies Inc
 */
library LibOrganizationMembers {
    /**
     * @dev Emitted when the members merkle root is updated
     * @param newRoot The new merkle root
     * @param ipfsCid The IPFS CID where full member data is stored for disaster recovery
     */
    event MembersUpdated(bytes32 indexed newRoot, string ipfsCid);

    /**
     * @dev Thrown when membership verification fails
     * @param memberAddress The address that failed verification
     */
    error MemberVerificationFailed(address memberAddress);

    /**
     * @dev Updates the global members merkle root
     * @dev This is the only way to set members. All member data is stored off-chain (IPFS).
     *      Validates that ALL admins remain members in the new tree to prevent bricking.
     *      Emits MembersUpdated event with the IPFS CID for disaster recovery.
     * @param newMembersRoot The new merkle root containing all members
     * @param ipfsCid The IPFS CID where full member data is stored
     * @param allAdminsInOrgProofs Proofs that all admins are in the new members tree
     */
    function setMembers(
        bytes32 newMembersRoot,
        string calldata ipfsCid,
        LibOrganizationAdmin.AllAdminsInOrgProofs memory allAdminsInOrgProofs
    ) internal {
        // Get current admin configuration
        LibOrganizationAdminStorage.AdminPermission memory admin = LibOrganizationAdminStorage.layout().adminPermission;

        // Validate that ALL admins are still members in the NEW members tree
        // This prevents accidentally bricking the organization by removing admins from membership
        LibOrganizationAdmin.validateAllAdminsAreMembersOrRevert(
            allAdminsInOrgProofs, admin.adminsRoot, newMembersRoot, admin.adminCount
        );

        // Update the members root
        LibOrganizationMembersStorage.layout().membersRoot = newMembersRoot;
        emit MembersUpdated(newMembersRoot, ipfsCid);
    }

    /**
     * @dev Verifies that an address is a member of the organization
     * @param memberAddress The address to verify
     * @param proof The merkle proof for the address
     * @return True if the address is a verified member, false otherwise
     */
    function isMemberInOrg(address memberAddress, bytes32[] memory proof) internal view returns (bool) {
        bytes32 root = LibOrganizationMembersStorage.layout().membersRoot;
        return isMemberInTree(memberAddress, root, proof);
    }

    /**
     * @dev Returns the current members merkle root
     * @return The members merkle root
     */
    function getMembersRoot() internal view returns (bytes32) {
        return LibOrganizationMembersStorage.layout().membersRoot;
    }

    /**
     * @dev Checks if an address is in a member tree given an explicit root
     * @dev Used to verify against potentially different roots (current vs new)
     * @param memberAddress The address to verify
     * @param membersRoot The merkle root to verify against
     * @param proof The merkle proof
     * @return True if the address is in the member tree, false otherwise
     */
    function isMemberInTree(address memberAddress, bytes32 membersRoot, bytes32[] memory proof)
        internal
        pure
        returns (bool)
    {
        if (membersRoot == bytes32(0)) return false;
        bytes32 leaf = MerkleUtils.computeAddressLeaf(memberAddress);
        return MerkleProof.verify(proof, membersRoot, leaf);
    }
}
