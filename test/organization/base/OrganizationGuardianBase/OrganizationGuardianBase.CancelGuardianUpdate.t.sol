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
    function test_OGB_CGU_1_nonGuardianCaller_revertsOnlyGuardian() public {
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
    function test_OGB_CGU_3_replaySameNonce_revertsNonceAlreadyUsed() public {
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

    /// @dev Verifies OGB-CGU-6: successful base call delegates to library and clears pending state.
    function test_OGB_CGU_6_delegatesToLibrary_andClearsPendingState() public {
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

    /// @dev Verifies OGB-CGU-8: signatures for a different operation type cannot authorize cancellation.
    function test_OGB_CGU_8_differentOperationTypeSignatures_cannotAuthorizeCancellation() public {
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
    function test_OGB_CGU_9_signedOperationDataBinding_rejectsChangedPendingGuardian() public {
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
    function test_OGB_CGU_10_noPendingRevert_rollsBackNonce() public {
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
}
