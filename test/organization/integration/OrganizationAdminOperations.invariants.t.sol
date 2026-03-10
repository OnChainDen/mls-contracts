// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    OrganizationAdminBaseHarness
} from "test/organization/base/OrganizationAdminBase/OrganizationAdminBaseHarness.sol";
import {
    OrganizationAdminBaseSuiteBase
} from "test/organization/base/OrganizationAdminBase/OrganizationAdminBaseSuiteBase.sol";
import {
    OrganizationAccountTransactionInvariantHandler
} from "test/organization/integration/OrganizationAccountTransactionInvariantHandler.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Invariant checks for admin-operation (modifyAdmins) nonce properties.
 */
contract OrganizationAdminOperationNonceInvariants is OrganizationAdminBaseSuiteBase {
    OrganizationAccountTransactionInvariantHandler internal handler;
    OrganizationAdminBaseHarness internal secondOrganization;
    uint256 internal usedSalt;
    uint256 internal executedNonce;
    bytes internal operationData;

    function setUp() public override {
        super.setUp();

        // Setup: route invariant fuzz calls to a dedicated no-op handler to keep fixture state stable.
        handler = new OrganizationAccountTransactionInvariantHandler();
        targetContract(address(handler));

        // Setup: configure members/admins for a valid baseline state. admin2 is a member so it can be added as admin.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1), threshold: 1});
        stateHarness.setMemberStatus(admin2, true);

        usedSalt = 9001;

        // Setup: build admin auth and extract operation data for nonce computation.
        (AdminAuthParams memory auth, bytes memory opData) = _buildModifyAdminsAuth({
            adminsToAdd: buildArray(admin2),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            salt: usedSalt,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        operationData = opData;
        executedNonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            salt: usedSalt
        });

        // Call: execute modifyAdmins to consume the admin-operation nonce.
        vm.prank(GUARDIAN);
        harness.modifyAdmins({
            adminsToAdd: buildArray(admin2),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            authParams: auth
        });

        // Setup: deploy a fresh organization harness for cross-org isolation invariants.
        secondOrganization = new OrganizationAdminBaseHarness();
    }

    /// @dev Verifies invariant: once an admin-operation nonce is consumed, `isNonceUsed` never flips back to false.
    function invariant_NMINV_1_consumedAdminOperationNonceRemainsUsed() public view {
        // Verify: the nonce consumed by the successful modifyAdmins in `setUp` remains marked as used.
        assertTrue(harness.getUsedNonce(executedNonce), "consumed admin-operation nonce should remain used");
    }

    /// @dev Verifies invariant: identical admin-operation tuples do not share nonce usage across organizations.
    function invariant_NMINV_3_sameNonceValueDoesNotShareUsageAcrossOrganizations_adminOperation() public view {
        // Call: derive the matching admin-operation tuple on a fresh organization harness.
        uint256 sameTupleNonceOnSecondOrg = secondOrganization.computeNonce({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            salt: usedSalt
        });

        // Verify: nonce validity remains isolated per organization even when tuple derivation matches.
        assertTrue(
            harness.getUsedNonce(executedNonce), "primary organization should keep the admin-operation nonce consumed"
        );
        assertFalse(
            secondOrganization.getUsedNonce(executedNonce),
            "fresh organization should not inherit another org's consumed admin-operation nonce"
        );
        assertFalse(
            secondOrganization.getUsedNonce(sameTupleNonceOnSecondOrg),
            "fresh organization should not inherit admin-operation nonce usage"
        );
    }
}
