// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Vm} from "forge-std/Vm.sol";

import {IOrganizationGroups} from "interfaces/organization/IOrganizationGroups.sol";
import {IOrganizationMembers} from "interfaces/organization/IOrganizationMembers.sol";
import {
    LibOrganizationGroupsSuiteBase
} from "test/organization/libraries/LibOrganizationGroups/LibOrganizationGroupsSuiteBase.sol";
import {GroupModification, GroupModificationType} from "types/CommonTypes.sol";

/**
 * @dev Unit tests for `LibOrganizationGroups._createGroup` via harness wrapper.
 */
contract LibOrganizationGroupsCreateGroupTest is LibOrganizationGroupsSuiteBase {
    /// @dev Verifies create succeeds for a new group ID with valid members.
    function test_createGroup__OGB_PH_1_validNewIdAndMembers_succeedsAndSetsState() public {
        uint256 groupId = 7401;
        _setMembers(buildArray(admin1, admin2), true);

        GroupModification memory mod = _createModification(groupId, buildArray(admin1, admin2));

        // Call: execute create helper path.
        harness.createGroupViaLibrary(mod);

        // Verify: group and member flags are set as expected.
        assertTrue(harness.isGroupViaLibrary(groupId), "group should be active after create");
        assertTrue(harness.isGroupMemberViaLibrary(groupId, admin1), "admin1 should be in group");
        assertTrue(harness.isGroupMemberViaLibrary(groupId, admin2), "admin2 should be in group");
    }

    /// @dev Verifies create with an empty member list succeeds.
    function test_createGroup_emptyMemberList_succeedsWithNoMembershipWrites() public {
        uint256 groupId = 7402;
        GroupModification memory mod = _createModification(groupId, buildEmptyAddressArray());

        // Call: execute create helper path.
        harness.createGroupViaLibrary(mod);

        // Verify: group is active and no membership entries are set.
        assertTrue(harness.isGroupViaLibrary(groupId), "group should be active after create");
        assertFalse(harness.isGroupMemberViaLibrary(groupId, admin1), "membership should remain unset");
    }

    /// @dev Verifies creating an already-active group reverts with `GroupAlreadyExists`.
    function test_createGroup_existingGroup_revertsGroupAlreadyExists() public {
        uint256 groupId = 7403;
        groupsStateHarness.setGroupStatus(groupId, true);

        GroupModification memory mod = _createModification(groupId, buildArray(admin1));

        // Verify: existing group ID cannot be created again.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationGroups.GroupAlreadyExists.selector, groupId));
        harness.createGroupViaLibrary(mod);
    }

    /// @dev Verifies creating a previously-deleted group ID reverts with `GroupAlreadyDeleted`.
    function test_createGroup_previouslyDeletedId_revertsGroupAlreadyDeleted() public {
        uint256 groupId = 7404;
        groupsStateHarness.setWasGroupDeletedStatus(groupId, true);

        GroupModification memory mod = _createModification(groupId, buildArray(admin1));

        // Verify: deleted group IDs are not reusable.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationGroups.GroupAlreadyDeleted.selector, groupId));
        harness.createGroupViaLibrary(mod);
    }

    /// @dev Verifies non-empty `membersToRemove` in create path reverts with `InvalidGroupCreationOperation`.
    function test_createGroup_nonEmptyMembersToRemove_revertsInvalidGroupCreationOperation() public {
        uint256 groupId = 7405;

        GroupModification memory mod =
            _buildGroupModification(groupId, GroupModificationType.Create, buildArray(admin1), buildArray(admin2));

        // Verify: create path forbids removals.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationGroups.InvalidGroupCreationOperation.selector, groupId));
        harness.createGroupViaLibrary(mod);
    }

    /// @dev Verifies successful create emits `GroupCreated` exactly once.
    function test_createGroup_emitsGroupCreatedExactlyOnce() public {
        uint256 groupId = 7406;
        GroupModification memory mod = _createModification(groupId, buildEmptyAddressArray());

        // Verify: exactly one `GroupCreated` event is emitted for this call.
        vm.recordLogs();
        harness.createGroupViaLibrary(mod);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 createdEventCount = 0;
        bytes32 groupCreatedTopic = keccak256("GroupCreated(uint256)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == groupCreatedTopic) {
                createdEventCount++;
            }
        }
        assertEq(createdEventCount, 1, "single create call should emit exactly one GroupCreated event");
    }

    /// @dev Verifies successful create emits `GroupMemberAdded` for each newly-added unique member.
    function test_createGroup_emitsGroupMemberAddedForEachUniqueMember() public {
        uint256 groupId = 7407;
        GroupModification memory mod = _createModification(groupId, buildArray(admin1, admin2));

        // Verify: member-add events are emitted for both unique addresses.
        vm.expectEmit(true, true, false, true);
        emit IOrganizationGroups.GroupMemberAdded(groupId, admin1);
        vm.expectEmit(true, true, false, true);
        emit IOrganizationGroups.GroupMemberAdded(groupId, admin2);

        harness.createGroupViaLibrary(mod);
    }

    /// @dev Verifies duplicate `membersToAdd` entries are idempotent and emit no duplicate member-added events.
    function test_createGroup_duplicateMembersToAdd_idempotentNoDuplicateEvents() public {
        uint256 groupId = 7408;
        address[] memory membersToAdd = new address[](3);
        membersToAdd[0] = admin1;
        membersToAdd[1] = admin1;
        membersToAdd[2] = admin2;

        GroupModification memory mod = _createModification(groupId, membersToAdd);

        vm.recordLogs();
        harness.createGroupViaLibrary(mod);

        // Verify: final state has both members active.
        assertTrue(harness.isGroupMemberViaLibrary(groupId, admin1), "admin1 should be in group");
        assertTrue(harness.isGroupMemberViaLibrary(groupId, admin2), "admin2 should be in group");

        // Verify: duplicate admin1 entry produced only one `GroupMemberAdded` event.
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 memberAddedTopic = keccak256("GroupMemberAdded(uint256,address)");
        uint256 memberAddedCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == memberAddedTopic) {
                memberAddedCount++;
            }
        }
        assertEq(memberAddedCount, 2, "duplicates should not emit duplicate GroupMemberAdded events");
    }

    /// @dev Verifies adding the zero address reverts with `InvalidMemberAddress`.
    function test_createGroup_membersToAddContainsZeroAddress_revertsInvalidMemberAddress() public {
        uint256 groupId = 7409;
        GroupModification memory mod = _createModification(groupId, buildArray(address(0)));

        // Verify: zero address is always invalid as a member.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationMembers.InvalidMemberAddress.selector, address(0)));
        harness.createGroupViaLibrary(mod);
    }

    /// @dev Verifies desired behavior that non-organization members cannot be added at create-time.
    function test_createGroup_nonOrganizationMember_revertsMemberDoesNotExist() public {
        uint256 groupId = 7410;
        address nonMember = address(0xF410);
        _setMembers(buildArray(admin1), true);

        GroupModification memory mod = _createModification(groupId, buildArray(admin1, nonMember));

        // Desired behavior: all added group members must be current org members.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationMembers.MemberDoesNotExist.selector, nonMember));
        harness.createGroupViaLibrary(mod);
    }

    /// @dev Verifies desired behavior that mixed valid+invalid members revert atomically with no partial writes/events.
    function test_createGroup_mixedValidAndInvalidMembers_revertsAtomically() public {
        uint256 groupId = 7411;
        address nonMember = address(0xF411);
        _setMembers(buildArray(admin1), true);

        GroupModification memory mod = _createModification(groupId, buildArray(admin1, nonMember));

        vm.expectRevert(abi.encodeWithSelector(IOrganizationMembers.MemberDoesNotExist.selector, nonMember));
        harness.createGroupViaLibrary(mod);

        // Desired behavior: no partial state writes from valid prefix members.
        assertFalse(harness.isGroupViaLibrary(groupId), "group should not be created on mixed-member failure");
        assertFalse(harness.isGroupMemberViaLibrary(groupId, admin1), "valid prefix member write should rollback");
    }

    /// @dev Verifies boundary create path supports `groupId = 0`.
    function test_createGroup_boundaryGroupIdZero_supported() public {
        uint256 groupId = 0;
        GroupModification memory mod = _createModification(groupId, buildArray(admin1));

        // Call: create boundary-ID group.
        harness.createGroupViaLibrary(mod);

        // Verify: boundary group ID is active with expected membership.
        assertTrue(harness.isGroupViaLibrary(groupId), "groupId=0 should be active");
        assertTrue(harness.isGroupMemberViaLibrary(groupId, admin1), "member should be added to groupId=0");
    }

    /// @dev Verifies boundary create path supports `groupId = type(uint256).max`.
    function test_createGroup_boundaryGroupIdMax_supported() public {
        uint256 groupId = type(uint256).max;
        GroupModification memory mod = _createModification(groupId, buildArray(admin1));

        // Call: create boundary-ID group.
        harness.createGroupViaLibrary(mod);

        // Verify: boundary group ID is active with expected membership.
        assertTrue(harness.isGroupViaLibrary(groupId), "groupId=max should be active");
        assertTrue(harness.isGroupMemberViaLibrary(groupId, admin1), "member should be added to groupId=max");
    }
}
