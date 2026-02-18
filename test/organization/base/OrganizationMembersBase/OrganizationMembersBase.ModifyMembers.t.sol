// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {
    OrganizationMembersBaseSuiteBase
} from "test/organization/base/OrganizationMembersBase/OrganizationMembersBaseSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Unit tests for `OrganizationMembersBase.modifyMembers` behavior.
 */
contract OrganizationMembersBaseModifyMembersTest is OrganizationMembersBaseSuiteBase {
    /// @dev Verifies that `modifyMembers` rejects non-guardian callers via `onlyGuardian`.
    function test_modifyMembers_nonGuardianCaller_revertsOnlyGuardian() public {
        // Setup: configure members/admins for a valid baseline state.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        AdminAuthParams memory auth;
        // Verify: non-guardian caller must be rejected before auth validation runs.
        _expectOnlyGuardianRevert(NON_GUARDIAN);
        vm.prank(NON_GUARDIAN);
        // Call: invoke `modifyMembers` through the base-contract wrapper.
        harness.modifyMembers({
            membersToAdd: buildEmptyAddressArray(), membersToRemove: buildEmptyAddressArray(), authParams: auth
        });
    }

    /// @dev Verifies that guardian calls with valid admin signatures succeed.
    function test_modifyMembers_guardianWithValidAuth_succeeds() public {
        address memberToAdd = address(0x401);
        // Setup: require two admin signatures for execution.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});

        (AdminAuthParams memory auth,) = _buildModifyMembersAuth({
            membersToAdd: buildArray(memberToAdd),
            membersToRemove: buildEmptyAddressArray(),
            salt: 4101,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1, ADMIN_PK_2)
        });

        vm.prank(GUARDIAN);
        // Call: invoke `modifyMembers` through the base-contract wrapper.
        harness.modifyMembers({
            membersToAdd: buildArray(memberToAdd), membersToRemove: buildEmptyAddressArray(), authParams: auth
        });

        // Verify: member should be added after authorized execution.
        assertTrue(harness.isMember(memberToAdd), "member should be added by authorized call");
    }

    /// @dev Verifies that guardian calls with insufficient signatures revert.
    function test_modifyMembers_insufficientAdminSignatures_reverts() public {
        address memberToAdd = address(0x402);
        // Setup: require two signatures but provide one.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});

        (AdminAuthParams memory auth, bytes memory operationData) = _buildModifyMembersAuth({
            membersToAdd: buildArray(memberToAdd),
            membersToRemove: buildEmptyAddressArray(),
            salt: 4102,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: authorization should fail when valid signer count is below threshold.
        vm.expectRevert(IOrganizationAdmin.InsufficientAdminAuthorization.selector);
        vm.prank(GUARDIAN);
        // Call: invoke `modifyMembers` through the base-contract wrapper.
        harness.modifyMembers({
            membersToAdd: buildArray(memberToAdd), membersToRemove: buildEmptyAddressArray(), authParams: auth
        });

        // Verify: failed execution should not leave nonce consumed.
        uint256 nonce = harness.computeNonce({
            operationType: OperationType.ModifyMembers, operationData: operationData, salt: 4102
        });
        assertFalse(harness.getUsedNonce(nonce), "failed auth should not consume nonce");
    }
}
