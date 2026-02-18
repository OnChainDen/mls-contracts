// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {LibOrganizationAdminSuiteBase} from "test/organization/helpers/LibOrganizationAdminSuiteBase.sol";

/**
 * @dev Unit tests for read-only view wrappers exposed by `LibOrganizationAdmin` harness.
 */
contract LibOrganizationAdminViewsTest is LibOrganizationAdminSuiteBase {
    /// @dev isAdmin returns true for known admin.
    function test_isAdmin_returnsTrueForKnownAdmin() public {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        assertTrue(harness.isAdmin(admin1), "admin should be reported as admin");
    }

    /// @dev isAdmin returns false for known non-admin.
    function test_isAdmin_returnsFalseForKnownNonAdmin() public {
        address nonAdmin = address(0x115);
        _setMembersAndAdmins({members: buildArray(admin1, nonAdmin), admins: buildArray(admin1), threshold: 1});
        assertFalse(harness.isAdmin(nonAdmin), "non-admin should not be reported as admin");
    }

    /// @dev isAdmin returns false for address(0).
    function test_isAdmin_returnsFalseForZeroAddress() public {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        assertFalse(harness.isAdmin(address(0)), "zero address should never be admin");
    }

    /// @dev getAdminCount returns initial and updated counts.
    function test_getAdminCount_returnsInitialAndUpdatedCount() public {
        address candidate = address(0x116);
        _setMembersAndAdmins({members: buildArray(admin1, candidate), admins: buildArray(admin1), threshold: 1});
        assertEq(harness.adminCount(), 1, "initial count mismatch");

        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildArray(candidate), adminsToRemove: buildEmptyAddressArray(), newVotingThreshold: 1
        });
        assertEq(harness.adminCount(), 2, "updated count mismatch");
    }

    /// @dev getVotingThreshold returns initial and updated thresholds.
    function test_getVotingThreshold_returnsInitialAndUpdatedThreshold() public {
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 1});
        assertEq(harness.votingThreshold(), 1, "initial threshold mismatch");

        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildEmptyAddressArray(), newVotingThreshold: 2
        });
        assertEq(harness.votingThreshold(), 2, "updated threshold mismatch");
    }
}
