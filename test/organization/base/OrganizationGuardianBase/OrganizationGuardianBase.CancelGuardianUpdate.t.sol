// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
import {IOrganizationSignatures} from "interfaces/organization/IOrganizationSignatures.sol";
import {
    OrganizationGuardianBaseSuiteBase
} from "test/organization/base/OrganizationGuardianBase/OrganizationGuardianBaseSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Unit tests for `OrganizationGuardianBase.cancelGuardianUpdate`.
 */
contract OrganizationGuardianBaseCancelGuardianUpdateTest is OrganizationGuardianBaseSuiteBase {
    /// @dev Verifies OGB-CGU-1: non-guardian caller reverts via `onlyGuardian`.
    function test_OGB_CGU_1_GUARD_INV_6_C_nonGuardianCaller_revertsOnlyGuardian() public {
        // Setup
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        guardianStateHarness.setPendingGuardian(NEW_GUARDIAN_A);
        guardianStateHarness.setPendingGuardianUpdateTimestamp(block.timestamp + 1 days);
        (AdminAuthParams memory auth,) = _buildCancelGuardianUpdateAuth({
            pendingGuardian: NEW_GUARDIAN_A,
            salt: 3001,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call
        _expectOnlyGuardianRevert(NON_GUARDIAN);
        vm.prank(NON_GUARDIAN);
        harness.cancelGuardianUpdate(auth);

        // Verify
        assertEq(harness.pendingGuardian(), NEW_GUARDIAN_A, "pending guardian should remain unchanged");
    }

    /// @dev Verifies OGB-CGU-2: insufficient admin signatures revert.
    function test_OGB_CGU_2_insufficientAdminSignatures_reverts() public {
        // Setup
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});
        guardianStateHarness.setPendingGuardian(NEW_GUARDIAN_A);
        guardianStateHarness.setPendingGuardianUpdateTimestamp(block.timestamp + 1 days);
        (AdminAuthParams memory auth,) = _buildCancelGuardianUpdateAuth({
            pendingGuardian: NEW_GUARDIAN_A,
            salt: 3002,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call
        vm.expectRevert(IOrganizationAdmin.InsufficientAdminAuthorization.selector);
        vm.prank(GUARDIAN);
        harness.cancelGuardianUpdate(auth);

        // Verify
        assertEq(harness.pendingGuardian(), NEW_GUARDIAN_A, "pending guardian should remain unchanged");
    }

    /// @dev Verifies OGB-CGU-3: replaying the same nonce reverts after successful execution.
    function test_OGB_CGU_3__NMGUB_GUF_5_replaySameNonce_revertsNonceAlreadyUsed() public {
        // Setup
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        _initiatePendingGuardianUpdate(NEW_GUARDIAN_A, 3901);
        (AdminAuthParams memory auth, bytes memory operationData) = _buildCancelGuardianUpdateAuth({
            pendingGuardian: NEW_GUARDIAN_A,
            salt: 3003,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 nonce = _computeGuardianNonce(OperationType.CancelUpdateGuardian, operationData, 3003);

        // Call
        vm.prank(GUARDIAN);
        harness.cancelGuardianUpdate(auth);

        // Verify
        assertTrue(harness.getUsedNonce(nonce), "nonce should be consumed on successful cancel");
        guardianStateHarness.setPendingGuardian(NEW_GUARDIAN_A);
        guardianStateHarness.setPendingGuardianUpdateTimestamp(block.timestamp + 1 days);
        guardianStateHarness.setIsGuardianUpdateReadyForAcceptance(false);
        vm.expectRevert(abi.encodeWithSelector(IOrganizationSignatures.NonceAlreadyUsed.selector, nonce));
        vm.prank(GUARDIAN);
        harness.cancelGuardianUpdate(auth);
    }

    /// @dev Verifies OGB-CGU-4: the approval path succeeds with `OperationType.CancelUpdateGuardian`.
    function test_OGB_CGU_4_operationTypeCancelUpdateGuardian_authorizesExecution() public {
        // Setup
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        _initiatePendingGuardianUpdate(NEW_GUARDIAN_A, 3902);
        (AdminAuthParams memory auth, bytes memory operationData) = _buildCancelGuardianUpdateAuth({
            pendingGuardian: NEW_GUARDIAN_A,
            salt: 3004,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 cancelNonce = _computeGuardianNonce(OperationType.CancelUpdateGuardian, operationData, 3004);
        uint256 finalizeNonce = _computeGuardianNonce(OperationType.FinalizeUpdateGuardian, operationData, 3004);

        // Call
        vm.prank(GUARDIAN);
        harness.cancelGuardianUpdate(auth);

        // Verify
        assertTrue(harness.getUsedNonce(cancelNonce), "cancel nonce should be consumed");
        assertFalse(harness.getUsedNonce(finalizeNonce), "finalize nonce should remain unused");
    }

    /// @dev Verifies OGB-CGU-5: operation data encodes current pending guardian.
    function test_OGB_CGU_5_operationDataEncodesPendingGuardian_bindingHolds() public {
        // Setup
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        _initiatePendingGuardianUpdate(NEW_GUARDIAN_A, 3903);
        (AdminAuthParams memory auth, bytes memory operationDataA) = _buildCancelGuardianUpdateAuth({
            pendingGuardian: NEW_GUARDIAN_A,
            salt: 3005,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        bytes memory operationDataB = abi.encode(NEW_GUARDIAN_B);

        // Call
        vm.prank(GUARDIAN);
        harness.cancelGuardianUpdate(auth);

        // Verify
        uint256 nonceA = _computeGuardianNonce(OperationType.CancelUpdateGuardian, operationDataA, 3005);
        uint256 nonceB = _computeGuardianNonce(OperationType.CancelUpdateGuardian, operationDataB, 3005);
        assertTrue(harness.getUsedNonce(nonceA), "signed pending payload nonce should be consumed");
        assertFalse(harness.getUsedNonce(nonceB), "different pending payload nonce should remain unused");
    }

    /// @dev Verifies `OrganizationGuardianBase.cancelGuardianUpdate` clears a pending normal guardian update before
    /// finalization. [OGU-GU-4]
    function test_OGB_CGU_6__OGU_GU_4__GUARD_INV_8_A_delegatesToLibrary_andClearsPendingState() public {
        // Setup
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        _initiatePendingGuardianUpdate(NEW_GUARDIAN_A, 3904);
        (AdminAuthParams memory auth,) = _buildCancelGuardianUpdateAuth({
            pendingGuardian: NEW_GUARDIAN_A,
            salt: 3006,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call
        vm.prank(GUARDIAN);
        harness.cancelGuardianUpdate(auth);

        // Verify
        assertEq(harness.pendingGuardian(), address(0), "pending guardian should clear");
        assertEq(harness.pendingGuardianUpdateTimestamp(), 0, "pending timestamp should clear");
        assertFalse(harness.isGuardianUpdateReadyForAcceptance(), "ready flag should clear");
        assertEq(harness.guardian(), GUARDIAN, "guardian should remain unchanged");
    }

    /// @dev Verifies OGB-CGU-7: rejection signatures cannot execute cancellation.
    function test_OGB_CGU_7_rejectionSignatures_cannotExecuteCancellation() public {
        // Setup
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        _initiatePendingGuardianUpdate(NEW_GUARDIAN_A, 3905);
        (AdminAuthParams memory auth, bytes memory operationData) = _buildCancelGuardianUpdateAuth({
            pendingGuardian: NEW_GUARDIAN_A,
            salt: 3007,
            expiration: block.timestamp + 1 days,
            isApproval: false,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.cancelGuardianUpdate(auth);

        // Verify
        uint256 nonce = _computeGuardianNonce(OperationType.CancelUpdateGuardian, operationData, 3007);
        assertFalse(harness.getUsedNonce(nonce), "nonce should rollback on failed auth");
    }

    /// @dev Verifies `OrganizationGuardianBase.cancelGuardianUpdate` rejects initiate-stage signatures reused during
    /// cancel-stage authorization. [OGU-GU-2]
    function test_OGB_CGU_8__NMGUB_GUF_7__OGU_GU_2_differentOperationTypeSignatures_cannotAuthorizeCancellation()
        public
    {
        // Setup
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        _initiatePendingGuardianUpdate(NEW_GUARDIAN_A, 3906);
        bytes memory operationData = abi.encode(NEW_GUARDIAN_A);
        uint256 salt = 3008;
        AdminAuthParams memory wrongAuth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.InitiateUpdateGuardian,
            operationData: operationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: block.timestamp + 1 days,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.cancelGuardianUpdate(wrongAuth);

        // Verify
        uint256 cancelNonce = _computeGuardianNonce(OperationType.CancelUpdateGuardian, operationData, salt);
        assertFalse(harness.getUsedNonce(cancelNonce), "cancel nonce should remain unused");
    }

    /// @dev Verifies OGB-CGU-9: cancel signatures for pending guardian A fail after pending guardian changes to B.
    function test_OGB_CGU_9__NMGUB_GUF_8_signedOperationDataBinding_rejectsChangedPendingGuardian() public {
        // Setup
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        _initiatePendingGuardianUpdate(NEW_GUARDIAN_A, 3907);
        (AdminAuthParams memory auth, bytes memory operationDataA) = _buildCancelGuardianUpdateAuth({
            pendingGuardian: NEW_GUARDIAN_A,
            salt: 3009,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        guardianStateHarness.setPendingGuardian(NEW_GUARDIAN_B);
        guardianStateHarness.setPendingGuardianUpdateTimestamp(block.timestamp + 1 days);
        guardianStateHarness.setIsGuardianUpdateReadyForAcceptance(false);
        bytes memory operationDataB = abi.encode(NEW_GUARDIAN_B);

        // Call
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.cancelGuardianUpdate(auth);

        // Verify
        uint256 nonceA = _computeGuardianNonce(OperationType.CancelUpdateGuardian, operationDataA, 3009);
        uint256 nonceB = _computeGuardianNonce(OperationType.CancelUpdateGuardian, operationDataB, 3009);
        assertFalse(harness.getUsedNonce(nonceA), "signed payload nonce should remain unused");
        assertFalse(harness.getUsedNonce(nonceB), "mutated pending payload nonce should remain unused");
    }

    /// @dev Verifies OGB-CGU-10: `NoPendingGuardianUpdate` downstream revert rolls back nonce usage.
    function test_OGB_CGU_10__NMGUB_GUF_10_noPendingRevert_rollsBackNonce() public {
        // Setup
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        (AdminAuthParams memory auth, bytes memory operationData) = _buildCancelGuardianUpdateAuth({
            pendingGuardian: address(0),
            salt: 3010,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 nonce = _computeGuardianNonce(OperationType.CancelUpdateGuardian, operationData, 3010);

        // Call
        vm.expectRevert(IOrganizationGuardian.NoPendingGuardianUpdate.selector);
        vm.prank(GUARDIAN);
        harness.cancelGuardianUpdate(auth);

        // Verify
        assertFalse(harness.getUsedNonce(nonce), "nonce should rollback on no-pending downstream revert");
    }

    /// @dev Verifies `OrganizationGuardianBase.cancelGuardianUpdate` can cancel the same pending guardian twice with
    /// different salts when the pending value is recreated in between.
    function test_NMGUB_GUF_6_cancelGuardianUpdate_samePendingGuardianDifferentSalts_canCancelTwiceAcrossReinitiation()
        public
    {
        // Setup: create one pending guardian update, prepare two cancel salts for the same guardian, and prepare a
        // re-initiation step between the cancels.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        _initiatePendingGuardianUpdate(NEW_GUARDIAN_A, 3910);
        (AdminAuthParams memory firstCancelAuth, bytes memory operationData) = _buildCancelGuardianUpdateAuth({
            pendingGuardian: NEW_GUARDIAN_A,
            salt: 3011,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        (AdminAuthParams memory secondCancelAuth,) = _buildCancelGuardianUpdateAuth({
            pendingGuardian: NEW_GUARDIAN_A,
            salt: 3012,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        (AdminAuthParams memory reinitiateAuth,) = _buildInitiateGuardianUpdateAuth({
            newGuardian: NEW_GUARDIAN_A,
            salt: 3013,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 firstNonce = _computeGuardianNonce(OperationType.CancelUpdateGuardian, operationData, 3011);
        uint256 secondNonce = _computeGuardianNonce(OperationType.CancelUpdateGuardian, operationData, 3012);

        // Call: cancel once, recreate the identical pending guardian tuple, then cancel again with a different salt.
        vm.prank(GUARDIAN);
        harness.cancelGuardianUpdate(firstCancelAuth);

        vm.prank(GUARDIAN);
        harness.initiateGuardianUpdate(NEW_GUARDIAN_A, reinitiateAuth);

        vm.prank(GUARDIAN);
        harness.cancelGuardianUpdate(secondCancelAuth);

        // Verify: both cancel nonces are isolated by salt, and the second cancel clears the recreated pending tuple.
        assertTrue(firstNonce != secondNonce, "different salts should isolate cancel nonces");
        assertTrue(harness.getUsedNonce(firstNonce), "first cancel nonce should remain consumed");
        assertTrue(harness.getUsedNonce(secondNonce), "second cancel nonce should be consumed");
        assertEq(harness.pendingGuardian(), address(0), "pending guardian should clear after the second cancel");
        assertEq(harness.pendingGuardianUpdateTimestamp(), 0, "pending timestamp should clear after the second cancel");
        assertFalse(harness.isGuardianUpdateReadyForAcceptance(), "ready flag should remain cleared after re-cancel");
    }

    /// @dev Verifies `OrganizationGuardianBase.cancelGuardianUpdate` can cancel a guardian update after finalize but
    /// before accept, restoring the lifecycle to a fresh re-initiable state. [OGU-GU-4]
    function test_OGU_GU_4__GUARD_INV_8_B_cancelAfterFinalizeBeforeAccept_clearsReadyStateAndAllowsFreshUpdate()
        public
    {
        // Setup: stage a normal guardian update through finalize so the pending guardian is ready for acceptance.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        (AdminAuthParams memory initiateAuth,) = _buildInitiateGuardianUpdateAuth({
            newGuardian: NEW_GUARDIAN_A,
            salt: 3_201,
            expiration: type(uint256).max,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        harness.initiateGuardianUpdate(NEW_GUARDIAN_A, initiateAuth);

        vm.warp(block.timestamp + ADMIN_OPERATION_TIMELOCK);
        (AdminAuthParams memory finalizeAuth,) = _buildFinalizeGuardianUpdateAuth({
            pendingGuardian: NEW_GUARDIAN_A,
            salt: 3_202,
            expiration: type(uint256).max,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        harness.finalizeGuardianUpdate(finalizeAuth);

        (AdminAuthParams memory cancelAuth,) = _buildCancelGuardianUpdateAuth({
            pendingGuardian: NEW_GUARDIAN_A,
            salt: 3_203,
            expiration: type(uint256).max,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        (AdminAuthParams memory reinitiateAuth,) = _buildInitiateGuardianUpdateAuth({
            newGuardian: NEW_GUARDIAN_B,
            salt: 3_204,
            expiration: type(uint256).max,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: cancel after finalize but before accept, then immediately start a fresh guardian-update lifecycle.
        vm.prank(GUARDIAN);
        harness.cancelGuardianUpdate(cancelAuth);

        vm.prank(GUARDIAN);
        harness.initiateGuardianUpdate(NEW_GUARDIAN_B, reinitiateAuth);

        // Verify: the finalized-but-unaccepted state is cleared by cancel, and a fresh pending guardian can be staged
        // right away with a new auth salt.
        uint256 pendingTimestamp = harness.pendingGuardianUpdateTimestamp();
        assertEq(harness.pendingGuardian(), NEW_GUARDIAN_B, "fresh initiate should stage the new guardian");
        assertGt(pendingTimestamp, block.timestamp, "fresh initiate should stage a future pending timestamp");
        assertEq(
            pendingTimestamp - block.timestamp,
            guardianStateHarness.getAdminOperationTimelockDurationSeconds(),
            "fresh initiate should offset the pending timestamp by the admin timelock"
        );
        assertFalse(harness.isGuardianUpdateReadyForAcceptance(), "fresh initiate should reset ready-for-acceptance");
        assertEq(harness.guardian(), GUARDIAN, "guardian should remain unchanged until a later accept step");
    }
}
