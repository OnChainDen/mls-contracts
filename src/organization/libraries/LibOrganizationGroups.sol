// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IOrganizationGroups} from "../../interfaces/organization/IOrganizationGroups.sol";
import {MerkleUtils} from "../../libraries/MerkleUtils.sol";
import {GroupData} from "../../types/PolicyTypes.sol";
import {LibOrganizationGroupsStorage} from "./storage/LibOrganizationGroupsStorage.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title Lib Organization Groups
 * @dev Library for merkle-based group operations for Organization contracts
 * @dev Groups are stored in a nested merkle tree. Only the root is stored on-chain.
 *      Full group data is stored off-chain (IPFS) and provided via calldata at validation time.
 *      Each group leaf is hash(hash(groupId, groupMembersRoot)) where groupMembersRoot is
 *      a separate merkle tree containing the member addresses in that group.
 *      This approach drastically reduces gas costs for group management (1 SSTORE)
 *      while keeping verification costs reasonable (O(log n) hash operations per verification).
 * @author Den Technologies Inc
 */
library LibOrganizationGroups {
    /**
     * @dev Updates the global groups merkle root
     * @dev This is the only way to set groups. All group data is stored off-chain (IPFS).
     *      Emits GroupsUpdated event with the IPFS CID for disaster recovery.
     * @param newGroupsRoot The new merkle root containing all groups
     * @param ipfsCid The IPFS CID where full group data is stored
     */
    function setGroups(bytes32 newGroupsRoot, string calldata ipfsCid) internal {
        LibOrganizationGroupsStorage.layout().groupsRoot = newGroupsRoot;
        emit IOrganizationGroups.GroupsUpdated(newGroupsRoot, ipfsCid);
    }

    /**
     * @dev Verifies that a group exists in the organization
     * @param groupData The group data containing groupId and groupMembersRoot
     * @param groupInOrgGroupsTreeProof The merkle proof for the group
     * @return True if the group exists, false otherwise
     */
    function isGroupInOrg(GroupData memory groupData, bytes32[] memory groupInOrgGroupsTreeProof)
        internal
        view
        returns (bool)
    {
        bytes32 root = LibOrganizationGroupsStorage.layout().groupsRoot;
        return isGroupInTree(groupData, root, groupInOrgGroupsTreeProof);
    }

    /**
     * @dev Verifies complete group membership (group exists AND member is in group)
     * @param memberAddress The address to verify
     * @param groupData The group data containing groupId and groupMembersRoot
     * @param groupInOrgGroupsTreeProof The merkle proof that the group exists
     * @param memberInGroupProof The merkle proof that the member is in the group
     * @return True if both verifications pass, false otherwise
     */
    function isMemberInGroupAndGroupInOrg(
        address memberAddress,
        GroupData memory groupData,
        bytes32[] memory groupInOrgGroupsTreeProof,
        bytes32[] memory memberInGroupProof
    ) internal view returns (bool) {
        // First verify the group exists
        if (!isGroupInOrg(groupData, groupInOrgGroupsTreeProof)) {
            return false;
        }

        // Then verify the member is in the group
        return isMemberInGroup(memberAddress, groupData.groupMembersRoot, memberInGroupProof);
    }

    /**
     * @dev Returns the current groups merkle root
     * @return The groups merkle root
     */
    function getGroupsRoot() internal view returns (bytes32) {
        return LibOrganizationGroupsStorage.layout().groupsRoot;
    }

    /**
     * @dev Checks if a group exists in a groups tree given an explicit root
     * @dev Used to verify against potentially different roots or to avoid storage reads in loops
     * @param groupData The group data containing groupId and groupMembersRoot
     * @param groupsRoot The merkle root to verify against
     * @param groupInOrgGroupsTreeProof The merkle proof for the group
     * @return True if the group exists in the tree, false otherwise
     */
    function isGroupInTree(GroupData memory groupData, bytes32 groupsRoot, bytes32[] memory groupInOrgGroupsTreeProof)
        internal
        pure
        returns (bool)
    {
        // Empty root means no groups (organization not initialized or all groups removed)
        if (groupsRoot == bytes32(0)) return false;

        bytes32 leaf = _computeGroupLeaf(groupData.groupId, groupData.groupMembersRoot);
        return MerkleProof.verify(groupInOrgGroupsTreeProof, groupsRoot, leaf);
    }

    /**
     * @dev Verifies that a member is in a specific group
     * @dev Verifies against the group's internal members merkle tree (groupMembersRoot)
     * @param memberAddress The address to verify
     * @param groupMembersRoot The merkle root of the group's members tree
     * @param memberInGroupProof The merkle proof that the member is in the group
     * @return True if the member is in the group, false otherwise
     */
    function isMemberInGroup(address memberAddress, bytes32 groupMembersRoot, bytes32[] memory memberInGroupProof)
        internal
        pure
        returns (bool)
    {
        // Empty root means no members in group
        if (groupMembersRoot == bytes32(0)) return false;

        bytes32 leaf = MerkleUtils.computeAddressLeaf(memberAddress);
        return MerkleProof.verify(memberInGroupProof, groupMembersRoot, leaf);
    }

    /**
     * @dev Computes the merkle leaf for a group
     * @dev Uses double hashing (hash of hash) for security against second preimage attacks
     * @param groupId The group's unique identifier
     * @param groupMembersRoot The merkle root of all member addresses in this group
     * @return The computed merkle leaf
     */
    function _computeGroupLeaf(uint256 groupId, bytes32 groupMembersRoot) private pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(groupId, groupMembersRoot))));
    }
}
