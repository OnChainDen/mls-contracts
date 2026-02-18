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
 * @dev Unit tests for `LibOrganizationGroups._updateGroup` via harness wrapper.
 */
contract LibOrganizationGroupsUpdateGroupTest is LibOrganizationGroupsSuiteBase {
    /// @dev Verifies updating an existing group with additions succeeds and leaves unrelated members unchanged.
    function test_updateGroup_addMembers_succeedsAndKeepsUnrelatedMembersUnchanged() public {
        uint256 groupId = 7501;

        // Setup: active group with two pre-existing members.
        groupsStateHarness.setGroupStatus(groupId, true);
        groupsStateHarness.setGroupMemberStatus(groupId, admin1, true);
        groupsStateHarness.setGroupMemberStatus(groupId, admin3, true);

        GroupModification memory mod = _updateModification(groupId, buildArray(admin2), buildEmptyAddressArray());

        // Call: add admin2.
        harness.updateGroupViaLibrary(mod);

        // Verify: added member becomes active and unrelated members remain unchanged.
        assertTrue(harness.isGroupMemberViaLibrary(groupId, admin2), "admin2 should be added");
        assertTrue(harness.isGroupMemberViaLibrary(groupId, admin1), "admin1 should remain in group");
        assertTrue(harness.isGroupMemberViaLibrary(groupId, admin3), "admin3 should remain in group");
    }

    /// @dev Verifies updating an existing group with removals succeeds and leaves unrelated members unchanged.
    function test_updateGroup_removeMembers_succeedsAndKeepsUnrelatedMembersUnchanged() public {
        uint256 groupId = 7502;

        // Setup: active group with three members.
        groupsStateHarness.setGroupStatus(groupId, true);
        groupsStateHarness.setGroupMemberStatus(groupId, admin1, true);
        groupsStateHarness.setGroupMemberStatus(groupId, admin2, true);
        groupsStateHarness.setGroupMemberStatus(groupId, admin3, true);

        GroupModification memory mod = _updateModification(groupId, buildEmptyAddressArray(), buildArray(admin2));

        // Call: remove admin2.
        harness.updateGroupViaLibrary(mod);

        // Verify: removed member is inactive and unrelated members remain active.
        assertFalse(harness.isGroupMemberViaLibrary(groupId, admin2), "admin2 should be removed");
        assertTrue(harness.isGroupMemberViaLibrary(groupId, admin1), "admin1 should remain active");
        assertTrue(harness.isGroupMemberViaLibrary(groupId, admin3), "admin3 should remain active");
    }

    /// @dev Verifies mixed additions+removals in one update produce the expected final membership set.
    function test_updateGroup_addsAndRemovals_sameModification_expectedFinalSet() public {
        uint256 groupId = 7503;

        // Setup: active group with admin1 initially present.
        groupsStateHarness.setGroupStatus(groupId, true);
        groupsStateHarness.setGroupMemberStatus(groupId, admin1, true);

        GroupModification memory mod = _updateModification(groupId, buildArray(admin2), buildArray(admin1));

        // Call: add admin2 then remove admin1.
        harness.updateGroupViaLibrary(mod);

        // Verify: final set reflects add-first/remove-second ordering.
        assertTrue(harness.isGroupMemberViaLibrary(groupId, admin2), "admin2 should be added");
        assertFalse(harness.isGroupMemberViaLibrary(groupId, admin1), "admin1 should be removed");
    }

    /// @dev Verifies updating a non-existent group reverts with `GroupDoesNotExist`.
    function test_updateGroup_nonExistentGroup_revertsGroupDoesNotExist() public {
        uint256 groupId = 7504;
        GroupModification memory mod = _updateModification(groupId, buildArray(admin1), buildEmptyAddressArray());

        // Verify: update requires an active group.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationGroups.GroupDoesNotExist.selector, groupId));
        harness.updateGroupViaLibrary(mod);
    }

    /// @dev Verifies updating a deleted group reverts with `GroupDoesNotExist`.
    function test_updateGroup_deletedGroup_revertsGroupDoesNotExist() public {
        uint256 groupId = 7505;

        // Setup: mark group as previously deleted.
        groupsStateHarness.setWasGroupDeletedStatus(groupId, true);

        GroupModification memory mod = _updateModification(groupId, buildArray(admin1), buildEmptyAddressArray());

        // Verify: deleted groups are treated as non-existent for update.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationGroups.GroupDoesNotExist.selector, groupId));
        harness.updateGroupViaLibrary(mod);
    }

    /// @dev Verifies desired behavior that removing a non-member is a no-op with no `GroupMemberRemoved` event.
    function test_updateGroup_removeNonMember_isNoOpAndEmitsNoRemovalEvent() public {
        uint256 groupId = 7506;

        // Setup: active group where admin2 is not currently a member.
        groupsStateHarness.setGroupStatus(groupId, true);
        groupsStateHarness.setGroupMemberStatus(groupId, admin1, true);

        GroupModification memory mod = _updateModification(groupId, buildEmptyAddressArray(), buildArray(admin2));

        vm.recordLogs();
        harness.updateGroupViaLibrary(mod);

        // Desired behavior: removing non-members should be a no-op.
        assertTrue(harness.isGroupMemberViaLibrary(groupId, admin1), "existing member should remain unchanged");
        assertFalse(harness.isGroupMemberViaLibrary(groupId, admin2), "non-member should remain absent");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 memberRemovedTopic = keccak256("GroupMemberRemoved(uint256,address)");
        uint256 removedEventCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == memberRemovedTopic) {
                removedEventCount++;
            }
        }
        assertEq(removedEventCount, 0, "non-member removals should not emit GroupMemberRemoved");
    }

    /// @dev Verifies adding an already-existing member is idempotent and emits no duplicate add event.
    function test_updateGroup_addExistingMember_idempotentNoDuplicateEvent() public {
        uint256 groupId = 7507;

        // Setup: active group where admin1 is already a member.
        groupsStateHarness.setGroupStatus(groupId, true);
        groupsStateHarness.setGroupMemberStatus(groupId, admin1, true);

        GroupModification memory mod = _updateModification(groupId, buildArray(admin1), buildEmptyAddressArray());

        vm.recordLogs();
        harness.updateGroupViaLibrary(mod);

        // Verify: state remains true and no add event is emitted.
        assertTrue(harness.isGroupMemberViaLibrary(groupId, admin1), "existing member should remain active");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 memberAddedTopic = keccak256("GroupMemberAdded(uint256,address)");
        uint256 addedEventCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == memberAddedTopic) {
                addedEventCount++;
            }
        }
        assertEq(addedEventCount, 0, "adding existing member should not emit GroupMemberAdded");
    }

    /// @dev Verifies adding the zero address reverts with `InvalidMemberAddress`.
    function test_updateGroup_addZeroAddress_revertsInvalidMemberAddress() public {
        uint256 groupId = 7508;
        groupsStateHarness.setGroupStatus(groupId, true);

        GroupModification memory mod = _updateModification(groupId, buildArray(address(0)), buildEmptyAddressArray());

        // Verify: zero address is invalid for additions.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationMembers.InvalidMemberAddress.selector, address(0)));
        harness.updateGroupViaLibrary(mod);
    }

    /// @dev Verifies desired behavior that adding a non-organization member reverts with `MemberDoesNotExist`.
    function test_updateGroup_addNonOrganizationMember_revertsMemberDoesNotExist() public {
        uint256 groupId = 7509;
        address nonMember = address(0xF509);
        groupsStateHarness.setGroupStatus(groupId, true);
        _setMembers(buildArray(admin1), true);

        GroupModification memory mod = _updateModification(groupId, buildArray(nonMember), buildEmptyAddressArray());

        // Desired behavior: update add path should validate org membership.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationMembers.MemberDoesNotExist.selector, nonMember));
        harness.updateGroupViaLibrary(mod);
    }

    /// @dev Verifies desired behavior that mixed valid+invalid additions revert atomically.
    function test_updateGroup_mixedValidAndInvalidAdditions_revertsAtomically() public {
        uint256 groupId = 7510;
        address nonMember = address(0xF510);
        groupsStateHarness.setGroupStatus(groupId, true);
        _setMembers(buildArray(admin1), true);

        GroupModification memory mod =
            _updateModification(groupId, buildArray(admin1, nonMember), buildEmptyAddressArray());

        vm.expectRevert(abi.encodeWithSelector(IOrganizationMembers.MemberDoesNotExist.selector, nonMember));
        harness.updateGroupViaLibrary(mod);

        // Desired behavior: no partial writes from valid-prefix additions.
        assertFalse(harness.isGroupMemberViaLibrary(groupId, admin1), "valid-prefix addition should rollback");
    }

    /// @dev Verifies desired behavior that removed org members cannot be added/re-added to groups.
    function test_updateGroup_removedOrgMemberCannotBeAdded_revertsMemberDoesNotExist() public {
        uint256 groupId = 7511;
        groupsStateHarness.setGroupStatus(groupId, true);
        groupsStateHarness.setMemberStatus(admin1, false);

        GroupModification memory mod = _updateModification(groupId, buildArray(admin1), buildEmptyAddressArray());

        // Desired behavior: inactive org members should be rejected.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationMembers.MemberDoesNotExist.selector, admin1));
        harness.updateGroupViaLibrary(mod);
    }

    /// @dev Verifies overlap semantics for initially-absent member in add+remove set ends removed.
    function test_updateGroup_overlapAddAndRemove_initiallyAbsent_endsRemoved() public {
        uint256 groupId = 7512;
        groupsStateHarness.setGroupStatus(groupId, true);

        GroupModification memory mod = _updateModification(groupId, buildArray(admin1), buildArray(admin1));

        // Call: add then remove same member.
        harness.updateGroupViaLibrary(mod);

        // Verify: final state should be removed.
        assertFalse(harness.isGroupMemberViaLibrary(groupId, admin1), "member should end removed");
    }

    /// @dev Verifies overlap semantics for initially-present member in add+remove set ends removed.
    function test_updateGroup_overlapAddAndRemove_initiallyPresent_endsRemoved() public {
        uint256 groupId = 7513;
        groupsStateHarness.setGroupStatus(groupId, true);
        groupsStateHarness.setGroupMemberStatus(groupId, admin1, true);

        GroupModification memory mod = _updateModification(groupId, buildArray(admin1), buildArray(admin1));

        // Call: no-op add followed by remove.
        harness.updateGroupViaLibrary(mod);

        // Verify: final state should be removed.
        assertFalse(harness.isGroupMemberViaLibrary(groupId, admin1), "member should end removed");
    }

    /// @dev Verifies mixed update emits all add events before remove events.
    function test_updateGroup_eventOrdering_addsEmittedBeforeRemovals() public {
        uint256 groupId = 7514;
        address extraMember = address(0xF514);

        // Setup: active group with two members to remove.
        groupsStateHarness.setGroupStatus(groupId, true);
        groupsStateHarness.setGroupMemberStatus(groupId, admin1, true);
        groupsStateHarness.setGroupMemberStatus(groupId, admin2, true);
        _setMembers(buildArray(admin3, extraMember), true);

        GroupModification memory mod =
            _updateModification(groupId, buildArray(admin3, extraMember), buildArray(admin1, admin2));

        // Verify: add events are emitted before remove events for mixed updates.
        vm.expectEmit(true, true, false, true);
        emit IOrganizationGroups.GroupMemberAdded(groupId, admin3);
        vm.expectEmit(true, true, false, true);
        emit IOrganizationGroups.GroupMemberAdded(groupId, extraMember);
        vm.expectEmit(true, true, false, true);
        emit IOrganizationGroups.GroupMemberRemoved(groupId, admin1);
        vm.expectEmit(true, true, false, true);
        emit IOrganizationGroups.GroupMemberRemoved(groupId, admin2);

        harness.updateGroupViaLibrary(mod);
    }
}
