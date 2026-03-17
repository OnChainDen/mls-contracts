// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Vm} from "forge-std/Vm.sol";

import {IOrganizationGroups} from "interfaces/organization/IOrganizationGroups.sol";
import {IOrganizationMembers} from "interfaces/organization/IOrganizationMembers.sol";
import {
    LibOrganizationGroupsSuiteBase
} from "test/organization/libraries/LibOrganizationGroups/LibOrganizationGroupsSuiteBase.sol";
import {GroupModification} from "types/CommonTypes.sol";

/**
 * @dev Fuzz tests for cross-file groups behaviors.
 */
contract LibOrganizationGroupsFuzzTest is LibOrganizationGroupsSuiteBase {
    /// @dev Verifies that any failing item in a fuzzed batch rolls back prior successful writes.
    function testFuzz_FLOG_HAR_53_modifyGroups_failingItemPreservesAtomicity(
        uint256 rawExistingGroupId,
        uint256 rawFailingGroupId,
        address existingMember,
        address newMember
    ) public {
        uint256 existingGroupId = bound(rawExistingGroupId, 1, 10_000);
        uint256 failingGroupId = bound(rawFailingGroupId, 1, 10_000);
        vm.assume(existingGroupId != failingGroupId);
        vm.assume(existingMember != address(0) && newMember != address(0));
        vm.assume(existingMember != newMember);

        // Setup: seed one active group and one active member before the fuzzed batch.
        groupsStateHarness.setGroupStatus(existingGroupId, true);
        groupsStateHarness.setGroupMemberStatus(existingGroupId, existingMember, true);
        _setMembers(buildArray(existingMember, newMember), true);

        GroupModification[] memory modifications = _buildModificationsArray(
            _updateModification(existingGroupId, buildArray(newMember), buildEmptyAddressArray()),
            _updateModification(failingGroupId, buildArray(existingMember), buildEmptyAddressArray())
        );

        // Snapshot: capture pre-state to assert atomic rollback on failure.
        bool expectExistingGroup = harness.isGroupViaLibrary(existingGroupId);
        bool expectExistingMember = harness.isGroupMemberViaLibrary(existingGroupId, existingMember);
        bool expectNewMember = harness.isGroupMemberViaLibrary(existingGroupId, newMember);

        vm.expectRevert(abi.encodeWithSelector(IOrganizationGroups.GroupDoesNotExist.selector, failingGroupId));
        harness.modifyGroupsViaLibrary(modifications);

        // Verify: all writes from the first successful step are rolled back.
        assertEq(harness.isGroupViaLibrary(existingGroupId), expectExistingGroup, "group active flag should rollback");
        assertEq(
            harness.isGroupMemberViaLibrary(existingGroupId, existingMember),
            expectExistingMember,
            "existing member bit should rollback"
        );
        assertEq(
            harness.isGroupMemberViaLibrary(existingGroupId, newMember),
            expectNewMember,
            "new member bit should rollback"
        );
    }

    /// @dev Verifies valid create/update/delete batches preserve the expected group lifecycle semantics.
    function testFuzz_FLOG_GROUP_49_modifyGroups_validLifecycleBatchesPreserveCreateUpdateDeleteSemantics(
        uint256 rawGroupId,
        address memberA,
        address memberB,
        bool removeMemberA,
        bool deleteGroupAtEnd
    ) public {
        uint256 groupId = bound(rawGroupId, 1, 50_000);
        vm.assume(memberA != address(0) && memberB != address(0));
        vm.assume(memberA != memberB);

        // Setup: register two valid organization members and build one valid create/update[/delete] batch.
        _setMembers(buildArray(memberA, memberB), true);

        GroupModification memory createModification = _createModification(groupId, buildArray(memberA));
        GroupModification memory updateModification = _updateModification(
            groupId, buildArray(memberB), removeMemberA ? buildArray(memberA) : buildEmptyAddressArray()
        );

        GroupModification[] memory modifications = deleteGroupAtEnd
            ? _buildModificationsArray(createModification, updateModification, _deleteModification(groupId))
            : _buildModificationsArray(createModification, updateModification);

        // Call: execute the valid lifecycle batch through the main library entry point.
        harness.modifyGroupsViaLibrary(modifications);

        if (deleteGroupAtEnd) {
            // Verify: delete-at-end batches should leave the group inactive and query helpers should fail closed.
            assertFalse(harness.isGroupViaLibrary(groupId), "delete-at-end batch should inactivate the group");
            assertFalse(harness.isGroupMemberViaLibrary(groupId, memberA), "deleted group should hide memberA");
            assertFalse(harness.isGroupMemberViaLibrary(groupId, memberB), "deleted group should hide memberB");
        } else {
            // Verify: create/update batches should preserve the expected membership model for both touched members.
            assertTrue(harness.isGroupViaLibrary(groupId), "group should remain active without a delete step");
            assertEq(
                harness.isGroupMemberViaLibrary(groupId, memberA),
                !removeMemberA,
                "memberA state should match the update removal flag"
            );
            assertTrue(harness.isGroupMemberViaLibrary(groupId, memberB), "memberB should be added by the update");
        }
    }

    /// @dev Verifies fuzzed group IDs cannot be reused after delete.
    function testFuzz_FLOG_GROUP_50_modifyGroups_deletedGroupIdsNeverReusable(uint256 groupId, address member) public {
        vm.assume(member != address(0));
        groupsStateHarness.setMemberStatus(member, true);

        // Setup: create and delete a fuzzed group ID.
        harness.modifyGroupsViaLibrary(_buildModificationsArray(_createModification(groupId, buildArray(member))));
        harness.modifyGroupsViaLibrary(_buildModificationsArray(_deleteModification(groupId)));

        // Verify: recreate always reverts.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationGroups.GroupAlreadyDeleted.selector, groupId));
        harness.modifyGroupsViaLibrary(_buildModificationsArray(_createModification(groupId, buildArray(member))));
    }

    /// @dev Verifies duplicate helper additions are idempotent for arbitrary non-zero members.
    function testFuzz_FLOG_HAR_53_addGroupMembers_duplicateAdditionsRemainConsistent(address member, uint256 rawGroupId)
        public
    {
        vm.assume(member != address(0));
        uint256 groupId = bound(rawGroupId, 1, 50_000);

        groupsStateHarness.setGroupStatus(groupId, true);
        groupsStateHarness.setMemberStatus(member, true);

        address[] memory members = new address[](2);
        members[0] = member;
        members[1] = member;

        vm.recordLogs();
        harness.addGroupMembersViaLibrary(groupId, members);

        // Verify: state is active and exactly one add event is emitted.
        assertTrue(harness.isGroupMemberViaLibrary(groupId, member), "member should be active");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 addedTopic = keccak256("GroupMemberAdded(uint256,address)");
        uint256 addedEventCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == addedTopic) {
                addedEventCount++;
            }
        }
        assertEq(addedEventCount, 1, "duplicate additions should emit one GroupMemberAdded event");
    }

    /// @dev Verifies create/update helper wrappers roll back atomically when a later zero-address member triggers the
    ///      documented validation error.
    function testFuzz_FLOG_HAR_53_createAndUpdateHelpersRevertAtomicallyOnInvalidMember(
        uint256 rawGroupId,
        address validMember,
        bool useCreatePath
    ) public {
        uint256 groupId = bound(rawGroupId, 1, 50_000);
        vm.assume(validMember != address(0));

        // Setup: seed one valid organization member, then prepare either a create or update helper call that hits
        // `address(0)` after touching valid state first.
        _setMembers(buildArray(validMember), true);
        if (useCreatePath) {
            GroupModification memory createModification =
                _createModification(groupId, buildArray(validMember, address(0)));

            // Call: execute the create helper and expect the exact zero-address validation revert.
            vm.expectRevert(abi.encodeWithSelector(IOrganizationMembers.InvalidMemberAddress.selector, address(0)));
            harness.createGroupViaLibrary(createModification);
        } else {
            address secondValidMember = _deriveHelperAddress(groupId, 1);
            vm.assume(secondValidMember != address(0));
            vm.assume(secondValidMember != validMember);

            groupsStateHarness.setGroupStatus(groupId, true);
            groupsStateHarness.setGroupMemberStatus(groupId, validMember, true);
            groupsStateHarness.setMemberStatus(secondValidMember, true);

            GroupModification memory updateModification =
                _updateModification(groupId, buildArray(secondValidMember, address(0)), buildEmptyAddressArray());

            // Call: execute the update helper and expect the exact zero-address validation revert.
            vm.expectRevert(abi.encodeWithSelector(IOrganizationMembers.InvalidMemberAddress.selector, address(0)));
            harness.updateGroupViaLibrary(updateModification);
        }

        // Verify: the invalid member should revert the helper and roll back earlier writes from the same helper call.
        if (useCreatePath) {
            assertFalse(harness.isGroupViaLibrary(groupId), "failed create helper should not persist the group");
            assertFalse(
                harness.isGroupMemberViaLibrary(groupId, validMember),
                "failed create helper should not persist valid-member writes"
            );
        } else {
            address secondValidMember = _deriveHelperAddress(groupId, 1);
            assertTrue(harness.isGroupViaLibrary(groupId), "failed update helper should preserve original group state");
            assertTrue(
                harness.isGroupMemberViaLibrary(groupId, validMember),
                "failed update helper should preserve pre-existing membership"
            );
            assertFalse(
                harness.isGroupMemberViaLibrary(groupId, secondValidMember),
                "failed update helper should roll back new member writes"
            );
        }
    }

    /// @dev Verifies any member-add batch containing zero address reverts with `InvalidMemberAddress`
    ///      when the paired non-zero address is otherwise valid.
    function testFuzz_FLOG_GROUP_51_addGroupMembers_zeroAddressAlwaysReverts(
        uint256 rawGroupId,
        address otherMember,
        bool zeroFirst
    ) public {
        uint256 groupId = bound(rawGroupId, 1, 50_000);
        vm.assume(otherMember != address(0));
        groupsStateHarness.setGroupStatus(groupId, true);
        groupsStateHarness.setMemberStatus(otherMember, true);

        address[] memory members = new address[](2);
        if (zeroFirst) {
            members[0] = address(0);
            members[1] = otherMember;
        } else {
            members[0] = otherMember;
            members[1] = address(0);
        }

        // Verify: zero-address inclusion should always revert.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationMembers.InvalidMemberAddress.selector, address(0)));
        harness.addGroupMembersViaLibrary(groupId, members);
    }

    /// @dev Verifies the desired behavior that arbitrary non-member addresses always revert with
    ///      `MemberDoesNotExist`.
    function testFuzz_FLOG_GROUP_52_addGroupMembers_nonMembersAlwaysRevertMemberDoesNotExist(
        uint256 rawGroupId,
        address nonMember
    ) public {
        uint256 groupId = bound(rawGroupId, 1, 50_000);
        vm.assume(nonMember != address(0));

        groupsStateHarness.setGroupStatus(groupId, true);
        groupsStateHarness.setMemberStatus(nonMember, false);

        // Desired behavior: non-member additions should revert.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationMembers.MemberDoesNotExist.selector, nonMember));
        harness.addGroupMembersViaLibrary(groupId, buildArray(nonMember));
    }

    /// @dev Verifies remove/delete helper wrappers keep group state consistent across successful cleanup flows.
    function testFuzz_FLOG_HAR_53_removeAndDeleteHelpersKeepStateConsistent(
        uint256 rawGroupId,
        address memberA,
        address memberB
    ) public {
        uint256 groupId = bound(rawGroupId, 1, 50_000);
        vm.assume(memberA != address(0) && memberB != address(0));
        vm.assume(memberA != memberB);

        // Setup: seed one active group with two active members before removing one member and deleting the group.
        groupsStateHarness.setGroupStatus(groupId, true);
        groupsStateHarness.setGroupMemberStatus(groupId, memberA, true);
        groupsStateHarness.setGroupMemberStatus(groupId, memberB, true);
        _setMembers(buildArray(memberA, memberB), true);

        // Call: remove one member through the helper, then delete the group through its dedicated helper.
        harness.removeGroupMembersViaLibrary(groupId, buildArray(memberA));
        harness.deleteGroupViaLibrary(_deleteModification(groupId));

        // Verify: the removal helper should clear only the requested member, and the delete helper should inactivate
        // the group for all future membership queries.
        assertFalse(harness.isGroupViaLibrary(groupId), "delete helper should inactivate the group");
        assertFalse(harness.isGroupMemberViaLibrary(groupId, memberA), "deleted group should hide the removed member");
        assertFalse(harness.isGroupMemberViaLibrary(groupId, memberB), "deleted group should hide remaining members");
    }

    /**
     * @dev Derives a deterministic helper address from the fuzzed group id and a one-byte differentiator.
     * @param groupId Group identifier used as part of the deterministic seed
     * @param differentiator Small differentiator used to derive distinct helper addresses
     * @return derived The derived helper address
     */
    function _deriveHelperAddress(uint256 groupId, uint8 differentiator) internal pure returns (address derived) {
        derived = address(uint160(uint256(keccak256(abi.encode(groupId, differentiator)))));
    }
}
