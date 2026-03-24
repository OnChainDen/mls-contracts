// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibOrganizationMembersSuiteBase
} from "test/organization/libraries/LibOrganizationMembers/LibOrganizationMembersSuiteBase.sol";

/**
 * @dev Unit tests for read-only view wrappers exposed by `LibOrganizationMembers` harness.
 */
contract LibOrganizationMembersViewsTest is LibOrganizationMembersSuiteBase {
    /// @dev Verifies that `isMember` returns true for an existing member.
    function test_isMember_returnsTrueForExistingMember() public {
        address knownMember = address(0x321);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1, knownMember), admins: buildArray(admin1), threshold: 1});

        // Call: read member status for the known member address.
        bool actualIsMember = harness.isMember(knownMember);

        // Verify: expected branch outcome for known member.
        assertTrue(actualIsMember, "known member should be reported as member");
    }

    /// @dev Verifies that `isMember` returns false for a non-member address.
    function test_isMember_returnsFalseForNonMember() public {
        address nonMember = address(0x322);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Call: read member status for the known non-member address.
        bool actualIsMember = harness.isMember(nonMember);

        // Verify: expected branch outcome for known non-member.
        assertFalse(actualIsMember, "non-member should be reported as non-member");
    }

    /// @dev Verifies that `isMember` returns false for `address(0)`.
    function test_isMember_returnsFalseForZeroAddress() public {
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Call: read member status for the zero address.
        bool actualIsMember = harness.isMember(address(0));

        // Verify: zero address must never be treated as member.
        assertFalse(actualIsMember, "zero address should never be a member");
    }
}
