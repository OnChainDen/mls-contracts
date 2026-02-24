// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    OrganizationMembersBaseSuiteBase
} from "test/organization/base/OrganizationMembersBase/OrganizationMembersBaseSuiteBase.sol";

/**
 * @dev Unit tests for read-only view wrappers exposed by `OrganizationMembersBase`.
 */
contract OrganizationMembersBaseViewsTest is OrganizationMembersBaseSuiteBase {
    /// @dev Verifies that `isMember` returns true for an existing member.
    function test_isMember_returnsTrueForExistingMember() public {
        address knownMember = address(0x411);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1, knownMember), admins: buildArray(admin1), threshold: 1});

        // Call: read member status for the known member address.
        bool actualIsMember = harness.isMember(knownMember);

        // Verify: expected branch outcome for known member.
        assertTrue(actualIsMember, "known member should be reported as member");
    }

    /// @dev Verifies that `isMember` returns false for a non-member address.
    function test_isMember_returnsFalseForNonMember() public {
        address nonMember = address(0x412);
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

    /// @dev Verifies that `isMember` is publicly callable (not guardian-gated).
    function test_isMember_callableByAnyone() public {
        address knownMember = address(0x411);
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1, knownMember), admins: buildArray(admin1), threshold: 1});

        vm.prank(NON_GUARDIAN);
        // Call: read member status from a non-guardian account.
        bool actualIsMember = harness.isMember(knownMember);

        // Verify: non-guardian callers can read and receive correct member status.
        assertTrue(actualIsMember, "isMember should be callable by non-guardian");
    }
}
