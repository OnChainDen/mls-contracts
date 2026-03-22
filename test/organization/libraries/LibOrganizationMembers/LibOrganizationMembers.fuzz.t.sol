// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationMembers} from "interfaces/organization/IOrganizationMembers.sol";
import {
    LibOrganizationMembersSuiteBase
} from "test/organization/libraries/LibOrganizationMembers/LibOrganizationMembersSuiteBase.sol";

/**
 * @dev Fuzz tests for `LibOrganizationMembers`.
 */
contract LibOrganizationMembersFuzzTest is LibOrganizationMembersSuiteBase {
    /**
     * @dev Verifies that adding N random non-zero addresses marks each one as a member.
     */
    function testFuzz_modifyMembers_addNRandomNonZeroAddresses_allBecomeMembers(uint256 seed, uint8 rawCount) public {
        uint256 count = bound(uint256(rawCount), 1, 16);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        address[] memory membersToAdd = _deriveUniqueNonZeroAddresses(seed, count);
        // Call: mutate members via direct library wrapper.
        harness.modifyMembersViaLibrary({membersToAdd: membersToAdd, membersToRemove: buildEmptyAddressArray()});

        for (uint256 i = 0; i < membersToAdd.length; i++) {
            // Verify: every address from the fuzz-generated add set should be a member.
            assertTrue(harness.isMember(membersToAdd[i]), "all added addresses should become members");
        }
    }

    /**
     * @dev Verifies that adding then removing the same N random addresses clears membership for each.
     */
    function testFuzz_modifyMembers_addThenRemoveNRandomAddresses_noneRemainMembers(uint256 seed, uint8 rawCount)
        public
    {
        uint256 count = bound(uint256(rawCount), 1, 16);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        address[] memory members = _deriveUniqueNonZeroAddresses(seed, count);
        // Call: first add all generated addresses.
        harness.modifyMembersViaLibrary({membersToAdd: members, membersToRemove: buildEmptyAddressArray()});
        // Call: then remove the same generated addresses.
        harness.modifyMembersViaLibrary({membersToAdd: buildEmptyAddressArray(), membersToRemove: members});

        for (uint256 i = 0; i < members.length; i++) {
            // Verify: every address from the remove set should end as non-member.
            assertFalse(harness.isMember(members[i]), "all removed addresses should end non-member");
        }
    }

    /**
     * @dev Verifies that adding the same address twice is idempotent.
     */
    function testFuzz_modifyMembers_addingSameAddressTwiceIsIdempotent(address candidate) public {
        // Setup: constrain fuzz inputs for valid preconditions.
        vm.assume(candidate != address(0));
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Call: first idempotent add.
        harness.modifyMembersViaLibrary({
            membersToAdd: buildArray(candidate), membersToRemove: buildEmptyAddressArray()
        });
        bool afterFirstAdd = harness.isMember(candidate);

        // Call: second idempotent add of the same address.
        harness.modifyMembersViaLibrary({
            membersToAdd: buildArray(candidate), membersToRemove: buildEmptyAddressArray()
        });
        bool afterSecondAdd = harness.isMember(candidate);

        // Verify: repeated adds should preserve the same membership state.
        assertEq(afterSecondAdd, afterFirstAdd, "repeated adds should not change membership state");
        // Verify: candidate should be a member after add flow.
        assertTrue(afterSecondAdd, "candidate should be member after add flow");
    }

    /**
     * @dev Verifies that removing the same non-member address repeatedly is idempotent and non-reverting.
     */
    function testFuzz_modifyMembers_removingSameNonMemberAddress_isIdempotent(address nonMember) public {
        // Setup: constrain fuzz inputs for valid preconditions.

        vm.assume(nonMember != address(0) && nonMember != admin1);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        bytes memory callData =
            abi.encodeCall(harness.modifyMembersViaLibrary, (buildEmptyAddressArray(), buildArray(nonMember)));
        // Call: execute first removal attempt through low-level call to capture success/failure.
        (bool firstSuccess,) = address(harness).call(callData);
        // Call: execute second removal attempt for the same non-member address.
        (bool secondSuccess,) = address(harness).call(callData);
        // Verify: both attempts should be successful no-ops.
        assertTrue(firstSuccess, "first non-member removal should be a non-reverting no-op");
        // Verify: both attempts should be successful no-ops.
        assertTrue(secondSuccess, "second non-member removal should be a non-reverting no-op");
        // Verify: target address remains non-member after idempotent removals.
        assertFalse(harness.isMember(nonMember), "target should remain non-member");
    }

    /**
     * @dev Verifies that any add array containing `address(0)` reverts with `InvalidMemberAddress`.
     */
    function testFuzz_modifyMembers_randomZeroAddressInputAlwaysRevertsInvalidMemberAddress(
        uint256 seed,
        uint8 rawCount,
        uint8 rawZeroIndex
    ) public {
        uint256 count = bound(uint256(rawCount), 1, 16);
        uint256 zeroIndex = bound(uint256(rawZeroIndex), 0, count - 1);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        address[] memory membersToAdd = _deriveUniqueNonZeroAddresses(seed, count);
        membersToAdd[zeroIndex] = address(0);

        // Verify: adding any zero-address entry should revert with InvalidMemberAddress.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationMembers.InvalidMemberAddress.selector, address(0)));
        // Call: mutate members via direct library wrapper.
        harness.modifyMembersViaLibrary({membersToAdd: membersToAdd, membersToRemove: buildEmptyAddressArray()});
    }

    /**
     * @dev Verifies that attempting to remove a member who is an admin always reverts with `MemberIsAdmin`.
     */
    function testFuzz_modifyMembers_removingAdminMemberAlwaysRevertsMemberIsAdmin(address adminMember) public {
        // Setup: constrain fuzz inputs for valid preconditions.
        vm.assume(adminMember != address(0) && adminMember != admin1);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({
            members: buildArray(admin1, adminMember), admins: buildArray(admin1, adminMember), threshold: 1
        });

        // Verify: member removal should revert while the address remains admin.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationMembers.MemberIsAdmin.selector, adminMember));
        // Call: mutate members via direct library wrapper.
        harness.modifyMembersViaLibrary({
            membersToAdd: buildEmptyAddressArray(), membersToRemove: buildArray(adminMember)
        });
    }

    /**
     * @dev Verifies that re-adding any previously removed member always reverts with `MemberAlreadyDeleted`.
     */
    function testFuzz_modifyMembers_readdDeletedMember_alwaysReverts(address candidate) public {
        // Setup: constrain fuzz inputs for valid preconditions.
        vm.assume(candidate != address(0) && candidate != admin1);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1, candidate), admins: buildArray(admin1), threshold: 1});

        // Call: remove the member.
        harness.modifyMembersViaLibrary({
            membersToAdd: buildEmptyAddressArray(), membersToRemove: buildArray(candidate)
        });

        // Verify: re-adding the deleted member should always revert.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationMembers.MemberAlreadyDeleted.selector, candidate));
        // Call: attempt to re-add the removed member.
        harness.modifyMembersViaLibrary({
            membersToAdd: buildArray(candidate), membersToRemove: buildEmptyAddressArray()
        });
    }

    /**
     * @dev Derives a deterministic set of unique, non-zero addresses from a fuzz seed.
     */
    function _deriveUniqueNonZeroAddresses(uint256 seed, uint256 count)
        internal
        pure
        returns (address[] memory values)
    {
        uint160 highBits = uint160(uint256(keccak256(abi.encode(seed))) & type(uint160).max) & ~uint160(0xff);
        values = new address[](count);

        for (uint256 i = 0; i < count; i++) {
            // Low byte is deterministic and unique within this bounded range.
            // Casting to uint160 is safe here: `count` is bounded to <= 16 in callers, so `(i + 1)` never truncates.
            // forge-lint: disable-next-line(unsafe-typecast)
            values[i] = address(highBits | uint160(i + 1));
        }
    }
}
