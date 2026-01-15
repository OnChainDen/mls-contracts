// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AdminAuthParams} from "types/AdminTypes.sol";
import {GroupData} from "types/PolicyTypes.sol";

/**
 * @title IOrganizationGroups
 * @notice Interface for group-related operations in Organization contracts
 * @dev Maps to LibOrganizationGroups library functionality
 * @author Den Technologies Inc
 */
interface IOrganizationGroups {
    /**
     * @notice Emitted when the groups merkle root is updated
     * @param newRoot The new merkle root
     * @param ipfsCid The IPFS CID where full group data is stored for disaster recovery
     */
    event GroupsUpdated(bytes32 indexed newRoot, string ipfsCid);

    /**
     * @notice Updates the global groups merkle root
     * @dev This is the only way to set groups. All group data is stored off-chain (IPFS).
     * @param newGroupsRoot The new merkle root containing all groups
     * @param ipfsCid The IPFS CID where full group data is stored for disaster recovery
     * @param authParams The authorization parameters (salt, expiration, signatures, and admin proofs)
     */
    function setGroups(bytes32 newGroupsRoot, string calldata ipfsCid, AdminAuthParams calldata authParams) external;

    /**
     * @notice Returns the current groups merkle root
     * @return The groups merkle root
     */
    function groupsRoot() external view returns (bytes32);

    /**
     * @notice Verifies that a group exists in the organization
     * @param groupData The group data containing groupId and groupMembersRoot
     * @param groupInOrgGroupsTreeProof The merkle proof for the group
     * @return True if the group exists, false otherwise
     */
    function isGroupInOrg(GroupData calldata groupData, bytes32[] calldata groupInOrgGroupsTreeProof)
        external
        view
        returns (bool);

    /**
     * @notice Verifies complete group membership (group exists AND member is in group)
     * @param memberAddress The address to verify
     * @param groupData The group data containing groupId and groupMembersRoot
     * @param groupInOrgGroupsTreeProof The merkle proof that the group exists
     * @param memberInGroupProof The merkle proof that the member is in the group
     * @return True if both verifications pass, false otherwise
     */
    function isMemberInGroupAndGroupInOrg(
        address memberAddress,
        GroupData calldata groupData,
        bytes32[] calldata groupInOrgGroupsTreeProof,
        bytes32[] calldata memberInGroupProof
    ) external view returns (bool);
}
