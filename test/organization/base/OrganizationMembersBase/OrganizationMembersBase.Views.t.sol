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
