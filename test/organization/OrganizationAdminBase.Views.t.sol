// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {OrganizationAdminBaseSuiteBase} from "test/organization/helpers/OrganizationAdminBaseSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";

/**
 * @dev Unit tests for read-only view wrappers exposed by `OrganizationAdminBase`.
 */
contract OrganizationAdminBaseViewsTest is OrganizationAdminBaseSuiteBase {
    /// @dev isAdmin returns true for admin.
    function test_isAdmin_returnsTrueForAdmin() public {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        assertTrue(harness.isAdmin(admin1), "isAdmin should return true for admin");
    }

    /// @dev isAdmin returns false for non-admin.
    function test_isAdmin_returnsFalseForNonAdmin() public {
        address nonAdmin = address(0x212);
        _setMembersAndAdmins({members: buildArray(admin1, nonAdmin), admins: buildArray(admin1), threshold: 1});
        assertFalse(harness.isAdmin(nonAdmin), "isAdmin should return false for non-admin");
    }

    /// @dev adminCount mirrors storage count after add/remove sequence.
    function test_adminCount_mirrorsStorageAfterMutations() public {
        address adminToAdd = address(0x213);
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
        harness.modifyAdmins({
            adminsToAdd: buildArray(adminToAdd),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            authParams: addAuth
        });
        assertEq(harness.adminCount(), 3, "adminCount should reflect addition");

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
        harness.modifyAdmins({
            adminsToAdd: buildEmptyAddressArray(),
            adminsToRemove: buildArray(admin2),
            newVotingThreshold: 1,
            authParams: removeAuth
        });
        assertEq(harness.adminCount(), 2, "adminCount should reflect removal");
    }

    /// @dev votingThreshold mirrors storage threshold after updates.
    function test_votingThreshold_mirrorsStorageAfterUpdates() public {
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
        harness.modifyAdmins({
            adminsToAdd: buildEmptyAddressArray(),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 2,
            authParams: auth
        });

        assertEq(harness.votingThreshold(), 2, "votingThreshold should mirror updated storage value");
    }
}
