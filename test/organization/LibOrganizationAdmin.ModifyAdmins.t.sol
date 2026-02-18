// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Vm} from "forge-std/Vm.sol";

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {IOrganizationMembers} from "interfaces/organization/IOrganizationMembers.sol";
import {LibOrganizationAdminSuiteBase} from "test/organization/helpers/LibOrganizationAdminSuiteBase.sol";

/**
 * @dev Unit tests for `LibOrganizationAdmin.modifyAdmins`.
 */
contract LibOrganizationAdminModifyAdminsTest is LibOrganizationAdminSuiteBase {
    /// @dev Add one valid member as admin succeeds and increments count.
    function test_modifyAdmins_addOneValidMember_succeedsAndIncrementsCount() public {
        address candidate = address(0x101);
        _setMembersAndAdmins({members: buildArray(admin1, candidate), admins: buildArray(admin1), threshold: 1});

        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildArray(candidate), adminsToRemove: buildEmptyAddressArray(), newVotingThreshold: 1
        });

        assertTrue(harness.getAdminStatus(candidate), "candidate should be admin");
        assertEq(harness.adminCount(), 2, "admin count should increment");
    }

    /// @dev Add multiple valid members as admins succeeds.
    function test_modifyAdmins_addMultipleValidMembers_succeeds() public {
        address candidate1 = address(0x102);
        address candidate2 = address(0x103);
        _setMembersAndAdmins({
            members: buildArray(admin1, candidate1, candidate2), admins: buildArray(admin1), threshold: 1
        });

        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildArray(candidate1, candidate2),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 2
        });

        assertTrue(harness.getAdminStatus(candidate1), "candidate1 should be admin");
        assertTrue(harness.getAdminStatus(candidate2), "candidate2 should be admin");
        assertEq(harness.adminCount(), 3, "admin count should be updated");
    }

    /// @dev Adding zero address reverts InvalidMemberAddress.
    function test_modifyAdmins_addZeroAddress_revertsInvalidMemberAddress() public {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        vm.expectRevert(abi.encodeWithSelector(IOrganizationMembers.InvalidMemberAddress.selector, address(0)));
        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildArray(address(0)), adminsToRemove: buildEmptyAddressArray(), newVotingThreshold: 1
        });
    }

    /// @dev Adding non-member reverts AdminNotMember.
    function test_modifyAdmins_addNonMember_revertsAdminNotMember() public {
        address nonMember = address(0x104);
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.AdminNotMember.selector, nonMember));
        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildArray(nonMember), adminsToRemove: buildEmptyAddressArray(), newVotingThreshold: 1
        });
    }

    /// @dev Adding existing admin reverts AdminAlreadyExists.
    function test_modifyAdmins_addExistingAdmin_revertsAdminAlreadyExists() public {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.AdminAlreadyExists.selector, admin1));
        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildArray(admin1), adminsToRemove: buildEmptyAddressArray(), newVotingThreshold: 1
        });
    }

    /// @dev Duplicate address in add array reverts on second occurrence.
    function test_modifyAdmins_duplicateInAddArray_revertsAdminAlreadyExists() public {
        address candidate = address(0x105);
        _setMembersAndAdmins({members: buildArray(admin1, candidate), admins: buildArray(admin1), threshold: 1});

        address[] memory addrs = buildArray(candidate, candidate);
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.AdminAlreadyExists.selector, candidate));
        harness.modifyAdminsViaLibrary({
            adminsToAdd: addrs, adminsToRemove: buildEmptyAddressArray(), newVotingThreshold: 1
        });
    }

    /// @dev Remove existing admin succeeds and decrements count.
    function test_modifyAdmins_removeExistingAdmin_succeedsAndDecrementsCount() public {
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 1});

        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildArray(admin2), newVotingThreshold: 1
        });

        assertFalse(harness.getAdminStatus(admin2), "admin2 should be removed");
        assertEq(harness.adminCount(), 1, "admin count should decrement");
    }

    /// @dev Remove multiple existing admins succeeds.
    function test_modifyAdmins_removeMultipleAdmins_succeeds() public {
        _setMembersAndAdmins({
            members: buildArray(admin1, admin2, admin3), admins: buildArray(admin1, admin2, admin3), threshold: 1
        });

        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildArray(admin2, admin3), newVotingThreshold: 1
        });

        assertFalse(harness.getAdminStatus(admin2), "admin2 should be removed");
        assertFalse(harness.getAdminStatus(admin3), "admin3 should be removed");
        assertEq(harness.adminCount(), 1, "admin count should match final set");
    }

    /// @dev Remove non-admin reverts AdminDoesNotExist.
    function test_modifyAdmins_removeNonAdmin_revertsAdminDoesNotExist() public {
        address nonAdmin = address(0x106);
        _setMembersAndAdmins({members: buildArray(admin1, nonAdmin), admins: buildArray(admin1), threshold: 1});

        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.AdminDoesNotExist.selector, nonAdmin));
        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildArray(nonAdmin), newVotingThreshold: 1
        });
    }

    /// @dev Remove zero address reverts AdminDoesNotExist.
    function test_modifyAdmins_removeZeroAddress_revertsAdminDoesNotExist() public {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.AdminDoesNotExist.selector, address(0)));
        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildArray(address(0)), newVotingThreshold: 1
        });
    }

    /// @dev Duplicate in remove array reverts on second occurrence.
    function test_modifyAdmins_duplicateInRemoveArray_revertsAdminDoesNotExist() public {
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 1});

        address[] memory removeAddrs = buildArray(admin2, admin2);
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.AdminDoesNotExist.selector, admin2));
        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: removeAddrs, newVotingThreshold: 1
        });
    }

    /// @dev Removing last admin reverts InvalidAdminConfig.
    function test_modifyAdmins_removeLastAdmin_revertsInvalidAdminConfig() public {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        vm.expectRevert(IOrganizationAdmin.InvalidAdminConfig.selector);
        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildArray(admin1), newVotingThreshold: 1
        });
    }

    /// @dev newVotingThreshold=0 reverts InvalidAdminVotingThreshold.
    function test_modifyAdmins_thresholdZero_revertsInvalidAdminVotingThreshold() public {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.InvalidAdminVotingThreshold.selector, 0, 1));
        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildEmptyAddressArray(), newVotingThreshold: 0
        });
    }

    /// @dev newVotingThreshold > final admin count reverts.
    function test_modifyAdmins_thresholdGreaterThanFinalCount_revertsInvalidAdminVotingThreshold() public {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.InvalidAdminVotingThreshold.selector, 2, 1));
        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildEmptyAddressArray(), newVotingThreshold: 2
        });
    }

    /// @dev newVotingThreshold=1 succeeds when final count >= 1.
    function test_modifyAdmins_thresholdOne_succeedsWhenFinalCountAtLeastOne() public {
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});

        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildArray(admin2), newVotingThreshold: 1
        });

        assertEq(harness.votingThreshold(), 1, "threshold should be updated to 1");
        assertEq(harness.adminCount(), 1, "admin count should be 1");
    }

    /// @dev newVotingThreshold=finalAdminCount succeeds.
    function test_modifyAdmins_thresholdEqualsFinalCount_succeeds() public {
        _setMembersAndAdmins({
            members: buildArray(admin1, admin2, admin3), admins: buildArray(admin1, admin2, admin3), threshold: 2
        });

        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildArray(admin3), newVotingThreshold: 2
        });

        assertEq(harness.adminCount(), 2, "admin count should be 2");
        assertEq(harness.votingThreshold(), 2, "threshold should equal final admin count");
    }

    /// @dev Removing admins while keeping too-high threshold reverts.
    function test_modifyAdmins_removalLeavingThresholdTooHigh_reverts() public {
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});

        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.InvalidAdminVotingThreshold.selector, 2, 1));
        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildArray(admin2), newVotingThreshold: 2
        });
    }

    /// @dev Empty add/remove with unchanged valid threshold is successful no-op.
    function test_modifyAdmins_emptyArraysUnchangedThreshold_succeedsNoOp() public {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildEmptyAddressArray(), newVotingThreshold: 1
        });

        assertEq(harness.adminCount(), 1, "admin count should remain unchanged");
        assertEq(harness.votingThreshold(), 1, "threshold should remain unchanged");
        assertTrue(harness.getAdminStatus(admin1), "existing admin must remain admin");
    }

    /// @dev Empty add/remove with changed valid threshold succeeds and updates threshold.
    function test_modifyAdmins_emptyArraysChangedThreshold_succeedsAndUpdatesThreshold() public {
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 1});

        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildEmptyAddressArray(), newVotingThreshold: 2
        });

        assertEq(harness.votingThreshold(), 2, "threshold should update");
        assertEq(harness.adminCount(), 2, "admin count should remain unchanged");
    }

    /// @dev Same address in add+remove when initially non-admin member succeeds (net unchanged).
    function test_modifyAdmins_sameAddressAddAndRemove_nonAdminMember_netUnchanged() public {
        address candidate = address(0x107);
        _setMembersAndAdmins({members: buildArray(admin1, candidate), admins: buildArray(admin1), threshold: 1});

        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildArray(candidate), adminsToRemove: buildArray(candidate), newVotingThreshold: 1
        });

        assertFalse(harness.getAdminStatus(candidate), "candidate should end non-admin");
        assertEq(harness.adminCount(), 1, "admin count should be unchanged");
    }

    /// @dev Same address in add+remove when initially admin reverts in add loop.
    function test_modifyAdmins_sameAddressAddAndRemove_initiallyAdmin_revertsAdminAlreadyExists() public {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.AdminAlreadyExists.selector, admin1));
        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildArray(admin1), adminsToRemove: buildArray(admin1), newVotingThreshold: 1
        });
    }

    /// @dev Revert during additions rolls back earlier successful additions.
    function test_modifyAdmins_revertDuringAdditions_rollsBackEarlierAdds() public {
        address validCandidate = address(0x108);
        address invalidCandidate = address(0x109);
        _setMembersAndAdmins({members: buildArray(admin1, validCandidate), admins: buildArray(admin1), threshold: 1});

        address[] memory addrs = buildArray(validCandidate, invalidCandidate);
        // First add would succeed in isolation, but second add fails and should revert all changes.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.AdminNotMember.selector, invalidCandidate));
        harness.modifyAdminsViaLibrary({
            adminsToAdd: addrs, adminsToRemove: buildEmptyAddressArray(), newVotingThreshold: 1
        });

        assertFalse(harness.getAdminStatus(validCandidate), "first addition must rollback on revert");
        assertEq(harness.adminCount(), 1, "admin count must rollback on revert");
    }

    /// @dev Revert during removals rolls back prior additions/removals from same tx.
    function test_modifyAdmins_revertDuringRemovals_rollsBackPriorMutations() public {
        address newAdmin = address(0x110);
        address nonAdminToRemove = address(0x111);
        _setMembersAndAdmins({
            members: buildArray(admin1, admin2, newAdmin, nonAdminToRemove),
            admins: buildArray(admin1, admin2),
            threshold: 1
        });

        address[] memory addrs = buildArray(newAdmin);
        address[] memory removals = buildArray(admin2, nonAdminToRemove);

        // Removing a non-admin in the same transaction should revert and rollback prior steps.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.AdminDoesNotExist.selector, nonAdminToRemove));
        harness.modifyAdminsViaLibrary({adminsToAdd: addrs, adminsToRemove: removals, newVotingThreshold: 1});

        assertFalse(harness.getAdminStatus(newAdmin), "addition should rollback");
        assertTrue(harness.getAdminStatus(admin2), "removal should rollback");
        assertEq(harness.adminCount(), 2, "admin count should rollback");
    }

    /// @dev Emits one AdminAdded event per successful addition.
    function test_modifyAdmins_emitsAdminAddedPerSuccessfulAdd() public {
        address candidate1 = address(0x112);
        address candidate2 = address(0x113);
        _setMembersAndAdmins({
            members: buildArray(admin1, candidate1, candidate2), admins: buildArray(admin1), threshold: 1
        });

        vm.expectEmit(true, false, false, true);
        emit IOrganizationAdmin.AdminAdded(candidate1);
        vm.expectEmit(true, false, false, true);
        emit IOrganizationAdmin.AdminAdded(candidate2);

        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildArray(candidate1, candidate2),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 2
        });
    }

    /// @dev Emits one AdminRemoved event per successful removal.
    function test_modifyAdmins_emitsAdminRemovedPerSuccessfulRemove() public {
        _setMembersAndAdmins({
            members: buildArray(admin1, admin2, admin3), admins: buildArray(admin1, admin2, admin3), threshold: 1
        });

        vm.expectEmit(true, false, false, true);
        emit IOrganizationAdmin.AdminRemoved(admin2);
        vm.expectEmit(true, false, false, true);
        emit IOrganizationAdmin.AdminRemoved(admin3);

        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildArray(admin2, admin3), newVotingThreshold: 1
        });
    }

    /// @dev VotingThresholdUpdated is emitted only when threshold changes.
    function test_modifyAdmins_emitsVotingThresholdUpdatedOnlyOnThresholdChange() public {
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 1});

        vm.expectEmit(false, false, false, true);
        emit IOrganizationAdmin.VotingThresholdUpdated(1, 2);
        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildEmptyAddressArray(), newVotingThreshold: 2
        });

        vm.recordLogs();
        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildEmptyAddressArray(), newVotingThreshold: 2
        });

        // Second call uses the same threshold and should emit no threshold-update event.
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 eventSig = keccak256("VotingThresholdUpdated(uint256,uint256)");
        for (uint256 i = 0; i < entries.length; i++) {
            assertTrue(entries[i].topics[0] != eventSig, "threshold update event should not be emitted when unchanged");
        }
    }

    /// @dev Post-state consistency for touched set matches adminCount.
    function test_modifyAdmins_postStateConsistency_touchedSetMatchesAdminCount() public {
        address candidate = address(0x114);
        _setMembersAndAdmins({
            members: buildArray(admin1, admin2, admin3, candidate),
            admins: buildArray(admin1, admin2, admin3),
            threshold: 2
        });

        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildArray(candidate), adminsToRemove: buildArray(admin2), newVotingThreshold: 2
        });

        address[] memory touched = buildArray(admin1, admin2, admin3, candidate);
        uint256 modeledCount = 0;
        for (uint256 i = 0; i < touched.length; i++) {
            if (harness.getAdminStatus(touched[i])) {
                modeledCount++;
            }
        }

        assertEq(modeledCount, harness.adminCount(), "touched-set cardinality must match adminCount");
    }
}
