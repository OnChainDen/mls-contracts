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
    function testFuzz_modifyGroups_failingItemPreservesAtomicity(
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

    /// @dev Verifies fuzzed group IDs cannot be reused after delete.
    function testFuzz_deletedGroupIds_neverReusable(uint256 groupId, address member) public {
        vm.assume(member != address(0));

        // Setup: create and delete a fuzzed group ID.
        harness.modifyGroupsViaLibrary(_buildModificationsArray(_createModification(groupId, buildArray(member))));
        harness.modifyGroupsViaLibrary(_buildModificationsArray(_deleteModification(groupId)));

        // Verify: recreate always reverts.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationGroups.GroupAlreadyDeleted.selector, groupId));
        harness.modifyGroupsViaLibrary(_buildModificationsArray(_createModification(groupId, buildArray(member))));
    }

    /// @dev Verifies duplicate additions are idempotent for arbitrary non-zero members.
    function testFuzz_duplicateAdditions_idempotent(address member, uint256 rawGroupId) public {
        vm.assume(member != address(0));
        uint256 groupId = bound(rawGroupId, 1, 50_000);

        groupsStateHarness.setGroupStatus(groupId, true);

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

    /// @dev Verifies any member-add batch containing zero address reverts with `InvalidMemberAddress`.
    function testFuzz_addGroupMembers_zeroAddressAlwaysReverts(uint256 rawGroupId, address otherMember, bool zeroFirst)
        public
    {
        uint256 groupId = bound(rawGroupId, 1, 50_000);
        groupsStateHarness.setGroupStatus(groupId, true);

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

    /// @dev Verifies desired behavior that arbitrary non-member addresses always revert with `MemberDoesNotExist`.
    function testFuzz_addGroupMembers_nonMembersAlwaysRevertMemberDoesNotExist(uint256 rawGroupId, address nonMember)
        public
    {
        uint256 groupId = bound(rawGroupId, 1, 50_000);
        vm.assume(nonMember != address(0));

        groupsStateHarness.setGroupStatus(groupId, true);
        groupsStateHarness.setMemberStatus(nonMember, false);

        // Desired behavior: non-member additions should revert.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationMembers.MemberDoesNotExist.selector, nonMember));
        harness.addGroupMembersViaLibrary(groupId, buildArray(nonMember));
    }
}
