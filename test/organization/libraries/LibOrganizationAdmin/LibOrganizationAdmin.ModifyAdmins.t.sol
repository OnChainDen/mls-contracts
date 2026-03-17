// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Vm} from "forge-std/Vm.sol";

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {IOrganizationMembers} from "interfaces/organization/IOrganizationMembers.sol";
import {
    LibOrganizationAdminSuiteBase
} from "test/organization/libraries/LibOrganizationAdmin/LibOrganizationAdminSuiteBase.sol";

/**
 * @dev Unit tests for `LibOrganizationAdmin.modifyAdmins`.
 */
contract LibOrganizationAdminModifyAdminsTest is LibOrganizationAdminSuiteBase {
    /// @dev Verifies that adding one valid member as admin succeeds and increments the admin count.
    function test_modifyAdmins_addOneValidMember_succeedsAndIncrementsCount() public {
        address candidate = address(0x101);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, candidate), admins: buildArray(admin1), threshold: 1});

        // Call: invoke `modifyAdminsViaLibrary` with the prepared add/remove sets and threshold update.

        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildArray(candidate), adminsToRemove: buildEmptyAddressArray(), newVotingThreshold: 1
        });

        // Verify: assert that the address has admin status expected for this branch.

        assertTrue(harness.getAdminStatus(candidate), "candidate should be admin");
        // Verify: assert that admin count matches the expected value.
        assertEq(harness.adminCount(), 2, "admin count should increment");
    }

    /// @dev Verifies that adding multiple valid members as admins succeeds.
    function test_modifyAdmins_addMultipleValidMembers_succeeds() public {
        address candidate1 = address(0x102);
        address candidate2 = address(0x103);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({
            members: buildArray(admin1, candidate1, candidate2), admins: buildArray(admin1), threshold: 1
        });

        // Call: invoke `modifyAdminsViaLibrary` with the prepared add/remove sets and threshold update.

        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildArray(candidate1, candidate2),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 2
        });

        // Verify: assert that the address has admin status expected for this branch.

        assertTrue(harness.getAdminStatus(candidate1), "candidate1 should be admin");
        // Verify: assert that the address has admin status expected for this branch.
        assertTrue(harness.getAdminStatus(candidate2), "candidate2 should be admin");
        // Verify: assert that admin count matches the expected value.
        assertEq(harness.adminCount(), 3, "admin count should be updated");
    }

    /// @dev Verifies that adding the zero address reverts with `InvalidMemberAddress`.
    function test_modifyAdmins_addZeroAddress_revertsInvalidMemberAddress() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert(abi.encodeWithSelector(IOrganizationMembers.InvalidMemberAddress.selector, address(0)));
        // Call: invoke `modifyAdminsViaLibrary` with the prepared add/remove sets and threshold update.
        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildArray(address(0)), adminsToRemove: buildEmptyAddressArray(), newVotingThreshold: 1
        });
    }

    /// @dev Verifies that adding a non-member reverts with `AdminNotMember`.
    function test_LOA_AADMIN_5_modifyAdmins_addNonMember_revertsAdminNotMember() public {
        address nonMember = address(0x104);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.AdminNotMember.selector, nonMember));
        // Call: invoke `modifyAdminsViaLibrary` with the prepared add/remove sets and threshold update.
        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildArray(nonMember), adminsToRemove: buildEmptyAddressArray(), newVotingThreshold: 1
        });
    }

    /// @dev Verifies that adding an existing admin reverts with `AdminAlreadyExists`.
    function test_modifyAdmins_addExistingAdmin_revertsAdminAlreadyExists() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.AdminAlreadyExists.selector, admin1));
        // Call: invoke `modifyAdminsViaLibrary` with the prepared add/remove sets and threshold update.
        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildArray(admin1), adminsToRemove: buildEmptyAddressArray(), newVotingThreshold: 1
        });
    }

    /// @dev Verifies that a duplicate address in the add array reverts with `AdminAlreadyExists` on the second
    /// occurrence.
    function test_modifyAdmins_duplicateInAddArray_revertsAdminAlreadyExists() public {
        address candidate = address(0x105);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, candidate), admins: buildArray(admin1), threshold: 1});

        address[] memory addrs = buildArray(candidate, candidate);
        // Verify: confirm this branch reverts for the intended failure condition.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.AdminAlreadyExists.selector, candidate));
        // Call: invoke `modifyAdminsViaLibrary` with the prepared add/remove sets and threshold update.
        harness.modifyAdminsViaLibrary({
            adminsToAdd: addrs, adminsToRemove: buildEmptyAddressArray(), newVotingThreshold: 1
        });
    }

    /// @dev Verifies that removing an existing admin succeeds and decrements the admin count.
    function test_modifyAdmins_removeExistingAdmin_succeedsAndDecrementsCount() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 1});

        // Call: invoke `modifyAdminsViaLibrary` with the prepared add/remove sets and threshold update.

        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildArray(admin2), newVotingThreshold: 1
        });

        // Verify: assert that the address does not have admin status for this branch.

        assertFalse(harness.getAdminStatus(admin2), "admin2 should be removed");
        // Verify: assert that admin count matches the expected value.
        assertEq(harness.adminCount(), 1, "admin count should decrement");
    }

    /// @dev Verifies that removing multiple existing admins succeeds.
    function test_modifyAdmins_removeMultipleAdmins_succeeds() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({
            members: buildArray(admin1, admin2, admin3), admins: buildArray(admin1, admin2, admin3), threshold: 1
        });

        // Call: invoke `modifyAdminsViaLibrary` with the prepared add/remove sets and threshold update.

        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildArray(admin2, admin3), newVotingThreshold: 1
        });

        // Verify: assert that the address does not have admin status for this branch.

        assertFalse(harness.getAdminStatus(admin2), "admin2 should be removed");
        // Verify: assert that the address does not have admin status for this branch.
        assertFalse(harness.getAdminStatus(admin3), "admin3 should be removed");
        // Verify: assert that admin count matches the expected value.
        assertEq(harness.adminCount(), 1, "admin count should match final set");
    }

    /// @dev Verifies that removing a non-admin reverts with `AdminDoesNotExist`.
    function test_modifyAdmins_removeNonAdmin_revertsAdminDoesNotExist() public {
        address nonAdmin = address(0x106);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, nonAdmin), admins: buildArray(admin1), threshold: 1});

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.AdminDoesNotExist.selector, nonAdmin));
        // Call: invoke `modifyAdminsViaLibrary` with the prepared add/remove sets and threshold update.
        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildArray(nonAdmin), newVotingThreshold: 1
        });
    }

    /// @dev Verifies that removing the zero address reverts with `AdminDoesNotExist`.
    function test_modifyAdmins_removeZeroAddress_revertsAdminDoesNotExist() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.AdminDoesNotExist.selector, address(0)));
        // Call: invoke `modifyAdminsViaLibrary` with the prepared add/remove sets and threshold update.
        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildArray(address(0)), newVotingThreshold: 1
        });
    }

    /// @dev Verifies that a duplicate in the remove array reverts with `AdminDoesNotExist` on the second occurrence.
    function test_modifyAdmins_duplicateInRemoveArray_revertsAdminDoesNotExist() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 1});

        address[] memory removeAddrs = buildArray(admin2, admin2);
        // Verify: confirm this branch reverts for the intended failure condition.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.AdminDoesNotExist.selector, admin2));
        // Call: invoke `modifyAdminsViaLibrary` with the prepared add/remove sets and threshold update.
        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: removeAddrs, newVotingThreshold: 1
        });
    }

    /// @dev Verifies that removing the last admin reverts with `InvalidAdminConfig`.
    function test_LOA_AADMIN_4_modifyAdmins_removeLastAdmin_revertsInvalidAdminConfig() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert(IOrganizationAdmin.InvalidAdminConfig.selector);
        // Call: invoke `modifyAdminsViaLibrary` with the prepared add/remove sets and threshold update.
        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildArray(admin1), newVotingThreshold: 1
        });
    }

    /// @dev Verifies that a zero voting threshold reverts with `InvalidAdminVotingThreshold`.
    function test_modifyAdmins_thresholdZero_revertsInvalidAdminVotingThreshold() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.InvalidAdminVotingThreshold.selector, 0, 1));
        // Call: invoke `modifyAdminsViaLibrary` with the prepared add/remove sets and threshold update.
        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildEmptyAddressArray(), newVotingThreshold: 0
        });
    }

    /// @dev Verifies that a voting threshold exceeding the final admin count reverts with
    /// `InvalidAdminVotingThreshold`.
    function test_modifyAdmins_thresholdGreaterThanFinalCount_revertsInvalidAdminVotingThreshold() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.InvalidAdminVotingThreshold.selector, 2, 1));
        // Call: invoke `modifyAdminsViaLibrary` with the prepared add/remove sets and threshold update.
        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildEmptyAddressArray(), newVotingThreshold: 2
        });
    }

    /// @dev Verifies that setting the voting threshold to one succeeds when the final admin count is at least one.
    function test_modifyAdmins_thresholdOne_succeedsWhenFinalCountAtLeastOne() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});

        // Call: invoke `modifyAdminsViaLibrary` with the prepared add/remove sets and threshold update.

        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildArray(admin2), newVotingThreshold: 1
        });

        // Verify: assert that voting threshold matches the expected value.

        assertEq(harness.votingThreshold(), 1, "threshold should be updated to 1");
        // Verify: assert that admin count matches the expected value.
        assertEq(harness.adminCount(), 1, "admin count should be 1");
    }

    /// @dev Verifies that setting the voting threshold equal to the final admin count succeeds.
    function test_modifyAdmins_thresholdEqualsFinalCount_succeeds() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({
            members: buildArray(admin1, admin2, admin3), admins: buildArray(admin1, admin2, admin3), threshold: 2
        });

        // Call: invoke `modifyAdminsViaLibrary` with the prepared add/remove sets and threshold update.

        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildArray(admin3), newVotingThreshold: 2
        });

        // Verify: assert that admin count matches the expected value.

        assertEq(harness.adminCount(), 2, "admin count should be 2");
        // Verify: assert that voting threshold matches the expected value.
        assertEq(harness.votingThreshold(), 2, "threshold should equal final admin count");
    }

    /// @dev Verifies that removing admins while keeping a too-high threshold reverts with
    /// `InvalidAdminVotingThreshold`.
    function test_modifyAdmins_removalLeavingThresholdTooHigh_reverts() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.InvalidAdminVotingThreshold.selector, 2, 1));
        // Call: invoke `modifyAdminsViaLibrary` with the prepared add/remove sets and threshold update.
        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildArray(admin2), newVotingThreshold: 2
        });
    }

    /// @dev Verifies that empty add/remove arrays with an unchanged threshold is a successful no-op.
    function test_modifyAdmins_emptyArraysUnchangedThreshold_succeedsNoOp() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Call: invoke `modifyAdminsViaLibrary` with the prepared add/remove sets and threshold update.

        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildEmptyAddressArray(), newVotingThreshold: 1
        });

        // Verify: assert that admin count matches the expected value.

        assertEq(harness.adminCount(), 1, "admin count should remain unchanged");
        // Verify: assert that voting threshold matches the expected value.
        assertEq(harness.votingThreshold(), 1, "threshold should remain unchanged");
        // Verify: assert that the address has admin status expected for this branch.
        assertTrue(harness.getAdminStatus(admin1), "existing admin must remain admin");
    }

    /// @dev Verifies that empty add/remove arrays with a changed threshold succeeds and updates the threshold.
    function test_modifyAdmins_emptyArraysChangedThreshold_succeedsAndUpdatesThreshold() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 1});

        // Call: invoke `modifyAdminsViaLibrary` with the prepared add/remove sets and threshold update.

        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildEmptyAddressArray(), newVotingThreshold: 2
        });

        // Verify: assert that voting threshold matches the expected value.

        assertEq(harness.votingThreshold(), 2, "threshold should update");
        // Verify: assert that admin count matches the expected value.
        assertEq(harness.adminCount(), 2, "admin count should remain unchanged");
    }

    /// @dev Verifies that adding and removing the same non-admin member in one call results in a net-zero change.
    function test_modifyAdmins_sameAddressAddAndRemove_nonAdminMember_netUnchanged() public {
        address candidate = address(0x107);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, candidate), admins: buildArray(admin1), threshold: 1});

        // Call: invoke `modifyAdminsViaLibrary` with the prepared add/remove sets and threshold update.

        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildArray(candidate), adminsToRemove: buildArray(candidate), newVotingThreshold: 1
        });

        // Verify: assert that the address does not have admin status for this branch.

        assertFalse(harness.getAdminStatus(candidate), "candidate should end non-admin");
        // Verify: assert that admin count matches the expected value.
        assertEq(harness.adminCount(), 1, "admin count should be unchanged");
    }

    /// @dev Verifies that adding and removing an existing admin in one call reverts with `AdminAlreadyExists` during
    /// the add loop.
    function test_modifyAdmins_sameAddressAddAndRemove_initiallyAdmin_revertsAdminAlreadyExists() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.AdminAlreadyExists.selector, admin1));
        // Call: invoke `modifyAdminsViaLibrary` with the prepared add/remove sets and threshold update.
        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildArray(admin1), adminsToRemove: buildArray(admin1), newVotingThreshold: 1
        });
    }

    /// @dev Verifies that a revert during additions rolls back all earlier successful additions.
    function test_modifyAdmins_revertDuringAdditions_rollsBackEarlierAdds() public {
        address validCandidate = address(0x108);
        address invalidCandidate = address(0x109);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, validCandidate), admins: buildArray(admin1), threshold: 1});

        address[] memory addrs = buildArray(validCandidate, invalidCandidate);
        // First add would succeed in isolation, but second add fails and should revert all changes.
        // Verify: confirm this branch reverts for the intended failure condition.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.AdminNotMember.selector, invalidCandidate));
        // Call: invoke `modifyAdminsViaLibrary` with the prepared add/remove sets and threshold update.
        harness.modifyAdminsViaLibrary({
            adminsToAdd: addrs, adminsToRemove: buildEmptyAddressArray(), newVotingThreshold: 1
        });

        // Verify: assert that the address does not have admin status for this branch.

        assertFalse(harness.getAdminStatus(validCandidate), "first addition must rollback on revert");
        // Verify: assert that admin count matches the expected value.
        assertEq(harness.adminCount(), 1, "admin count must rollback on revert");
    }

    /// @dev Verifies that a revert during removals rolls back all prior additions and removals from the same
    /// transaction.
    function test_modifyAdmins_revertDuringRemovals_rollsBackPriorMutations() public {
        address newAdmin = address(0x110);
        address nonAdminToRemove = address(0x111);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({
            members: buildArray(admin1, admin2, newAdmin, nonAdminToRemove),
            admins: buildArray(admin1, admin2),
            threshold: 1
        });

        address[] memory addrs = buildArray(newAdmin);
        address[] memory removals = buildArray(admin2, nonAdminToRemove);

        // Removing a non-admin in the same transaction should revert and rollback prior steps.
        // Verify: confirm this branch reverts for the intended failure condition.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.AdminDoesNotExist.selector, nonAdminToRemove));
        // Call: invoke `modifyAdminsViaLibrary` with the prepared add/remove sets and threshold update.
        harness.modifyAdminsViaLibrary({adminsToAdd: addrs, adminsToRemove: removals, newVotingThreshold: 1});

        // Verify: assert that the address does not have admin status for this branch.

        assertFalse(harness.getAdminStatus(newAdmin), "addition should rollback");
        // Verify: assert that the address has admin status expected for this branch.
        assertTrue(harness.getAdminStatus(admin2), "removal should rollback");
        // Verify: assert that admin count matches the expected value.
        assertEq(harness.adminCount(), 2, "admin count should rollback");
    }

    /// @dev Verifies that one `AdminAdded` event is emitted per successful addition.
    function test_modifyAdmins_emitsAdminAddedPerSuccessfulAdd() public {
        address candidate1 = address(0x112);
        address candidate2 = address(0x113);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({
            members: buildArray(admin1, candidate1, candidate2), admins: buildArray(admin1), threshold: 1
        });

        // Verify: confirm the expected event (and args/topics) is emitted for this success path.

        vm.expectEmit(true, false, false, true);
        emit IOrganizationAdmin.AdminAdded(candidate1);
        // Verify: confirm the expected event (and args/topics) is emitted for this success path.
        vm.expectEmit(true, false, false, true);
        emit IOrganizationAdmin.AdminAdded(candidate2);

        // Call: invoke `modifyAdminsViaLibrary` with the prepared add/remove sets and threshold update.

        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildArray(candidate1, candidate2),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 2
        });
    }

    /// @dev Verifies that one `AdminRemoved` event is emitted per successful removal.
    function test_modifyAdmins_emitsAdminRemovedPerSuccessfulRemove() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({
            members: buildArray(admin1, admin2, admin3), admins: buildArray(admin1, admin2, admin3), threshold: 1
        });

        // Verify: confirm the expected event (and args/topics) is emitted for this success path.

        vm.expectEmit(true, false, false, true);
        emit IOrganizationAdmin.AdminRemoved(admin2);
        // Verify: confirm the expected event (and args/topics) is emitted for this success path.
        vm.expectEmit(true, false, false, true);
        emit IOrganizationAdmin.AdminRemoved(admin3);

        // Call: invoke `modifyAdminsViaLibrary` with the prepared add/remove sets and threshold update.

        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildArray(admin2, admin3), newVotingThreshold: 1
        });
    }

    /// @dev Verifies that `VotingThresholdUpdated` is emitted only when the threshold changes.
    function test_modifyAdmins_emitsVotingThresholdUpdatedOnlyOnThresholdChange() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 1});

        // Verify: confirm the expected event (and args/topics) is emitted for this success path.

        vm.expectEmit(false, false, false, true);
        emit IOrganizationAdmin.VotingThresholdUpdated(1, 2);
        // Call: invoke `modifyAdminsViaLibrary` with the prepared add/remove sets and threshold update.
        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildEmptyAddressArray(), newVotingThreshold: 2
        });

        vm.recordLogs();
        // Call: invoke `modifyAdminsViaLibrary` with the prepared add/remove sets and threshold update.
        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildEmptyAddressArray(), newVotingThreshold: 2
        });

        // Second call uses the same threshold and should emit no threshold-update event.
        Vm.Log[] memory actualLogs = vm.getRecordedLogs();
        bytes32 expectVotingThresholdUpdatedSig = keccak256("VotingThresholdUpdated(uint256,uint256)");
        for (uint256 i = 0; i < actualLogs.length; i++) {
            // Verify: confirm the resulting state/value matches the expected branch outcome.
            assertTrue(
                actualLogs[i].topics[0] != expectVotingThresholdUpdatedSig,
                "threshold update event should not be emitted when unchanged"
            );
        }
    }

    /// @dev Verifies that the post-state admin count matches the number of admins in the touched address set.
    function test_modifyAdmins_postStateConsistency_touchedSetMatchesAdminCount() public {
        address candidate = address(0x114);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({
            members: buildArray(admin1, admin2, admin3, candidate),
            admins: buildArray(admin1, admin2, admin3),
            threshold: 2
        });

        // Call: invoke `modifyAdminsViaLibrary` with the prepared add/remove sets and threshold update.

        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildArray(candidate), adminsToRemove: buildArray(admin2), newVotingThreshold: 2
        });

        address[] memory touched = buildArray(admin1, admin2, admin3, candidate);
        uint256 actualTouchedSetAdminCount = 0;
        for (uint256 i = 0; i < touched.length; i++) {
            if (harness.getAdminStatus(touched[i])) {
                actualTouchedSetAdminCount++;
            }
        }

        uint256 expectAdminCount = harness.adminCount();
        // Verify: assert that admin count matches the expected value.
        assertEq(actualTouchedSetAdminCount, expectAdminCount, "touched-set cardinality must match adminCount");
    }
}
