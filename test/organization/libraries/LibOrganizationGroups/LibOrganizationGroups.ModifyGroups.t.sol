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
 * @dev Unit tests for `LibOrganizationGroups.modifyGroups`.
 */
contract LibOrganizationGroupsModifyGroupsTest is LibOrganizationGroupsSuiteBase {
    /// @dev Stress batch size used by the large-batch creation test case.
    uint256 internal constant STRESS_GROUP_COUNT = 10_000;

    /**
     * @dev Raw-typed group modification used to craft malformed enum calldata.
     *      ABI shape intentionally mirrors `GroupModification` with `modificationType` as unchecked integer.
     */
    struct RawGroupModification {
        uint256 groupId;
        uint256 modificationType;
        address[] membersToAdd;
        address[] membersToRemove;
    }

    /// @dev Verifies that an empty modifications array is a no-op with no emitted events.
    function test_modifyGroups_emptyModifications_noOpAndNoEvents() public {
        uint256 existingGroupId = 7001;
        uint256 deletedGroupId = 7002;

        // Setup: seed baseline state that should remain untouched by an empty batch.
        groupsStateHarness.setGroupStatus(existingGroupId, true);
        groupsStateHarness.setGroupMemberStatus(existingGroupId, admin1, true);
        groupsStateHarness.setWasGroupDeletedStatus(deletedGroupId, true);

        GroupModification[] memory modifications = new GroupModification[](0);

        // Call: execute an empty batch.
        vm.recordLogs();
        harness.modifyGroupsViaLibrary(modifications);

        // Verify: seeded state is unchanged and no events were emitted.
        assertTrue(harness.isGroupViaLibrary(existingGroupId), "existing group should remain active");
        assertTrue(
            harness.isGroupMemberViaLibrary(existingGroupId, admin1), "existing group member should remain unchanged"
        );
        assertTrue(
            groupsStateHarness.getWasGroupDeletedStatus(deletedGroupId), "deleted-group marker should remain unchanged"
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0, "empty batch should not emit events");
    }

    /// @dev Verifies a mixed create/update/delete batch succeeds in-order across multiple groups.
    function test_modifyGroups_mixedCreateUpdateDeleteAcrossGroups_succeedsInOrder() public {
        uint256 groupA = 7101;
        uint256 groupB = 7102;

        // Setup: configure organization-member status for addresses used in mutations.
        _setMembers(buildArray(admin1, admin2, admin3), true);

        GroupModification[] memory modifications = _buildModificationsArray(
            _createModification(groupA, buildArray(admin1)),
            _createModification(groupB, buildArray(admin2)),
            _updateModification(groupA, buildArray(admin3), buildArray(admin1)),
            _deleteModification(groupB)
        );

        // Call: execute full mixed batch.
        harness.modifyGroupsViaLibrary(modifications);

        // Verify: groupA reflects update results and groupB reflects deletion results.
        assertTrue(harness.isGroupViaLibrary(groupA), "groupA should remain active");
        assertFalse(harness.isGroupMemberViaLibrary(groupA, admin1), "admin1 should be removed from groupA");
        assertTrue(harness.isGroupMemberViaLibrary(groupA, admin3), "admin3 should be added to groupA");

        assertFalse(harness.isGroupViaLibrary(groupB), "groupB should be deleted");
        assertTrue(groupsStateHarness.getWasGroupDeletedStatus(groupB), "groupB deleted marker should be set");
    }

    /// @dev Verifies `Create -> Update` for the same group in one batch succeeds.
    function test_modifyGroups_createThenUpdateSameGroupInOneBatch_succeeds() public {
        uint256 groupId = 7201;
        _setMembers(buildArray(admin1, admin2), true);

        GroupModification[] memory modifications = _buildModificationsArray(
            _createModification(groupId, buildArray(admin1)),
            _updateModification(groupId, buildArray(admin2), buildArray(admin1))
        );

        // Call: apply create then update on the same group ID.
        harness.modifyGroupsViaLibrary(modifications);

        // Verify: final state reflects both operations in order.
        assertTrue(harness.isGroupViaLibrary(groupId), "group should exist after create+update");
        assertFalse(harness.isGroupMemberViaLibrary(groupId, admin1), "admin1 should be removed by update");
        assertTrue(harness.isGroupMemberViaLibrary(groupId, admin2), "admin2 should be added by update");
    }

    /// @dev Verifies `Update -> Create` for the same group reverts on the update step.
    function test_modifyGroups_updateThenCreateSameGroup_revertsOnUpdate() public {
        uint256 groupId = 7202;
        _setMembers(buildArray(admin1), true);

        GroupModification[] memory modifications = _buildModificationsArray(
            _updateModification(groupId, buildArray(admin1), buildEmptyAddressArray()),
            _createModification(groupId, buildArray(admin1))
        );

        // Verify: first update should fail because the group does not exist yet.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationGroups.GroupDoesNotExist.selector, groupId));
        harness.modifyGroupsViaLibrary(modifications);

        assertFalse(harness.isGroupViaLibrary(groupId), "group should remain non-existent after revert");
    }

    /// @dev Verifies `Create -> Delete` in one call succeeds and leaves the group deleted.
    function test_modifyGroups_createThenDeleteSameGroupInOneBatch_succeedsAndLeavesDeleted() public {
        uint256 groupId = 7203;
        _setMembers(buildArray(admin1), true);

        GroupModification[] memory modifications =
            _buildModificationsArray(_createModification(groupId, buildArray(admin1)), _deleteModification(groupId));

        // Call: create and delete in one batch.
        harness.modifyGroupsViaLibrary(modifications);

        // Verify: active flag is false and deleted marker is true.
        assertFalse(harness.isGroupViaLibrary(groupId), "group should be deleted");
        assertTrue(groupsStateHarness.getWasGroupDeletedStatus(groupId), "deleted marker should be set");
        assertTrue(
            groupsStateHarness.getGroupMemberStatus(groupId, admin1),
            "historical membership should persist as ghost data"
        );
    }

    /// @dev Verifies `Delete -> Create` reverts with `GroupAlreadyDeleted` on the create step.
    function test_modifyGroups_deleteThenCreateSameGroup_revertsGroupAlreadyDeleted() public {
        uint256 groupId = 7204;

        // Setup: seed an existing active group.
        groupsStateHarness.setGroupStatus(groupId, true);

        GroupModification[] memory modifications =
            _buildModificationsArray(_deleteModification(groupId), _createModification(groupId, buildArray(admin1)));

        // Verify: second operation should fail because the batch marked the ID as deleted.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationGroups.GroupAlreadyDeleted.selector, groupId));
        harness.modifyGroupsViaLibrary(modifications);

        // Verify: atomic revert preserves original pre-batch state.
        assertTrue(harness.isGroupViaLibrary(groupId), "group should remain active after revert");
        assertFalse(groupsStateHarness.getWasGroupDeletedStatus(groupId), "deleted marker should rollback on revert");
    }

    /// @dev Verifies `Delete -> Update` reverts with `GroupDoesNotExist` on the update step.
    function test_modifyGroups_deleteThenUpdateSameGroup_revertsGroupDoesNotExist() public {
        uint256 groupId = 7205;

        // Setup: seed an existing active group.
        groupsStateHarness.setGroupStatus(groupId, true);

        GroupModification[] memory modifications = _buildModificationsArray(
            _deleteModification(groupId), _updateModification(groupId, buildArray(admin1), buildEmptyAddressArray())
        );

        // Verify: update should fail after prior delete in the same batch.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationGroups.GroupDoesNotExist.selector, groupId));
        harness.modifyGroupsViaLibrary(modifications);

        assertTrue(harness.isGroupViaLibrary(groupId), "group should remain active after rollback");
    }

    /// @dev Verifies `Create -> Create` for the same group reverts with `GroupAlreadyExists` on second create.
    function test_modifyGroups_createThenCreateSameGroup_revertsGroupAlreadyExists() public {
        uint256 groupId = 7206;

        GroupModification[] memory modifications = _buildModificationsArray(
            _createModification(groupId, buildEmptyAddressArray()),
            _createModification(groupId, buildEmptyAddressArray())
        );

        // Verify: second create in one batch must revert.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationGroups.GroupAlreadyExists.selector, groupId));
        harness.modifyGroupsViaLibrary(modifications);

        assertFalse(harness.isGroupViaLibrary(groupId), "group should not exist because the transaction reverted");
    }

    /// @dev Verifies any failing item in a batch reverts the whole transaction atomically.
    function test_modifyGroups_failingModification_revertsEntireBatchAtomically() public {
        uint256 newGroupId = 7207;
        uint256 nonExistentGroupId = 7999;

        GroupModification[] memory modifications = _buildModificationsArray(
            _createModification(newGroupId, buildArray(admin1)),
            _updateModification(nonExistentGroupId, buildArray(admin2), buildEmptyAddressArray())
        );

        // Verify: middle failure should rollback prior successful state writes.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationGroups.GroupDoesNotExist.selector, nonExistentGroupId));
        harness.modifyGroupsViaLibrary(modifications);

        assertFalse(harness.isGroupViaLibrary(newGroupId), "create from reverted batch must rollback");
        assertFalse(harness.isGroupMemberViaLibrary(newGroupId, admin1), "member addition must rollback");
    }

    /// @dev Verifies helper-path custom errors bubble unchanged through `modifyGroups`.
    function test_modifyGroups_underlyingHelperRevertData_bubblesUnchanged() public {
        uint256 groupId = 7208;

        GroupModification[] memory modifications = _buildModificationsArray(
            _buildGroupModification(groupId, GroupModificationType.Create, buildEmptyAddressArray(), buildArray(admin1))
        );

        // Verify: `_createGroup` revert data should bubble exactly.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationGroups.InvalidGroupCreationOperation.selector, groupId));
        harness.modifyGroupsViaLibrary(modifications);
    }

    /// @dev Verifies malformed enum values revert instead of being silently skipped.
    function test_modifyGroups_malformedEnumValue_revertsAndDoesNotSkip() public {
        uint256 groupId = 7209;
        RawGroupModification[] memory rawModifications = new RawGroupModification[](1);
        rawModifications[0] = RawGroupModification({
            groupId: groupId,
            modificationType: 77,
            membersToAdd: buildArray(admin1),
            membersToRemove: buildEmptyAddressArray()
        });

        bytes memory malformedCallData =
            abi.encodeWithSelector(harness.modifyGroupsViaLibrary.selector, rawModifications);

        // Desired behavior: malformed enum in calldata should revert.
        (bool success,) = address(harness).call(malformedCallData);
        assertFalse(success, "malformed enum payload should revert");

        assertFalse(harness.isGroupViaLibrary(groupId), "malformed enum path should not mutate state");
    }

    /// @dev Verifies event ordering in a successful mixed batch follows modification order.
    function test_modifyGroups_eventOrderingInMixedBatch_followsModificationOrder() public {
        uint256 groupId = 7210;

        GroupModification[] memory modifications = _buildModificationsArray(
            _createModification(groupId, buildArray(admin1, admin2)),
            _updateModification(groupId, buildArray(admin3), buildArray(admin1)),
            _deleteModification(groupId)
        );

        // Verify: events are emitted in deterministic order matching modification execution order.
        vm.expectEmit(true, false, false, true);
        emit IOrganizationGroups.GroupCreated(groupId);
        vm.expectEmit(true, true, false, true);
        emit IOrganizationGroups.GroupMemberAdded(groupId, admin1);
        vm.expectEmit(true, true, false, true);
        emit IOrganizationGroups.GroupMemberAdded(groupId, admin2);
        vm.expectEmit(true, true, false, true);
        emit IOrganizationGroups.GroupMemberAdded(groupId, admin3);
        vm.expectEmit(true, true, false, true);
        emit IOrganizationGroups.GroupMemberRemoved(groupId, admin1);
        vm.expectEmit(true, false, false, true);
        emit IOrganizationGroups.GroupDeleted(groupId);

        harness.modifyGroupsViaLibrary(modifications);
    }

    /// @dev Verifies boundary IDs `0` and `type(uint256).max` are handled correctly in a batch.
    function test_modifyGroups_boundaryGroupIds_zeroAndMax_supported() public {
        uint256 zeroGroupId = 0;
        uint256 maxGroupId = type(uint256).max;

        GroupModification[] memory modifications = _buildModificationsArray(
            _createModification(zeroGroupId, buildArray(admin1)),
            _createModification(maxGroupId, buildArray(admin2)),
            _updateModification(zeroGroupId, buildArray(admin2), buildArray(admin1))
        );

        // Call: apply boundary-ID mutations.
        harness.modifyGroupsViaLibrary(modifications);

        // Verify: both boundary IDs remain queryable and correctly mutated.
        assertTrue(harness.isGroupViaLibrary(zeroGroupId), "groupId=0 should be active");
        assertTrue(harness.isGroupViaLibrary(maxGroupId), "groupId=max should be active");
        assertFalse(harness.isGroupMemberViaLibrary(zeroGroupId, admin1), "admin1 should be removed from groupId=0");
        assertTrue(harness.isGroupMemberViaLibrary(zeroGroupId, admin2), "admin2 should be added to groupId=0");
        assertTrue(harness.isGroupMemberViaLibrary(maxGroupId, admin2), "admin2 should be in groupId=max");
    }

    /// @dev Verifies a batch containing a malformed enum in the middle reverts atomically.
    function test_modifyGroups_createThenMalformedEnumThenUpdate_revertsAtomically() public {
        uint256 groupId = 7211;
        RawGroupModification[] memory rawModifications = new RawGroupModification[](3);
        rawModifications[0] = RawGroupModification({
            groupId: groupId,
            modificationType: uint256(GroupModificationType.Create),
            membersToAdd: buildArray(admin1),
            membersToRemove: buildEmptyAddressArray()
        });
        rawModifications[1] = RawGroupModification({
            groupId: 8888,
            modificationType: 88,
            membersToAdd: buildEmptyAddressArray(),
            membersToRemove: buildEmptyAddressArray()
        });
        rawModifications[2] = RawGroupModification({
            groupId: groupId,
            modificationType: uint256(GroupModificationType.Update),
            membersToAdd: buildArray(admin2),
            membersToRemove: buildArray(admin1)
        });

        bytes memory malformedCallData =
            abi.encodeWithSelector(harness.modifyGroupsViaLibrary.selector, rawModifications);

        // Desired behavior: malformed enum should revert and rollback preceding valid operations.
        (bool success,) = address(harness).call(malformedCallData);
        assertFalse(success, "malformed enum payload should revert");

        assertFalse(harness.isGroupViaLibrary(groupId), "create before malformed enum should rollback");
        assertFalse(
            harness.isGroupMemberViaLibrary(groupId, admin1), "member write before malformed enum should rollback"
        );
    }

    /// @dev Verifies a middle-item revert rolls back all prior and subsequent modifications with no events.
    function test_modifyGroups_middleModificationReverts_rollsBackAllStateAndEvents() public {
        uint256 existingGroupId = 7212;
        uint256 newGroupId = 7213;
        uint256 failingGroupId = 9000;

        // Setup: seed an existing group so delete-path rollback can be asserted.
        groupsStateHarness.setGroupStatus(existingGroupId, true);
        groupsStateHarness.setGroupMemberStatus(existingGroupId, admin3, true);

        GroupModification[] memory modifications = _buildModificationsArray(
            _createModification(newGroupId, buildArray(admin1)),
            _deleteModification(existingGroupId),
            _updateModification(failingGroupId, buildArray(admin2), buildEmptyAddressArray()),
            _updateModification(newGroupId, buildArray(admin2), buildArray(admin1))
        );

        // Verify: failure in the middle should rollback all state writes and event emissions.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationGroups.GroupDoesNotExist.selector, failingGroupId));
        harness.modifyGroupsViaLibrary(modifications);

        assertFalse(harness.isGroupViaLibrary(newGroupId), "new group should not exist after rollback");
        assertFalse(harness.isGroupMemberViaLibrary(newGroupId, admin1), "new-group membership should rollback");
        assertFalse(harness.isGroupMemberViaLibrary(newGroupId, admin2), "new-group membership should rollback");

        assertTrue(harness.isGroupViaLibrary(existingGroupId), "existing group deletion should rollback");
        assertTrue(
            harness.isGroupMemberViaLibrary(existingGroupId, admin3), "existing-group membership should remain intact"
        );
    }

    /// @dev Verifies a 10,000-group create batch succeeds and every group is queryable as active.
    function test_modifyGroups_batchCreateTenThousandGroups_succeedsAndAllQueryable() public {
        address[] memory emptyMembers = buildEmptyAddressArray();
        GroupModification[] memory modifications = new GroupModification[](STRESS_GROUP_COUNT);

        // Setup: build a large all-create batch with empty member sets.
        for (uint256 i = 0; i < STRESS_GROUP_COUNT; i++) {
            modifications[i] = _buildGroupModification(i + 1, GroupModificationType.Create, emptyMembers, emptyMembers);
        }

        // Call: execute stress batch.
        harness.modifyGroupsViaLibrary(modifications);

        // Verify: each created group ID is queryable via `isGroup`.
        for (uint256 i = 0; i < STRESS_GROUP_COUNT; i++) {
            assertTrue(harness.isGroupViaLibrary(i + 1), "created group should be active");
        }
    }
}
