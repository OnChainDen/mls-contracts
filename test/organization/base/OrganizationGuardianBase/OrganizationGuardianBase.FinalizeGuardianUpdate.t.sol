// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {IOrganizationAdminOperationTimelock} from "interfaces/organization/IOrganizationAdminOperationTimelock.sol";
import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
import {IOrganizationSignatures} from "interfaces/organization/IOrganizationSignatures.sol";
import {
    OrganizationGuardianBaseSuiteBase
} from "test/organization/base/OrganizationGuardianBase/OrganizationGuardianBaseSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Unit tests for `OrganizationGuardianBase.finalizeGuardianUpdate`.
 */
contract OrganizationGuardianBaseFinalizeGuardianUpdateTest is OrganizationGuardianBaseSuiteBase {
    /// @dev Verifies OGB-FGU-1: non-guardian caller reverts via `onlyGuardian`.
    function test_OGB_FGU_1_nonGuardianCaller_revertsOnlyGuardian() public {
        // Setup
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        guardianStateHarness.setPendingGuardian(NEW_GUARDIAN_A);
        guardianStateHarness.setPendingGuardianUpdateTimestamp(block.timestamp);
        (AdminAuthParams memory auth,) = _buildFinalizeGuardianUpdateAuth({
            pendingGuardian: NEW_GUARDIAN_A,
            salt: 2001,
            expiration: type(uint256).max,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call
        _expectOnlyGuardianRevert(NON_GUARDIAN);
        vm.prank(NON_GUARDIAN);
        harness.finalizeGuardianUpdate(auth);

        // Verify
        assertFalse(harness.isGuardianUpdateReadyForAcceptance(), "ready flag must remain unchanged");
    }

    /// @dev Verifies OGB-FGU-2: insufficient admin signatures revert.
    function test_OGB_FGU_2_insufficientAdminSignatures_reverts() public {
        // Setup
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});
        guardianStateHarness.setPendingGuardian(NEW_GUARDIAN_A);
        guardianStateHarness.setPendingGuardianUpdateTimestamp(block.timestamp);
        (AdminAuthParams memory auth,) = _buildFinalizeGuardianUpdateAuth({
            pendingGuardian: NEW_GUARDIAN_A,
            salt: 2002,
            expiration: type(uint256).max,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call
        vm.expectRevert(IOrganizationAdmin.InsufficientAdminAuthorization.selector);
        vm.prank(GUARDIAN);
        harness.finalizeGuardianUpdate(auth);

        // Verify
        assertFalse(harness.isGuardianUpdateReadyForAcceptance(), "ready flag must remain false");
    }

    /// @dev Verifies OGB-FGU-3: replaying the same nonce reverts after successful execution.
    function test_OGB_FGU_3__NMGUB_GUF_3_replaySameNonce_revertsNonceAlreadyUsed() public {
        // Setup
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        _initiatePendingGuardianUpdate(NEW_GUARDIAN_A, 2901);
        vm.warp(block.timestamp + ADMIN_OPERATION_TIMELOCK);
        (AdminAuthParams memory auth, bytes memory operationData) = _buildFinalizeGuardianUpdateAuth({
            pendingGuardian: NEW_GUARDIAN_A,
            salt: 2003,
            expiration: type(uint256).max,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 nonce = _computeGuardianNonce(OperationType.FinalizeUpdateGuardian, operationData, 2003);

        // Call
        vm.prank(GUARDIAN);
        harness.finalizeGuardianUpdate(auth);

        // Verify
        assertTrue(harness.getUsedNonce(nonce), "nonce should be consumed on successful finalize");
        vm.expectRevert(abi.encodeWithSelector(IOrganizationSignatures.NonceAlreadyUsed.selector, nonce));
        vm.prank(GUARDIAN);
        harness.finalizeGuardianUpdate(auth);
    }

    /// @dev Verifies OGB-FGU-4: the approval path succeeds with `OperationType.FinalizeUpdateGuardian`.
    function test_OGB_FGU_4_operationTypeFinalizeUpdateGuardian_authorizesExecution() public {
        // Setup
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        _initiatePendingGuardianUpdate(NEW_GUARDIAN_A, 2902);
        vm.warp(block.timestamp + ADMIN_OPERATION_TIMELOCK);
        (AdminAuthParams memory auth, bytes memory operationData) = _buildFinalizeGuardianUpdateAuth({
            pendingGuardian: NEW_GUARDIAN_A,
            salt: 2004,
            expiration: type(uint256).max,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 finalizeNonce = _computeGuardianNonce(OperationType.FinalizeUpdateGuardian, operationData, 2004);
        uint256 initiateNonce = _computeGuardianNonce(OperationType.InitiateUpdateGuardian, operationData, 2004);

        // Call
        vm.prank(GUARDIAN);
        harness.finalizeGuardianUpdate(auth);

        // Verify
        assertTrue(harness.getUsedNonce(finalizeNonce), "finalize nonce should be consumed");
        assertFalse(harness.getUsedNonce(initiateNonce), "initiate nonce should remain unused");
    }

    /// @dev Verifies OGB-FGU-5: operation data encodes current pending guardian.
    function test_OGB_FGU_5_operationDataEncodesPendingGuardian_bindingHolds() public {
        // Setup
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        _initiatePendingGuardianUpdate(NEW_GUARDIAN_A, 2903);
        vm.warp(block.timestamp + ADMIN_OPERATION_TIMELOCK);
        (AdminAuthParams memory auth, bytes memory operationDataA) = _buildFinalizeGuardianUpdateAuth({
            pendingGuardian: NEW_GUARDIAN_A,
            salt: 2005,
            expiration: type(uint256).max,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        bytes memory operationDataB = abi.encode(NEW_GUARDIAN_B);

        // Call
        vm.prank(GUARDIAN);
        harness.finalizeGuardianUpdate(auth);

        // Verify
        uint256 nonceA = _computeGuardianNonce(OperationType.FinalizeUpdateGuardian, operationDataA, 2005);
        uint256 nonceB = _computeGuardianNonce(OperationType.FinalizeUpdateGuardian, operationDataB, 2005);
        assertTrue(harness.getUsedNonce(nonceA), "signed pending guardian payload nonce should be consumed");
        assertFalse(harness.getUsedNonce(nonceB), "different pending guardian payload nonce should remain unused");
    }

    /// @dev Verifies OGB-FGU-6: successful base call delegates to library and marks update ready for acceptance.
    function test_OGB_FGU_6_delegatesToLibrary_andMarksReadyForAcceptance() public {
        // Setup
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        _initiatePendingGuardianUpdate(NEW_GUARDIAN_A, 2904);
        vm.warp(block.timestamp + ADMIN_OPERATION_TIMELOCK);
        (AdminAuthParams memory auth,) = _buildFinalizeGuardianUpdateAuth({
            pendingGuardian: NEW_GUARDIAN_A,
            salt: 2006,
            expiration: type(uint256).max,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call
        vm.prank(GUARDIAN);
        harness.finalizeGuardianUpdate(auth);

        // Verify
        assertTrue(harness.isGuardianUpdateReadyForAcceptance(), "ready flag should be true after finalize");
        assertEq(harness.pendingGuardian(), NEW_GUARDIAN_A, "pending guardian should remain unchanged");
        assertEq(harness.guardian(), GUARDIAN, "guardian should not change during finalize");
    }

    /// @dev Verifies OGB-FGU-7: rejection signatures cannot execute finalization.
    function test_OGB_FGU_7_rejectionSignatures_cannotExecuteFinalization() public {
        // Setup
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        _initiatePendingGuardianUpdate(NEW_GUARDIAN_A, 2905);
        vm.warp(block.timestamp + ADMIN_OPERATION_TIMELOCK);
        (AdminAuthParams memory auth, bytes memory operationData) = _buildFinalizeGuardianUpdateAuth({
            pendingGuardian: NEW_GUARDIAN_A,
            salt: 2007,
            expiration: type(uint256).max,
            isApproval: false,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.finalizeGuardianUpdate(auth);

        // Verify
        uint256 nonce = _computeGuardianNonce(OperationType.FinalizeUpdateGuardian, operationData, 2007);
        assertFalse(harness.getUsedNonce(nonce), "nonce should rollback on failed auth");
    }

    /// @dev Verifies `OrganizationGuardianBase.finalizeGuardianUpdate` rejects initiate-stage signatures reused
    /// during finalize-stage authorization. [OGU-GU-2]
    function test_OGB_FGU_8__NMGUB_GUF_7__OGU_GU_2_differentOperationTypeSignatures_cannotAuthorizeFinalization()
        public
    {
        // Setup
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        _initiatePendingGuardianUpdate(NEW_GUARDIAN_A, 2906);
        vm.warp(block.timestamp + ADMIN_OPERATION_TIMELOCK);
        bytes memory operationData = abi.encode(NEW_GUARDIAN_A);
        uint256 salt = 2008;
        AdminAuthParams memory wrongAuth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.InitiateUpdateGuardian,
            operationData: operationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: type(uint256).max,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.finalizeGuardianUpdate(wrongAuth);

        // Verify
        uint256 finalizeNonce = _computeGuardianNonce(OperationType.FinalizeUpdateGuardian, operationData, salt);
        assertFalse(harness.getUsedNonce(finalizeNonce), "finalize nonce should remain unused");
        uint256 wrongAuthNonce = _computeGuardianNonce(OperationType.InitiateUpdateGuardian, operationData, salt);
        assertFalse(harness.getUsedNonce(wrongAuthNonce), "wrong auth nonce should remain unused");
    }

    /// @dev Verifies OGB-FGU-9: finalize signatures for pending guardian A fail after pending guardian changes to B.
    function test_OGB_FGU_9__NMGUB_GUF_8_signedOperationDataBinding_rejectsChangedPendingGuardian() public {
        // Setup
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        _initiatePendingGuardianUpdate(NEW_GUARDIAN_A, 2907);
        vm.warp(block.timestamp + ADMIN_OPERATION_TIMELOCK);
        (AdminAuthParams memory auth, bytes memory operationDataA) = _buildFinalizeGuardianUpdateAuth({
            pendingGuardian: NEW_GUARDIAN_A,
            salt: 2009,
            expiration: type(uint256).max,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        guardianStateHarness.setPendingGuardian(NEW_GUARDIAN_B);
        guardianStateHarness.setPendingGuardianUpdateTimestamp(block.timestamp);
        guardianStateHarness.setIsGuardianUpdateReadyForAcceptance(false);
        bytes memory operationDataB = abi.encode(NEW_GUARDIAN_B);

        // Call
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.finalizeGuardianUpdate(auth);

        // Verify
        uint256 nonceA = _computeGuardianNonce(OperationType.FinalizeUpdateGuardian, operationDataA, 2009);
        uint256 nonceB = _computeGuardianNonce(OperationType.FinalizeUpdateGuardian, operationDataB, 2009);
        assertFalse(harness.getUsedNonce(nonceA), "signed payload nonce should remain unused");
        assertFalse(harness.getUsedNonce(nonceB), "mutated pending payload nonce should remain unused");
    }

    /// @dev Verifies `OrganizationGuardianBase.finalizeGuardianUpdate` reverts before the admin timelock expires and
    /// succeeds at the exact boundary without requiring new signatures. [OGU-GU-3]
    function test_OGB_FGU_10__NMGUB_GUF_10__OGU_GU_3_timelockRevert_rollsBackNonceAndAllowsRetry_A() public {
        // Setup
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        _initiatePendingGuardianUpdate(NEW_GUARDIAN_A, 2908);
        uint256 canFinalizeAt = harness.pendingGuardianUpdateTimestamp();
        (AdminAuthParams memory auth, bytes memory operationData) = _buildFinalizeGuardianUpdateAuth({
            pendingGuardian: NEW_GUARDIAN_A,
            salt: 2010,
            expiration: type(uint256).max,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 nonce = _computeGuardianNonce(OperationType.FinalizeUpdateGuardian, operationData, 2010);

        // Call
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdminOperationTimelock.TimelockNotExpired.selector, canFinalizeAt, block.timestamp
            )
        );
        vm.prank(GUARDIAN);
        harness.finalizeGuardianUpdate(auth);

        // Verify
        assertFalse(harness.getUsedNonce(nonce), "nonce should rollback on downstream timelock revert");
        vm.warp(canFinalizeAt);
        vm.prank(GUARDIAN);
        harness.finalizeGuardianUpdate(auth);
        assertTrue(harness.getUsedNonce(nonce), "same signed finalize request should succeed after timelock expiry");
    }

    /// @dev Verifies OGB-FGU-10: `NoPendingGuardianUpdate` revert rolls back nonce usage.
    function test_OGB_FGU_10__NMGUB_GUF_10_noPendingRevert_rollsBackNonce_B() public {
        // Setup
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        (AdminAuthParams memory auth, bytes memory operationData) = _buildFinalizeGuardianUpdateAuth({
            pendingGuardian: address(0),
            salt: 2011,
            expiration: type(uint256).max,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 nonce = _computeGuardianNonce(OperationType.FinalizeUpdateGuardian, operationData, 2011);

        // Call
        vm.expectRevert(IOrganizationGuardian.NoPendingGuardianUpdate.selector);
        vm.prank(GUARDIAN);
        harness.finalizeGuardianUpdate(auth);

        // Verify
        assertFalse(harness.getUsedNonce(nonce), "nonce should rollback on no-pending downstream revert");
    }

    /// @dev Verifies `OrganizationGuardianBase.finalizeGuardianUpdate` can finalize the same pending guardian twice
    /// with different salts before accept/cancel.
    function test_NMGUB_GUF_4_finalizeGuardianUpdate_samePendingGuardianDifferentSalts_canFinalizeTwice() public {
        // Setup: create one pending guardian update, wait through timelock, and build two finalize auth payloads with
        // distinct salts for the same pending guardian.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        _initiatePendingGuardianUpdate(NEW_GUARDIAN_A, 2910);
        vm.warp(block.timestamp + ADMIN_OPERATION_TIMELOCK);
        (AdminAuthParams memory firstAuth, bytes memory operationData) = _buildFinalizeGuardianUpdateAuth({
            pendingGuardian: NEW_GUARDIAN_A,
            salt: 2012,
            expiration: type(uint256).max,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        (AdminAuthParams memory secondAuth,) = _buildFinalizeGuardianUpdateAuth({
            pendingGuardian: NEW_GUARDIAN_A,
            salt: 2013,
            expiration: type(uint256).max,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 firstNonce = _computeGuardianNonce(OperationType.FinalizeUpdateGuardian, operationData, 2012);
        uint256 secondNonce = _computeGuardianNonce(OperationType.FinalizeUpdateGuardian, operationData, 2013);

        // Call: finalize the identical pending guardian tuple twice using two different admin-auth salts.
        vm.prank(GUARDIAN);
        harness.finalizeGuardianUpdate(firstAuth);

        vm.prank(GUARDIAN);
        harness.finalizeGuardianUpdate(secondAuth);

        // Verify: each finalize consumes its own nonce while keeping the same guardian update ready for acceptance.
        assertTrue(firstNonce != secondNonce, "different salts should isolate finalize nonces");
        assertTrue(harness.getUsedNonce(firstNonce), "first finalize nonce should be consumed");
        assertTrue(harness.getUsedNonce(secondNonce), "second finalize nonce should be consumed");
        assertTrue(harness.isGuardianUpdateReadyForAcceptance(), "pending guardian should remain ready for acceptance");
        assertEq(harness.pendingGuardian(), NEW_GUARDIAN_A, "pending guardian should remain unchanged");
        assertEq(harness.guardian(), GUARDIAN, "finalize should not directly rotate guardian");
    }
}
