// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    OrganizationAdminBaseSuiteBase
} from "test/organization/base/OrganizationAdminBase/OrganizationAdminBaseSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";

/**
 * @dev Unit tests for read-only view wrappers exposed by `OrganizationAdminBase`.
 */
contract OrganizationAdminBaseViewsTest is OrganizationAdminBaseSuiteBase {
    /// @dev Verifies that `isAdmin` returns true for a configured admin.
    function test_isAdmin_returnsTrueForAdmin() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Call: read admin status for a configured admin address.
        bool actualIsAdmin = harness.isAdmin(admin1);

        // Verify: assert that the address has admin status expected for this branch.
        assertTrue(actualIsAdmin, "isAdmin should return true for admin");
    }

    /// @dev Verifies that `isAdmin` returns false for a non-admin address.
    function test_isAdmin_returnsFalseForNonAdmin() public {
        address nonAdmin = address(0x212);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, nonAdmin), admins: buildArray(admin1), threshold: 1});

        // Call: read admin status for a configured non-admin address.
        bool actualIsAdmin = harness.isAdmin(nonAdmin);

        // Verify: assert that the address does not have admin status for this branch.
        assertFalse(actualIsAdmin, "isAdmin should return false for non-admin");
    }

    /// @dev Verifies that `adminCount` mirrors the storage count after an add/remove sequence.
    function test_adminCount_mirrorsStorageAfterMutations() public {
        address adminToAdd = address(0x213);
        // Setup: configure the initial organization state for this branch (3 members, 2 admins).
        _setMembersAndAdmins({
            members: buildArray(admin1, admin2, adminToAdd), admins: buildArray(admin1, admin2), threshold: 1
        });

        (AdminAuthParams memory addAuth,) = _buildModifyAdminsAuth({
            adminsToAdd: buildArray(adminToAdd),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            salt: 2029,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        // Call: invoke `modifyAdmins` with the prepared add/remove sets, threshold, and admin auth params.
        harness.modifyAdmins({
            adminsToAdd: buildArray(adminToAdd),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            authParams: addAuth
        });

        // Call: read admin count after the add flow.
        uint256 actualAdminCountAfterAdd = harness.adminCount();
        uint256 expectAdminCountAfterAdd = 3;
        // Verify: assert that admin count matches the expected value.
        assertEq(actualAdminCountAfterAdd, expectAdminCountAfterAdd, "adminCount should reflect addition");

        (AdminAuthParams memory removeAuth,) = _buildModifyAdminsAuth({
            adminsToAdd: buildEmptyAddressArray(),
            adminsToRemove: buildArray(admin2),
            newVotingThreshold: 1,
            salt: 2030,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        // Call: invoke `modifyAdmins` with the prepared add/remove sets, threshold, and admin auth params.
        harness.modifyAdmins({
            adminsToAdd: buildEmptyAddressArray(),
            adminsToRemove: buildArray(admin2),
            newVotingThreshold: 1,
            authParams: removeAuth
        });

        // Call: read admin count after the remove flow.
        uint256 actualAdminCountAfterRemoval = harness.adminCount();
        uint256 expectAdminCountAfterRemoval = 2;
        // Verify: assert that admin count matches the expected value.
        assertEq(actualAdminCountAfterRemoval, expectAdminCountAfterRemoval, "adminCount should reflect removal");
    }

    /// @dev Verifies that `votingThreshold` mirrors the storage value after updates.
    function test_votingThreshold_mirrorsStorageAfterUpdates() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 1});

        (AdminAuthParams memory auth,) = _buildModifyAdminsAuth({
            adminsToAdd: buildEmptyAddressArray(),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 2,
            salt: 2031,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        // Call: invoke `modifyAdmins` with the prepared add/remove sets, threshold, and admin auth params.
        harness.modifyAdmins({
            adminsToAdd: buildEmptyAddressArray(),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 2,
            authParams: auth
        });

        // Call: read voting threshold after the update.
        uint256 actualVotingThreshold = harness.votingThreshold();
        uint256 expectVotingThreshold = 2;
        // Verify: assert that voting threshold matches the expected value.
        assertEq(actualVotingThreshold, expectVotingThreshold, "votingThreshold should mirror updated storage value");
    }
}
