// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Vm} from "forge-std/Vm.sol";

import {IOrganizationMembers} from "interfaces/organization/IOrganizationMembers.sol";
import {
    LibOrganizationGroupsSuiteBase
} from "test/organization/libraries/LibOrganizationGroups/LibOrganizationGroupsSuiteBase.sol";

/**
 * @dev Unit tests for `LibOrganizationGroups._addGroupMembers` via harness wrapper.
 */
contract LibOrganizationGroupsAddGroupMembersTest is LibOrganizationGroupsSuiteBase {
    /// @dev Verifies new members are added and marked true in `isGroupMember`.
    function test_addGroupMembers_addsNewMembers_setsMembershipTrue() public {
        uint256 groupId = 7701;
        groupsStateHarness.setGroupStatus(groupId, true);

        // Call: add two members.
        harness.addGroupMembersViaLibrary(groupId, buildArray(admin1, admin2));

        // Verify: both member bits are set.
        assertTrue(harness.isGroupMemberViaLibrary(groupId, admin1), "admin1 should be added");
        assertTrue(harness.isGroupMemberViaLibrary(groupId, admin2), "admin2 should be added");
    }

    /// @dev Verifies a `GroupMemberAdded` event is emitted for each newly-added member.
    function test_addGroupMembers_emitsEventPerNewMember() public {
        uint256 groupId = 7702;
        groupsStateHarness.setGroupStatus(groupId, true);

        vm.recordLogs();
        harness.addGroupMembersViaLibrary(groupId, buildArray(admin1, admin2));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 addedTopic = keccak256("GroupMemberAdded(uint256,address)");
        uint256 addedEventCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(harness) && logs[i].topics.length > 0 && logs[i].topics[0] == addedTopic) {
                addedEventCount++;
            }
        }
        assertEq(addedEventCount, 2, "two unique additions should emit two GroupMemberAdded events");
    }

    /// @dev Verifies duplicate members are idempotent with no duplicate events.
    function test_addGroupMembers_duplicateMembers_idempotentAndNoDuplicateEvents() public {
        uint256 groupId = 7703;
        groupsStateHarness.setGroupStatus(groupId, true);

        address[] memory members = new address[](3);
        members[0] = admin1;
        members[1] = admin1;
        members[2] = admin2;

        vm.recordLogs();
        harness.addGroupMembersViaLibrary(groupId, members);

        // Verify: state reflects unique set only.
        assertTrue(harness.isGroupMemberViaLibrary(groupId, admin1), "admin1 should be active");
        assertTrue(harness.isGroupMemberViaLibrary(groupId, admin2), "admin2 should be active");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 addedTopic = keccak256("GroupMemberAdded(uint256,address)");
        uint256 addedEventCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == addedTopic) {
                addedEventCount++;
            }
        }
        assertEq(addedEventCount, 2, "duplicate additions should not emit duplicate events");
    }

    /// @dev Verifies zero-address additions revert with `InvalidMemberAddress`.
    function test_addGroupMembers_zeroAddress_revertsInvalidMemberAddress() public {
        uint256 groupId = 7704;
        groupsStateHarness.setGroupStatus(groupId, true);

        // Verify: zero address should always revert.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationMembers.InvalidMemberAddress.selector, address(0)));
        harness.addGroupMembersViaLibrary(groupId, buildArray(address(0)));
    }

    /// @dev Verifies desired behavior that non-organization members revert with `MemberDoesNotExist`.
    function test_addGroupMembers_nonOrganizationMember_revertsMemberDoesNotExist() public {
        uint256 groupId = 7705;
        address nonMember = address(0xF705);
        groupsStateHarness.setGroupStatus(groupId, true);
        _setMembers(buildArray(admin1), true);

        // Desired behavior: add-path should enforce organization membership.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationMembers.MemberDoesNotExist.selector, nonMember));
        harness.addGroupMembersViaLibrary(groupId, buildArray(nonMember));
    }

    /// @dev Verifies desired behavior that mixed valid+invalid additions revert atomically.
    function test_addGroupMembers_mixedValidAndInvalidMembers_revertsAtomically() public {
        uint256 groupId = 7706;
        address nonMember = address(0xF706);
        groupsStateHarness.setGroupStatus(groupId, true);
        _setMembers(buildArray(admin1), true);

        vm.expectRevert(abi.encodeWithSelector(IOrganizationMembers.MemberDoesNotExist.selector, nonMember));
        harness.addGroupMembersViaLibrary(groupId, buildArray(admin1, nonMember));

        // Desired behavior: valid-prefix writes should rollback.
        assertFalse(harness.isGroupMemberViaLibrary(groupId, admin1), "valid-prefix member write should rollback");
    }

    /// @dev Verifies desired behavior that org-removed addresses are invalid for group adds.
    function test_addGroupMembers_removedOrgMember_revertsMemberDoesNotExist() public {
        uint256 groupId = 7707;
        groupsStateHarness.setGroupStatus(groupId, true);
        groupsStateHarness.setMemberStatus(admin1, false);

        // Desired behavior: non-member (removed) addresses should be rejected.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationMembers.MemberDoesNotExist.selector, admin1));
        harness.addGroupMembersViaLibrary(groupId, buildArray(admin1));
    }
}
