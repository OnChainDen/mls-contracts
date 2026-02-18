// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {BitmaskHelpers} from "test/helpers/BitmaskHelpers.sol";
import {
    LibOrganizationGroupsHarness
} from "test/organization/libraries/LibOrganizationGroups/LibOrganizationGroupsHarness.sol";
import {GroupModification, GroupModificationType} from "types/CommonTypes.sol";

/**
 * @dev Stateful invariant handler for `LibOrganizationGroups` invariants.
 *      Mutations are executed through library helper wrappers; reverts are absorbed via low-level calls.
 */
contract LibOrganizationGroupsInvariantHandler is BitmaskHelpers {
    /// @dev Harness under test.
    LibOrganizationGroupsHarness public immutable harness;

    /// @dev Tracked group IDs used by stateful operations and invariant checks.
    uint256[] internal trackedGroupIds;

    /// @dev Tracked non-zero members used by stateful operations and invariant checks.
    address[] internal trackedMembers;

    /// @dev Model marker for monotonic deleted-group behavior.
    mapping(uint256 => bool) public modelWasDeletedEver;

    /**
     * @dev Initializes tracked universe and seeds baseline member status.
     */
    constructor(LibOrganizationGroupsHarness harness_, address member1, address member2, address member3) {
        harness = harness_;

        trackedGroupIds.push(1);
        trackedGroupIds.push(2);
        trackedGroupIds.push(3);
        trackedGroupIds.push(4);

        trackedMembers.push(member1);
        trackedMembers.push(member2);
        trackedMembers.push(member3);

        // Keep tracked members initially active in org-member mapping.
        harness.setMemberStatus(member1, true);
        harness.setMemberStatus(member2, true);
        harness.setMemberStatus(member3, true);

        // Seed one active group/member pair through direct state setup.
        harness.setGroupStatus(1, true);
        harness.setGroupMemberStatus(1, member1, true);
    }

    /**
     * @dev Stateful operation: create a tracked group with members selected by bitmask.
     */
    function createGroup(uint8 rawGroupIndex, uint8 addMask) external {
        uint256 groupId = trackedGroupIds[rawGroupIndex % trackedGroupIds.length];
        address[] memory membersToAdd = _membersFromMask(addMask);

        GroupModification memory mod = GroupModification({
            groupId: groupId,
            modificationType: GroupModificationType.Create,
            membersToAdd: membersToAdd,
            membersToRemove: new address[](0)
        });

        // Keep stateful sequences running through expected reverts.
        address(harness).call(abi.encodeCall(harness.createGroupViaLibrary, (mod)));
        _refreshDeletedModel();
    }

    /**
     * @dev Stateful operation: update a tracked group with add/remove masks.
     */
    function updateGroup(uint8 rawGroupIndex, uint8 addMask, uint8 removeMask) external {
        uint256 groupId = trackedGroupIds[rawGroupIndex % trackedGroupIds.length];
        address[] memory membersToAdd = _membersFromMask(addMask);
        address[] memory membersToRemove = _membersFromMask(removeMask);

        GroupModification memory mod = GroupModification({
            groupId: groupId,
            modificationType: GroupModificationType.Update,
            membersToAdd: membersToAdd,
            membersToRemove: membersToRemove
        });

        // Keep stateful sequences running through expected reverts.
        address(harness).call(abi.encodeCall(harness.updateGroupViaLibrary, (mod)));
        _refreshDeletedModel();
    }

    /**
     * @dev Stateful operation: delete a tracked group.
     */
    function deleteGroup(uint8 rawGroupIndex) external {
        uint256 groupId = trackedGroupIds[rawGroupIndex % trackedGroupIds.length];

        GroupModification memory mod = GroupModification({
            groupId: groupId,
            modificationType: GroupModificationType.Delete,
            membersToAdd: new address[](0),
            membersToRemove: new address[](0)
        });

        // Keep stateful sequences running through expected reverts.
        address(harness).call(abi.encodeCall(harness.deleteGroupViaLibrary, (mod)));
        _refreshDeletedModel();
    }

    /**
     * @dev Stateful operation: mutate org-member status for a tracked member.
     */
    function setTrackedOrgMemberStatus(uint8 rawMemberIndex, bool isMember) external {
        address member = trackedMembers[rawMemberIndex % trackedMembers.length];
        harness.setMemberStatus(member, isMember);
    }

    /**
     * @dev Returns tracked group count.
     */
    function trackedGroupCount() external view returns (uint256) {
        return trackedGroupIds.length;
    }

    /**
     * @dev Returns tracked group ID at index.
     */
    function trackedGroupIdAt(uint256 index) external view returns (uint256) {
        return trackedGroupIds[index];
    }

    /**
     * @dev Returns tracked member count.
     */
    function trackedMemberCount() external view returns (uint256) {
        return trackedMembers.length;
    }

    /**
     * @dev Returns tracked member at index.
     */
    function trackedMemberAt(uint256 index) external view returns (address) {
        return trackedMembers[index];
    }

    /**
     * @dev Builds an address array from lower-three-bits mask over tracked members.
     */
    function _membersFromMask(uint8 mask) internal view returns (address[] memory members) {
        uint8 masked = mask & 0x07;
        uint256 length = _popcountLowerBits(masked, 3);

        members = new address[](length);
        uint256 index = 0;
        for (uint256 i = 0; i < trackedMembers.length; i++) {
            if (((masked >> i) & 1) == 1) {
                members[index] = trackedMembers[i];
                index++;
            }
        }
    }

    /**
     * @dev Updates model marker when on-chain deleted marker becomes true.
     */
    function _refreshDeletedModel() internal {
        for (uint256 i = 0; i < trackedGroupIds.length; i++) {
            uint256 groupId = trackedGroupIds[i];
            if (harness.getWasGroupDeletedStatus(groupId)) {
                modelWasDeletedEver[groupId] = true;
            }
        }
    }
}
