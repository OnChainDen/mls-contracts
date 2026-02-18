// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibOrganizationAdminSuiteBase
} from "test/organization/libraries/LibOrganizationAdmin/LibOrganizationAdminSuiteBase.sol";

/**
 * @dev Unit tests for read-only view wrappers exposed by `LibOrganizationAdmin` harness.
 */
contract LibOrganizationAdminViewsTest is LibOrganizationAdminSuiteBase {
    /// @dev Verifies that `isAdmin` returns true for a known admin.
    function test_isAdmin_returnsTrueForKnownAdmin() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Call: read admin status for the known admin address.
        bool actualIsAdmin = harness.isAdmin(admin1);

        // Verify: confirm the resulting state/value matches the expected branch outcome.
        assertTrue(actualIsAdmin, "admin should be reported as admin");
    }

    /// @dev Verifies that `isAdmin` returns false for a known non-admin.
    function test_isAdmin_returnsFalseForKnownNonAdmin() public {
        address nonAdmin = address(0x115);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, nonAdmin), admins: buildArray(admin1), threshold: 1});

        // Call: read admin status for the known non-admin address.
        bool actualIsAdmin = harness.isAdmin(nonAdmin);

        // Verify: confirm the resulting state/value matches the expected branch outcome.
        assertFalse(actualIsAdmin, "non-admin should not be reported as admin");
    }

    /// @dev Verifies that `isAdmin` returns false for the zero address.
    function test_isAdmin_returnsFalseForZeroAddress() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Call: read admin status for the zero address.
        bool actualIsAdmin = harness.isAdmin(address(0));

        // Verify: confirm the resulting state/value matches the expected branch outcome.
        assertFalse(actualIsAdmin, "zero address should never be admin");
    }

    /// @dev Verifies that `getAdminCount` returns correct initial and updated counts after an addition.
    function test_getAdminCount_returnsInitialAndUpdatedCount() public {
        address candidate = address(0x116);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, candidate), admins: buildArray(admin1), threshold: 1});

        // Call: read admin count before the mutation.
        uint256 actualInitialAdminCount = harness.adminCount();
        uint256 expectInitialAdminCount = 1;
        // Verify: confirm the resulting state/value matches the expected branch outcome.
        assertEq(actualInitialAdminCount, expectInitialAdminCount, "initial count mismatch");

        // Call: invoke `modifyAdminsViaLibrary` with the prepared add/remove sets and threshold update.

        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildArray(candidate), adminsToRemove: buildEmptyAddressArray(), newVotingThreshold: 1
        });

        // Call: read admin count after the mutation.
        uint256 actualUpdatedAdminCount = harness.adminCount();
        uint256 expectUpdatedAdminCount = 2;
        // Verify: confirm the resulting state/value matches the expected branch outcome.
        assertEq(actualUpdatedAdminCount, expectUpdatedAdminCount, "updated count mismatch");
    }

    /// @dev Verifies that `getVotingThreshold` returns correct initial and updated values after a threshold change.
    function test_getVotingThreshold_returnsInitialAndUpdatedThreshold() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 1});

        // Call: read voting threshold before the mutation.
        uint256 actualInitialThreshold = harness.votingThreshold();
        uint256 expectInitialThreshold = 1;
        // Verify: confirm the resulting state/value matches the expected branch outcome.
        assertEq(actualInitialThreshold, expectInitialThreshold, "initial threshold mismatch");

        // Call: invoke `modifyAdminsViaLibrary` with the prepared add/remove sets and threshold update.

        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(), adminsToRemove: buildEmptyAddressArray(), newVotingThreshold: 2
        });

        // Call: read voting threshold after the mutation.
        uint256 actualUpdatedThreshold = harness.votingThreshold();
        uint256 expectUpdatedThreshold = 2;
        // Verify: confirm the resulting state/value matches the expected branch outcome.
        assertEq(actualUpdatedThreshold, expectUpdatedThreshold, "updated threshold mismatch");
    }
}
