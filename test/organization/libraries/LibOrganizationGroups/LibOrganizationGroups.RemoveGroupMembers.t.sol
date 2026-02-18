// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Vm} from "forge-std/Vm.sol";

import {
    LibOrganizationGroupsSuiteBase
} from "test/organization/libraries/LibOrganizationGroups/LibOrganizationGroupsSuiteBase.sol";

/**
 * @dev Unit tests for `LibOrganizationGroups._removeGroupMembers` via harness wrapper.
 */
contract LibOrganizationGroupsRemoveGroupMembersTest is LibOrganizationGroupsSuiteBase {
    /// @dev Verifies removing an existing member sets membership to false.
    function test_removeGroupMembers_existingMember_setsMembershipFalse() public {
        uint256 groupId = 7801;
        groupsStateHarness.setGroupStatus(groupId, true);
        groupsStateHarness.setGroupMemberStatus(groupId, admin1, true);

        // Call: remove active member.
        harness.removeGroupMembersViaLibrary(groupId, buildArray(admin1));

        // Verify: member bit is cleared.
        assertFalse(harness.isGroupMemberViaLibrary(groupId, admin1), "member should be removed");
    }

    /// @dev Verifies removing an existing member emits `GroupMemberRemoved`.
    function test_removeGroupMembers_existingMember_emitsGroupMemberRemoved() public {
        uint256 groupId = 7802;
        groupsStateHarness.setGroupStatus(groupId, true);
        groupsStateHarness.setGroupMemberStatus(groupId, admin1, true);

        vm.recordLogs();
        harness.removeGroupMembersViaLibrary(groupId, buildArray(admin1));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 removedTopic = keccak256("GroupMemberRemoved(uint256,address)");
        uint256 removedEventCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == removedTopic) {
                removedEventCount++;
            }
        }
        assertEq(removedEventCount, 1, "single removal should emit one GroupMemberRemoved event");
    }

    /// @dev Verifies desired behavior that removing a non-member is a no-op with no event.
    function test_removeGroupMembers_nonMember_isNoOpAndEmitsNoEvent() public {
        uint256 groupId = 7803;
        groupsStateHarness.setGroupStatus(groupId, true);
        groupsStateHarness.setGroupMemberStatus(groupId, admin1, true);

        vm.recordLogs();
        harness.removeGroupMembersViaLibrary(groupId, buildArray(admin2));

        // Desired behavior: non-member removal should no-op.
        assertTrue(harness.isGroupMemberViaLibrary(groupId, admin1), "existing member should remain active");
        assertFalse(harness.isGroupMemberViaLibrary(groupId, admin2), "non-member should remain absent");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 removedTopic = keccak256("GroupMemberRemoved(uint256,address)");
        uint256 removedEventCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == removedTopic) {
                removedEventCount++;
            }
        }
        assertEq(removedEventCount, 0, "non-member removal should not emit GroupMemberRemoved");
    }

    /// @dev Verifies desired behavior that removing the same member twice in one call no-ops on second removal.
    function test_removeGroupMembers_sameMemberTwice_secondRemovalNoOpAndSingleEvent() public {
        uint256 groupId = 7804;
        groupsStateHarness.setGroupStatus(groupId, true);
        groupsStateHarness.setGroupMemberStatus(groupId, admin1, true);

        address[] memory membersToRemove = new address[](2);
        membersToRemove[0] = admin1;
        membersToRemove[1] = admin1;

        vm.recordLogs();
        harness.removeGroupMembersViaLibrary(groupId, membersToRemove);

        // Desired behavior: final state is removed and second removal emits nothing.
        assertFalse(harness.isGroupMemberViaLibrary(groupId, admin1), "member should remain removed");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 removedTopic = keccak256("GroupMemberRemoved(uint256,address)");
        uint256 removedEventCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == removedTopic) {
                removedEventCount++;
            }
        }
        assertEq(removedEventCount, 1, "second duplicate removal should not emit an extra event");
    }
}
