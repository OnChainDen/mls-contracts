// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Vm} from "forge-std/Vm.sol";

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {IOrganizationMembers} from "interfaces/organization/IOrganizationMembers.sol";
import {
    LibOrganizationMembersSuiteBase
} from "test/organization/libraries/LibOrganizationMembers/LibOrganizationMembersSuiteBase.sol";

/**
 * @dev Unit tests for `LibOrganizationMembers.modifyMembers`.
 */
contract LibOrganizationMembersModifyMembersTest is LibOrganizationMembersSuiteBase {
    /// @dev Verifies that adding one non-zero member succeeds and marks it as a member.
    function test_modifyMembers_addSingleMember_succeedsAndMarksMember() public {
        address candidate = address(0x301);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Call: mutate members via direct library wrapper.
        harness.modifyMembersViaLibrary({
            membersToAdd: buildArray(candidate), membersToRemove: buildEmptyAddressArray()
        });

        // Verify: added address should now be a member.
        assertTrue(harness.isMember(candidate), "candidate should be a member after add");
    }

    /// @dev Verifies that adding multiple non-zero members succeeds for each entry.
    function test_modifyMembers_addMultipleMembers_allAdded() public {
        address memberA = address(0x302);
        address memberB = address(0x303);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Call: mutate members via direct library wrapper.
        harness.modifyMembersViaLibrary({
            membersToAdd: buildArray(memberA, memberB), membersToRemove: buildEmptyAddressArray()
        });

        // Verify: both addresses should now be members.
        assertTrue(harness.isMember(memberA), "memberA should be a member");
        // Verify: both addresses should now be members.
        assertTrue(harness.isMember(memberB), "memberB should be a member");
    }

    /// @dev Verifies that adding `address(0)` reverts with `InvalidMemberAddress`.
    function test_modifyMembers_addZeroAddress_revertsInvalidMemberAddress() public {
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Verify: zero-address adds must revert.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationMembers.InvalidMemberAddress.selector, address(0)));
        // Call: mutate members via direct library wrapper.
        harness.modifyMembersViaLibrary({
            membersToAdd: buildArray(address(0)), membersToRemove: buildEmptyAddressArray()
        });
    }

    /// @dev Verifies that adding an already-existing member is idempotent and does not revert.
    function test_modifyMembers_addExistingMember_noopDoesNotRevert() public {
        address existingMember = address(0x304);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1, existingMember), admins: buildArray(admin1), threshold: 1});

        // Call: mutate members via direct library wrapper.
        harness.modifyMembersViaLibrary({
            membersToAdd: buildArray(existingMember), membersToRemove: buildEmptyAddressArray()
        });

        // Verify: idempotent add keeps membership true.
        assertTrue(harness.isMember(existingMember), "existing member should remain a member");
    }

    /// @dev Verifies that successful additions emit `MemberAdded` once per added member.
    function test_modifyMembers_successfulAdd_emitsMemberAdded() public {
        address candidate = address(0x305);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Verify: expect one MemberAdded event for the new member.
        vm.expectEmit(true, false, false, true);
        emit IOrganizationMembers.MemberAdded(candidate);

        // Call: mutate members via direct library wrapper.
        harness.modifyMembersViaLibrary({
            membersToAdd: buildArray(candidate), membersToRemove: buildEmptyAddressArray()
        });
    }

    /// @dev Verifies that adding an existing member does not emit `MemberAdded` again.
    function test_modifyMembers_addExistingMember_doesNotEmitMemberAddedAgain() public {
        address existingMember = address(0x306);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1, existingMember), admins: buildArray(admin1), threshold: 1});

        vm.recordLogs();
        // Call: mutate members via direct library wrapper.
        harness.modifyMembersViaLibrary({
            membersToAdd: buildArray(existingMember), membersToRemove: buildEmptyAddressArray()
        });

        Vm.Log[] memory actualLogs = vm.getRecordedLogs();
        bytes32 memberAddedSig = keccak256("MemberAdded(address)");
        for (uint256 i = 0; i < actualLogs.length; i++) {
            // Verify: no new MemberAdded event should be emitted for idempotent add.
            assertTrue(actualLogs[i].topics[0] != memberAddedSig, "duplicate add should not emit MemberAdded");
        }
    }

    /// @dev Verifies that removing an existing non-admin member succeeds and clears membership.
    function test_modifyMembers_removeExistingMember_succeedsAndClearsMembership() public {
        address memberToRemove = address(0x307);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1, memberToRemove), admins: buildArray(admin1), threshold: 1});

        // Call: mutate members via direct library wrapper.
        harness.modifyMembersViaLibrary({
            membersToAdd: buildEmptyAddressArray(), membersToRemove: buildArray(memberToRemove)
        });

        // Verify: removed address should no longer be a member.
        assertFalse(harness.isMember(memberToRemove), "removed member should no longer be a member");
    }

    /// @dev Verifies that removing multiple existing non-admin members succeeds.
    function test_modifyMembers_removeMultipleMembers_allRemoved() public {
        address memberA = address(0x308);
        address memberB = address(0x309);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1, memberA, memberB), admins: buildArray(admin1), threshold: 1});

        // Call: mutate members via direct library wrapper.
        harness.modifyMembersViaLibrary({
            membersToAdd: buildEmptyAddressArray(), membersToRemove: buildArray(memberA, memberB)
        });

        // Verify: both removed addresses should no longer be members.
        assertFalse(harness.isMember(memberA), "memberA should be removed");
        // Verify: both removed addresses should no longer be members.
        assertFalse(harness.isMember(memberB), "memberB should be removed");
    }

    /// @dev Verifies that removing a non-existent member is an idempotent no-op and does not revert.
    function test_modifyMembers_removeNonExistentMember_noopDoesNotRevert() public {
        address nonMember = address(0x30A);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Call: mutate members via direct library wrapper.
        harness.modifyMembersViaLibrary({
            membersToAdd: buildEmptyAddressArray(), membersToRemove: buildArray(nonMember)
        });

        // Verify: non-member should remain non-member after idempotent removal.
        assertFalse(harness.isMember(nonMember), "non-member should remain non-member");
    }

    /// @dev Verifies that removing an address that is still an admin reverts with `MemberIsAdmin`.
    function test_modifyMembers_removeAdminMember_revertsMemberIsAdmin() public {
        address adminMember = address(0x30B);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({
            members: buildArray(admin1, adminMember), admins: buildArray(admin1, adminMember), threshold: 1
        });

        // Verify: removing an admin from members must revert.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationMembers.MemberIsAdmin.selector, adminMember));
        // Call: mutate members via direct library wrapper.
        harness.modifyMembersViaLibrary({
            membersToAdd: buildEmptyAddressArray(), membersToRemove: buildArray(adminMember)
        });
    }

    /// @dev Verifies that removing a member who is in a group still succeeds (group membership is not checked).
    function test_modifyMembers_removeMemberInGroup_succeeds() public {
        uint256 groupId = 77;
        address groupedMember = address(0x30C);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1, groupedMember), admins: buildArray(admin1), threshold: 1});
        // Setup: mark the target as a group member as well.
        stateHarness.setGroupStatus(groupId, true);
        stateHarness.setGroupMemberStatus(groupId, groupedMember, true);

        // Call: mutate members via direct library wrapper.
        harness.modifyMembersViaLibrary({
            membersToAdd: buildEmptyAddressArray(), membersToRemove: buildArray(groupedMember)
        });

        // Verify: member removal should succeed regardless of group membership.
        assertFalse(harness.isMember(groupedMember), "grouped member should be removable");
        // Verify: group-membership mapping remains untouched by member removal.
        assertTrue(stateHarness.getGroupMemberStatus(groupId, groupedMember), "group status should be unchanged");
    }

    /// @dev Verifies that successful removals emit `MemberRemoved` once per removed member.
    function test_modifyMembers_successfulRemove_emitsMemberRemoved() public {
        address memberToRemove = address(0x30D);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1, memberToRemove), admins: buildArray(admin1), threshold: 1});

        // Verify: expect one MemberRemoved event for the removed member.
        vm.expectEmit(true, false, false, true);
        emit IOrganizationMembers.MemberRemoved(memberToRemove);

        // Call: mutate members via direct library wrapper.
        harness.modifyMembersViaLibrary({
            membersToAdd: buildEmptyAddressArray(), membersToRemove: buildArray(memberToRemove)
        });
    }

    /// @dev Verifies that removing a non-existent member does not emit `MemberRemoved`.
    function test_modifyMembers_removeNonExistentMember_doesNotEmitMemberRemoved() public {
        address nonMember = address(0x30E);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        vm.recordLogs();
        // Call: mutate members via direct library wrapper.
        harness.modifyMembersViaLibrary({
            membersToAdd: buildEmptyAddressArray(), membersToRemove: buildArray(nonMember)
        });

        Vm.Log[] memory actualLogs = vm.getRecordedLogs();
        bytes32 memberRemovedSig = keccak256("MemberRemoved(address)");
        for (uint256 i = 0; i < actualLogs.length; i++) {
            // Verify: idempotent remove of non-member should not emit MemberRemoved.
            assertTrue(actualLogs[i].topics[0] != memberRemovedSig, "non-member removal should not emit MemberRemoved");
        }
    }

    /// @dev Verifies again that an admin cannot be removed from members until admin status is removed.
    function test_modifyMembers_adminMustBeDemotedBeforeMemberRemoval() public {
        address adminMember = address(0x30F);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({
            members: buildArray(admin1, adminMember), admins: buildArray(admin1, adminMember), threshold: 1
        });

        // Verify: removing a member with active admin status must revert.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationMembers.MemberIsAdmin.selector, adminMember));
        // Call: mutate members via direct library wrapper.
        harness.modifyMembersViaLibrary({
            membersToAdd: buildEmptyAddressArray(), membersToRemove: buildArray(adminMember)
        });
    }

    /// @dev Verifies that once admin status is removed, the same address can be removed from members.
    function test_modifyMembers_afterDemotion_memberCanBeRemoved() public {
        address adminMember = address(0x310);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({
            members: buildArray(admin1, adminMember), admins: buildArray(admin1, adminMember), threshold: 1
        });

        // Call: first remove admin status via the admin library path.
        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildArray(adminMember), newVotingThreshold: 1
        });
        // Call: then remove the member.
        harness.modifyMembersViaLibrary({
            membersToAdd: buildEmptyAddressArray(), membersToRemove: buildArray(adminMember)
        });

        // Verify: the address should no longer be admin nor member.
        assertFalse(harness.isAdmin(adminMember), "address should no longer be admin");
        // Verify: the address should no longer be admin nor member.
        assertFalse(harness.isMember(adminMember), "address should no longer be member");
    }

    /// @dev Verifies integration behavior: admin additions require target addresses to already be members.
    function test_modifyAdmins_integrationAddNonMember_revertsAdminNotMember() public {
        address nonMember = address(0x311);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Verify: admin add for non-member must revert.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.AdminNotMember.selector, nonMember));
        // Call: invoke admin mutation path to validate cross-module invariant.
        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildArray(nonMember), adminsToRemove: buildEmptyAddressArray(), newVotingThreshold: 1
        });
    }

    /// @dev Verifies that adding and removing different members in the same call updates both states and emits both
    /// events.
    function test_modifyMembers_addAndRemoveDifferentMembers_sameCall_succeeds() public {
        address memberToAdd = address(0x312);
        address memberToRemove = address(0x313);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1, memberToRemove), admins: buildArray(admin1), threshold: 1});

        // Verify: expect add/remove events for the successful mixed mutation.
        vm.expectEmit(true, false, false, true);
        emit IOrganizationMembers.MemberAdded(memberToAdd);
        // Verify: expect add/remove events for the successful mixed mutation.
        vm.expectEmit(true, false, false, true);
        emit IOrganizationMembers.MemberRemoved(memberToRemove);

        // Call: mutate members via direct library wrapper.
        harness.modifyMembersViaLibrary({
            membersToAdd: buildArray(memberToAdd), membersToRemove: buildArray(memberToRemove)
        });

        // Verify: add target should be member and remove target should not.
        assertTrue(harness.isMember(memberToAdd), "added member should be present");
        // Verify: add target should be member and remove target should not.
        assertFalse(harness.isMember(memberToRemove), "removed member should be absent");
    }

    /// @dev Verifies that empty add/remove arrays are a no-op that succeeds and emits no member events.
    function test_modifyMembers_emptyAddAndRemoveArrays_noopSucceeds() public {
        address untouchedMember = address(0x314);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1, untouchedMember), admins: buildArray(admin1), threshold: 1});

        vm.recordLogs();
        // Call: mutate members via direct library wrapper.
        harness.modifyMembersViaLibrary({
            membersToAdd: buildEmptyAddressArray(), membersToRemove: buildEmptyAddressArray()
        });

        // Verify: pre-existing membership remains unchanged.
        assertTrue(harness.isMember(untouchedMember), "untouched member should remain a member");

        Vm.Log[] memory actualLogs = vm.getRecordedLogs();
        bytes32 memberAddedSig = keccak256("MemberAdded(address)");
        bytes32 memberRemovedSig = keccak256("MemberRemoved(address)");
        for (uint256 i = 0; i < actualLogs.length; i++) {
            // Verify: no member add/remove events should be emitted for empty operations.
            assertTrue(
                actualLogs[i].topics[0] != memberAddedSig && actualLogs[i].topics[0] != memberRemovedSig,
                "empty mutation should not emit member events"
            );
        }
    }

    /// @dev Verifies that adding and removing the same address in one call yields net `not member` (add processed
    /// first).
    function test_modifyMembers_addThenRemoveSameAddress_sameCall_netRemoved() public {
        address candidate = address(0x315);
        // Setup: candidate starts as a non-member and is included in both add/remove arrays.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Call: mutate members via direct library wrapper.
        harness.modifyMembersViaLibrary({membersToAdd: buildArray(candidate), membersToRemove: buildArray(candidate)});

        // Verify: address should end as non-member after add-then-remove processing.
        assertFalse(harness.isMember(candidate), "candidate should be removed at end of call");
    }

    /// @dev Verifies that when the same non-member is added and removed in one call, both events are emitted in-order.
    function test_modifyMembers_addThenRemoveSameAddress_sameCall_emitsMemberAddedAndMemberRemoved() public {
        address candidate = address(0x316);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Verify: add/remove events should both be emitted for the same address.
        vm.expectEmit(true, false, false, true);
        emit IOrganizationMembers.MemberAdded(candidate);
        // Verify: add/remove events should both be emitted for the same address.
        vm.expectEmit(true, false, false, true);
        emit IOrganizationMembers.MemberRemoved(candidate);

        // Call: mutate members via direct library wrapper.
        harness.modifyMembersViaLibrary({membersToAdd: buildArray(candidate), membersToRemove: buildArray(candidate)});

        // Verify: final state remains non-member after add-then-remove processing.
        assertFalse(harness.isMember(candidate), "candidate should end non-member");
    }
}
