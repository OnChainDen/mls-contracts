// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Vm} from "forge-std/Vm.sol";

import {IOrganizationGroups} from "interfaces/organization/IOrganizationGroups.sol";
import {
    LibOrganizationGroupsSuiteBase
} from "test/organization/libraries/LibOrganizationGroups/LibOrganizationGroupsSuiteBase.sol";
import {GroupModification, GroupModificationType} from "types/CommonTypes.sol";

/**
 * @dev Unit tests for `LibOrganizationGroups._deleteGroup` via harness wrapper.
 */
contract LibOrganizationGroupsDeleteGroupTest is LibOrganizationGroupsSuiteBase {
    /// @dev Verifies deleting an existing group succeeds and sets `isGroup[groupId] = false`.
    function test_deleteGroup_existingGroup_succeedsAndSetsIsGroupFalse() public {
        uint256 groupId = 7601;
        groupsStateHarness.setGroupStatus(groupId, true);

        GroupModification memory mod = _deleteModification(groupId);

        // Call: execute delete helper path.
        harness.deleteGroupViaLibrary(mod);

        // Verify: active-group flag is cleared.
        assertFalse(harness.isGroupViaLibrary(groupId), "group should be inactive after deletion");
    }

    /// @dev Verifies deletion sets `wasGroupDeleted` and the flag remains true permanently.
    function test_deleteGroup_setsWasGroupDeletedAndFlagNeverResets() public {
        uint256 groupId = 7602;
        groupsStateHarness.setGroupStatus(groupId, true);

        // Call: delete once.
        harness.deleteGroupViaLibrary(_deleteModification(groupId));

        // Verify: deleted marker is set.
        assertTrue(groupsStateHarness.getWasGroupDeletedStatus(groupId), "deleted marker should be set");

        // Verify: recreate attempts revert and must not clear deleted marker.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationGroups.GroupAlreadyDeleted.selector, groupId));
        harness.createGroupViaLibrary(_createModification(groupId, buildEmptyAddressArray()));

        assertTrue(groupsStateHarness.getWasGroupDeletedStatus(groupId), "deleted marker should remain true forever");
    }

    /// @dev Verifies desired behavior that deleting a non-existent group is a no-op with no event.
    function test_deleteGroup_nonExistentGroup_isNoOpAndEmitsNoEvent() public {
        uint256 groupId = 7603;

        GroupModification memory mod = _deleteModification(groupId);

        vm.recordLogs();
        harness.deleteGroupViaLibrary(mod);

        // Desired behavior: deleting non-existent groups should no-op.
        assertFalse(harness.isGroupViaLibrary(groupId), "non-existent group should remain inactive");
        assertFalse(groupsStateHarness.getWasGroupDeletedStatus(groupId), "deleted marker should remain unchanged");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0, "non-existent group delete should emit no events");
    }

    /// @dev Verifies non-empty `membersToAdd` in delete path reverts `InvalidGroupDeletionOperation`.
    function test_deleteGroup_nonEmptyMembersToAdd_revertsInvalidGroupDeletionOperation() public {
        uint256 groupId = 7604;
        groupsStateHarness.setGroupStatus(groupId, true);

        GroupModification memory mod = _buildGroupModification(
            groupId, GroupModificationType.Delete, buildArray(admin1), buildEmptyAddressArray()
        );

        // Verify: delete path forbids membersToAdd.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationGroups.InvalidGroupDeletionOperation.selector, groupId));
        harness.deleteGroupViaLibrary(mod);
    }

    /// @dev Verifies non-empty `membersToRemove` in delete path reverts `InvalidGroupDeletionOperation`.
    function test_deleteGroup_nonEmptyMembersToRemove_revertsInvalidGroupDeletionOperation() public {
        uint256 groupId = 7605;
        groupsStateHarness.setGroupStatus(groupId, true);

        GroupModification memory mod = _buildGroupModification(
            groupId, GroupModificationType.Delete, buildEmptyAddressArray(), buildArray(admin1)
        );

        // Verify: delete path forbids membersToRemove.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationGroups.InvalidGroupDeletionOperation.selector, groupId));
        harness.deleteGroupViaLibrary(mod);
    }

    /// @dev Verifies successful deletion emits `GroupDeleted` exactly once.
    function test_deleteGroup_emitsGroupDeletedExactlyOnce() public {
        uint256 groupId = 7606;
        groupsStateHarness.setGroupStatus(groupId, true);

        vm.recordLogs();
        harness.deleteGroupViaLibrary(_deleteModification(groupId));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 groupDeletedTopic = keccak256("GroupDeleted(uint256)");
        uint256 deletedEventCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == groupDeletedTopic) {
                deletedEventCount++;
            }
        }
        assertEq(deletedEventCount, 1, "delete should emit exactly one GroupDeleted event");
    }

    /// @dev Verifies deleted group IDs cannot be recreated.
    function test_deleteGroup_recreateDeletedGroup_revertsGroupAlreadyDeleted() public {
        uint256 groupId = 7607;
        groupsStateHarness.setGroupStatus(groupId, true);

        harness.deleteGroupViaLibrary(_deleteModification(groupId));

        // Verify: deleted IDs are permanently retired.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationGroups.GroupAlreadyDeleted.selector, groupId));
        harness.createGroupViaLibrary(_createModification(groupId, buildArray(admin1)));
    }

    /// @dev Verifies `isGroupMember` ghost entries persist after delete.
    function test_deleteGroup_historicalMembershipEntriesPersistAsGhostData() public {
        uint256 groupId = 7608;

        // Setup: create group with one member, then delete it.
        harness.createGroupViaLibrary(_createModification(groupId, buildArray(admin1)));
        harness.deleteGroupViaLibrary(_deleteModification(groupId));

        // Verify: active-group flag is false but historical storage bit remains true.
        assertFalse(harness.isGroupViaLibrary(groupId), "group should be inactive");
        assertTrue(groupsStateHarness.getGroupMemberStatus(groupId, admin1), "membership ghost data should persist");
    }
}
