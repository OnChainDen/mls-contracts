// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Vm} from "forge-std/Vm.sol";

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {IOrganizationMembers} from "interfaces/organization/IOrganizationMembers.sol";
import {
    OrganizationMembersBaseSuiteBase
} from "test/organization/base/OrganizationMembersBase/OrganizationMembersBaseSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Unit tests for `OrganizationMembersBase.modifyMembers` behavior.
 */
contract OrganizationMembersBaseModifyMembersTest is OrganizationMembersBaseSuiteBase {
    /**
     * @dev Executes `modifyMembers` as guardian with approval signatures from the provided keys.
     */
    function _executeModifyMembers(
        address[] memory membersToAdd,
        address[] memory membersToRemove,
        uint256 salt,
        uint256[] memory privateKeys
    ) internal {
        (AdminAuthParams memory auth,) = _buildModifyMembersAuth({
            membersToAdd: membersToAdd,
            membersToRemove: membersToRemove,
            salt: salt,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: privateKeys
        });

        vm.prank(GUARDIAN);
        harness.modifyMembers({membersToAdd: membersToAdd, membersToRemove: membersToRemove, authParams: auth});
    }

    /**
     * @dev Executes `modifyMembers` as guardian using the default single-admin signer.
     */
    function _executeModifyMembers(address[] memory membersToAdd, address[] memory membersToRemove, uint256 salt)
        internal
    {
        _executeModifyMembers({
            membersToAdd: membersToAdd,
            membersToRemove: membersToRemove,
            salt: salt,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
    }

    /**
     * @dev Executes `modifyAdmins` as guardian with approval signatures from the provided keys.
     */
    function _executeModifyAdmins(
        address[] memory adminsToAdd,
        address[] memory adminsToRemove,
        uint256 newVotingThreshold,
        uint256 salt,
        uint256[] memory privateKeys
    ) internal {
        (AdminAuthParams memory auth,) = _buildModifyAdminsAuth({
            adminsToAdd: adminsToAdd,
            adminsToRemove: adminsToRemove,
            newVotingThreshold: newVotingThreshold,
            salt: salt,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: privateKeys
        });

        vm.prank(GUARDIAN);
        harness.modifyAdmins({
            adminsToAdd: adminsToAdd,
            adminsToRemove: adminsToRemove,
            newVotingThreshold: newVotingThreshold,
            authParams: auth
        });
    }

    /// @dev Verifies that adding one non-zero member succeeds and marks it as a member.
    function test_modifyMembers_addSingleMember_succeedsAndMarksMember() public {
        address candidate = address(0x401);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Call: invoke `modifyMembers` through the base-contract wrapper.
        _executeModifyMembers({
            membersToAdd: buildArray(candidate), membersToRemove: buildEmptyAddressArray(), salt: 4101
        });

        // Verify: added address should now be a member.
        assertTrue(harness.isMember(candidate), "candidate should be a member after add");
    }

    /// @dev Verifies that adding multiple non-zero members succeeds for each entry.
    function test_modifyMembers_addMultipleMembers_allAdded() public {
        address memberA = address(0x402);
        address memberB = address(0x403);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Call: invoke `modifyMembers` through the base-contract wrapper.
        _executeModifyMembers({
            membersToAdd: buildArray(memberA, memberB), membersToRemove: buildEmptyAddressArray(), salt: 4102
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

        (AdminAuthParams memory auth,) = _buildModifyMembersAuth({
            membersToAdd: buildArray(address(0)),
            membersToRemove: buildEmptyAddressArray(),
            salt: 4103,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: zero-address adds must revert.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationMembers.InvalidMemberAddress.selector, address(0)));
        vm.prank(GUARDIAN);
        // Call: invoke `modifyMembers` through the base-contract wrapper.
        harness.modifyMembers({
            membersToAdd: buildArray(address(0)), membersToRemove: buildEmptyAddressArray(), authParams: auth
        });
    }

    /// @dev Verifies that adding an already-existing member is idempotent and does not revert.
    function test_modifyMembers_addExistingMember_noopDoesNotRevert() public {
        address existingMember = address(0x404);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1, existingMember), admins: buildArray(admin1), threshold: 1});

        // Call: invoke `modifyMembers` through the base-contract wrapper.
        _executeModifyMembers({
            membersToAdd: buildArray(existingMember), membersToRemove: buildEmptyAddressArray(), salt: 4104
        });

        // Verify: idempotent add keeps membership true.
        assertTrue(harness.isMember(existingMember), "existing member should remain a member");
    }

    /// @dev Verifies that successful additions emit `MemberAdded` once per added member.
    function test_modifyMembers_successfulAdd_emitsMemberAdded() public {
        address candidate = address(0x405);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Verify: expect one MemberAdded event for the new member.
        vm.expectEmit(true, false, false, true);
        emit IOrganizationMembers.MemberAdded(candidate);

        // Call: invoke `modifyMembers` through the base-contract wrapper.
        _executeModifyMembers({
            membersToAdd: buildArray(candidate), membersToRemove: buildEmptyAddressArray(), salt: 4105
        });
    }

    /// @dev Verifies that adding an existing member does not emit `MemberAdded` again.
    function test_modifyMembers_addExistingMember_doesNotEmitMemberAddedAgain() public {
        address existingMember = address(0x406);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1, existingMember), admins: buildArray(admin1), threshold: 1});

        vm.recordLogs();
        // Call: invoke `modifyMembers` through the base-contract wrapper.
        _executeModifyMembers({
            membersToAdd: buildArray(existingMember), membersToRemove: buildEmptyAddressArray(), salt: 4106
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
        address memberToRemove = address(0x407);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1, memberToRemove), admins: buildArray(admin1), threshold: 1});

        // Call: invoke `modifyMembers` through the base-contract wrapper.
        _executeModifyMembers({
            membersToAdd: buildEmptyAddressArray(), membersToRemove: buildArray(memberToRemove), salt: 4107
        });

        // Verify: removed address should no longer be a member.
        assertFalse(harness.isMember(memberToRemove), "removed member should no longer be a member");
    }

    /// @dev Verifies that removing multiple existing non-admin members succeeds.
    function test_modifyMembers_removeMultipleMembers_allRemoved() public {
        address memberA = address(0x408);
        address memberB = address(0x409);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1, memberA, memberB), admins: buildArray(admin1), threshold: 1});

        // Call: invoke `modifyMembers` through the base-contract wrapper.
        _executeModifyMembers({
            membersToAdd: buildEmptyAddressArray(), membersToRemove: buildArray(memberA, memberB), salt: 4108
        });

        // Verify: both removed addresses should no longer be members.
        assertFalse(harness.isMember(memberA), "memberA should be removed");
        // Verify: both removed addresses should no longer be members.
        assertFalse(harness.isMember(memberB), "memberB should be removed");
    }

    /// @dev Verifies that removing a non-existent member is an idempotent no-op and does not revert.
    function test_modifyMembers_removeNonExistentMember_noopDoesNotRevert() public {
        address nonMember = address(0x40A);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Call: invoke `modifyMembers` through the base-contract wrapper.
        _executeModifyMembers({
            membersToAdd: buildEmptyAddressArray(), membersToRemove: buildArray(nonMember), salt: 4109
        });

        // Verify: non-member should remain non-member after idempotent removal.
        assertFalse(harness.isMember(nonMember), "non-member should remain non-member");
    }

    /// @dev Verifies that removing an address that is still an admin reverts with `MemberIsAdmin`.
    function test_modifyMembers_removeAdminMember_revertsMemberIsAdmin() public {
        address adminMember = address(0x40B);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({
            members: buildArray(admin1, adminMember), admins: buildArray(admin1, adminMember), threshold: 1
        });

        (AdminAuthParams memory auth,) = _buildModifyMembersAuth({
            membersToAdd: buildEmptyAddressArray(),
            membersToRemove: buildArray(adminMember),
            salt: 4110,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: removing an admin from members must revert.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationMembers.MemberIsAdmin.selector, adminMember));
        vm.prank(GUARDIAN);
        // Call: invoke `modifyMembers` through the base-contract wrapper.
        harness.modifyMembers({
            membersToAdd: buildEmptyAddressArray(), membersToRemove: buildArray(adminMember), authParams: auth
        });
    }

    /// @dev Verifies that removing a member who is in a group still succeeds (group membership is not checked).
    function test_modifyMembers_removeMemberInGroup_succeeds() public {
        uint256 groupId = 77;
        address groupedMember = address(0x40C);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1, groupedMember), admins: buildArray(admin1), threshold: 1});
        // Setup: mark the target as a group member as well.
        stateHarness.setGroupStatus(groupId, true);
        stateHarness.setGroupMemberStatus(groupId, groupedMember, true);

        // Call: invoke `modifyMembers` through the base-contract wrapper.
        _executeModifyMembers({
            membersToAdd: buildEmptyAddressArray(), membersToRemove: buildArray(groupedMember), salt: 4111
        });

        // Verify: member removal should succeed regardless of group membership.
        assertFalse(harness.isMember(groupedMember), "grouped member should be removable");
        // Verify: group-membership mapping remains untouched by member removal.
        assertTrue(stateHarness.getGroupMemberStatus(groupId, groupedMember), "group status should be unchanged");
    }

    /// @dev Verifies that successful removals emit `MemberRemoved` once per removed member.
    function test_modifyMembers_successfulRemove_emitsMemberRemoved() public {
        address memberToRemove = address(0x40D);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1, memberToRemove), admins: buildArray(admin1), threshold: 1});

        // Verify: expect one MemberRemoved event for the removed member.
        vm.expectEmit(true, false, false, true);
        emit IOrganizationMembers.MemberRemoved(memberToRemove);

        // Call: invoke `modifyMembers` through the base-contract wrapper.
        _executeModifyMembers({
            membersToAdd: buildEmptyAddressArray(), membersToRemove: buildArray(memberToRemove), salt: 4112
        });
    }

    /// @dev Verifies that removing a non-existent member does not emit `MemberRemoved`.
    function test_modifyMembers_removeNonExistentMember_doesNotEmitMemberRemoved() public {
        address nonMember = address(0x40E);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        vm.recordLogs();
        // Call: invoke `modifyMembers` through the base-contract wrapper.
        _executeModifyMembers({
            membersToAdd: buildEmptyAddressArray(), membersToRemove: buildArray(nonMember), salt: 4113
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
        address adminMember = address(0x40F);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({
            members: buildArray(admin1, adminMember), admins: buildArray(admin1, adminMember), threshold: 1
        });

        (AdminAuthParams memory auth,) = _buildModifyMembersAuth({
            membersToAdd: buildEmptyAddressArray(),
            membersToRemove: buildArray(adminMember),
            salt: 4114,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: removing a member with active admin status must revert.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationMembers.MemberIsAdmin.selector, adminMember));
        vm.prank(GUARDIAN);
        // Call: invoke `modifyMembers` through the base-contract wrapper.
        harness.modifyMembers({
            membersToAdd: buildEmptyAddressArray(), membersToRemove: buildArray(adminMember), authParams: auth
        });
    }

    /// @dev Verifies that once admin status is removed, the same address can be removed from members.
    function test_modifyMembers_afterDemotion_memberCanBeRemoved() public {
        address adminMember = address(0x410);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({
            members: buildArray(admin1, adminMember), admins: buildArray(admin1, adminMember), threshold: 1
        });

        // Call: first remove admin status via the admin base-contract path.
        _executeModifyAdmins({
            adminsToAdd: buildEmptyAddressArray(),
            adminsToRemove: buildArray(adminMember),
            newVotingThreshold: 1,
            salt: 5115,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: the account should no longer be an admin.
        assertFalse(stateHarness.getAdminStatus(adminMember), "address should no longer be admin");

        // Call: then remove the member.
        _executeModifyMembers({
            membersToAdd: buildEmptyAddressArray(), membersToRemove: buildArray(adminMember), salt: 4115
        });

        // Verify: the address should no longer be a member.
        assertFalse(harness.isMember(adminMember), "address should no longer be member");
    }

    /// @dev Verifies integration behavior: admin additions require target addresses to already be members.
    function test_modifyAdmins_integrationAddNonMember_revertsAdminNotMember() public {
        address nonMember = address(0x411);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        (AdminAuthParams memory auth,) = _buildModifyAdminsAuth({
            adminsToAdd: buildArray(nonMember),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            salt: 5116,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: admin add for non-member must revert.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.AdminNotMember.selector, nonMember));
        vm.prank(GUARDIAN);
        // Call: invoke admin base-contract path to validate cross-module invariant.
        harness.modifyAdmins({
            adminsToAdd: buildArray(nonMember),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            authParams: auth
        });
    }

    /// @dev Verifies that adding and removing different members in the same call updates both states and emits both
    /// events.
    function test_modifyMembers_addAndRemoveDifferentMembers_sameCall_succeeds() public {
        address memberToAdd = address(0x412);
        address memberToRemove = address(0x413);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1, memberToRemove), admins: buildArray(admin1), threshold: 1});

        // Verify: expect add/remove events for the successful mixed mutation.
        vm.expectEmit(true, false, false, true);
        emit IOrganizationMembers.MemberAdded(memberToAdd);
        // Verify: expect add/remove events for the successful mixed mutation.
        vm.expectEmit(true, false, false, true);
        emit IOrganizationMembers.MemberRemoved(memberToRemove);

        // Call: invoke `modifyMembers` through the base-contract wrapper.
        _executeModifyMembers({
            membersToAdd: buildArray(memberToAdd), membersToRemove: buildArray(memberToRemove), salt: 4116
        });

        // Verify: add target should be member and remove target should not.
        assertTrue(harness.isMember(memberToAdd), "added member should be present");
        // Verify: add target should be member and remove target should not.
        assertFalse(harness.isMember(memberToRemove), "removed member should be absent");
    }

    /// @dev Verifies that empty add/remove arrays are a no-op that succeeds and emits no member events.
    function test_modifyMembers_emptyAddAndRemoveArrays_noopSucceeds() public {
        address untouchedMember = address(0x414);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1, untouchedMember), admins: buildArray(admin1), threshold: 1});

        vm.recordLogs();
        // Call: invoke `modifyMembers` through the base-contract wrapper.
        _executeModifyMembers({
            membersToAdd: buildEmptyAddressArray(), membersToRemove: buildEmptyAddressArray(), salt: 4117
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
        address candidate = address(0x415);
        // Setup: candidate starts as a non-member and is included in both add/remove arrays.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Call: invoke `modifyMembers` through the base-contract wrapper.
        _executeModifyMembers({membersToAdd: buildArray(candidate), membersToRemove: buildArray(candidate), salt: 4118});

        // Verify: address should end as non-member after add-then-remove processing.
        assertFalse(harness.isMember(candidate), "candidate should be removed at end of call");
    }

    /// @dev Verifies that when the same non-member is added and removed in one call, both events are emitted in-order.
    function test_modifyMembers_addThenRemoveSameAddress_sameCall_emitsMemberAddedAndMemberRemoved() public {
        address candidate = address(0x416);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Verify: add/remove events should both be emitted for the same address.
        vm.expectEmit(true, false, false, true);
        emit IOrganizationMembers.MemberAdded(candidate);
        // Verify: add/remove events should both be emitted for the same address.
        vm.expectEmit(true, false, false, true);
        emit IOrganizationMembers.MemberRemoved(candidate);

        // Call: invoke `modifyMembers` through the base-contract wrapper.
        _executeModifyMembers({membersToAdd: buildArray(candidate), membersToRemove: buildArray(candidate), salt: 4119});

        // Verify: final state remains non-member after add-then-remove processing.
        assertFalse(harness.isMember(candidate), "candidate should end non-member");
    }

    /// @dev Verifies that `modifyMembers` rejects non-guardian callers via `onlyGuardian`.
    function test_modifyMembers_nonGuardianCaller_revertsOnlyGuardian() public {
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        AdminAuthParams memory auth;
        // Verify: non-guardian caller must be rejected before auth validation runs.
        _expectOnlyGuardianRevert(NON_GUARDIAN);
        vm.prank(NON_GUARDIAN);
        // Call: invoke `modifyMembers` through the base-contract wrapper.
        harness.modifyMembers({
            membersToAdd: buildEmptyAddressArray(), membersToRemove: buildEmptyAddressArray(), authParams: auth
        });
    }

    /// @dev Verifies that guardian calls with valid admin signatures succeed.
    function test_modifyMembers_guardianWithValidAuth_succeeds() public {
        address memberToAdd = address(0x401);
        // Setup: require two admin signatures for execution.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});

        (AdminAuthParams memory auth,) = _buildModifyMembersAuth({
            membersToAdd: buildArray(memberToAdd),
            membersToRemove: buildEmptyAddressArray(),
            salt: 4101,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1, ADMIN_PK_2)
        });

        vm.prank(GUARDIAN);
        // Call: invoke `modifyMembers` through the base-contract wrapper.
        harness.modifyMembers({
            membersToAdd: buildArray(memberToAdd), membersToRemove: buildEmptyAddressArray(), authParams: auth
        });

        // Verify: member should be added after authorized execution.
        assertTrue(harness.isMember(memberToAdd), "member should be added by authorized call");
    }

    /// @dev Verifies that guardian calls with insufficient signatures revert.
    function test_modifyMembers_insufficientAdminSignatures_reverts() public {
        address memberToAdd = address(0x402);
        // Setup: require two signatures but provide one.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});

        (AdminAuthParams memory auth, bytes memory operationData) = _buildModifyMembersAuth({
            membersToAdd: buildArray(memberToAdd),
            membersToRemove: buildEmptyAddressArray(),
            salt: 4102,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: authorization should fail when valid signer count is below threshold.
        vm.expectRevert(IOrganizationAdmin.InsufficientAdminAuthorization.selector);
        vm.prank(GUARDIAN);
        // Call: invoke `modifyMembers` through the base-contract wrapper.
        harness.modifyMembers({
            membersToAdd: buildArray(memberToAdd), membersToRemove: buildEmptyAddressArray(), authParams: auth
        });

        // Verify: failed execution should not leave nonce consumed.
        uint256 nonce = harness.computeNonce({
            operationType: OperationType.ModifyMembers, operationData: operationData, salt: 4102
        });
        assertFalse(harness.getUsedNonce(nonce), "failed auth should not consume nonce");
    }
}
