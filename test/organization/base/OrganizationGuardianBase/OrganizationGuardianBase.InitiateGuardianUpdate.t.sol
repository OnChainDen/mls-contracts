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
 * @dev Unit tests for `OrganizationGuardianBase.initiateGuardianUpdate`.
 */
contract OrganizationGuardianBaseInitiateGuardianUpdateTest is OrganizationGuardianBaseSuiteBase {
    /// @dev Verifies OGB-IGU-1: non-guardian caller reverts via `onlyGuardian`.
    function test_OGB_IGU_1_nonGuardianCaller_revertsOnlyGuardian() public {
        // Setup
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        (AdminAuthParams memory auth,) = _buildInitiateGuardianUpdateAuth({
            newGuardian: NEW_GUARDIAN_A,
            salt: 1001,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call
        _expectOnlyGuardianRevert(NON_GUARDIAN);
        vm.prank(NON_GUARDIAN);
        harness.initiateGuardianUpdate(NEW_GUARDIAN_A, auth);

        // Verify
        assertEq(harness.pendingGuardian(), address(0), "pending guardian must remain unchanged");
    }

    /// @dev Verifies OGB-IGU-2: insufficient admin signatures revert.
    function test_OGB_IGU_2_insufficientAdminSignatures_reverts() public {
        // Setup
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});
        (AdminAuthParams memory auth,) = _buildInitiateGuardianUpdateAuth({
            newGuardian: NEW_GUARDIAN_A,
            salt: 1002,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call
        vm.expectRevert(IOrganizationAdmin.InsufficientAdminAuthorization.selector);
        vm.prank(GUARDIAN);
        harness.initiateGuardianUpdate(NEW_GUARDIAN_A, auth);

        // Verify
        assertEq(harness.pendingGuardian(), address(0), "pending guardian must remain unchanged");
    }

    /// @dev Verifies OGB-IGU-3: replaying the same nonce reverts after successful execution.
    function test_OGB_IGU_3_replaySameNonce_revertsNonceAlreadyUsed() public {
        // Setup
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        (AdminAuthParams memory auth, bytes memory operationData) = _buildInitiateGuardianUpdateAuth({
            newGuardian: NEW_GUARDIAN_A,
            salt: 1003,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 nonce = _computeGuardianNonce(OperationType.InitiateUpdateGuardian, operationData, 1003);

        // Call
        vm.prank(GUARDIAN);
        harness.initiateGuardianUpdate(NEW_GUARDIAN_A, auth);

        // Verify
        assertTrue(harness.getUsedNonce(nonce), "nonce should be consumed on success");
        vm.expectRevert(abi.encodeWithSelector(IOrganizationSignatures.NonceAlreadyUsed.selector, nonce));
        vm.prank(GUARDIAN);
        harness.initiateGuardianUpdate(NEW_GUARDIAN_A, auth);
    }

    /// @dev Verifies OGB-IGU-4: the approval path succeeds with `OperationType.InitiateUpdateGuardian`.
    function test_OGB_IGU_4_operationTypeInitiateUpdateGuardian_authorizesExecution() public {
        // Setup
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        (AdminAuthParams memory auth, bytes memory operationData) = _buildInitiateGuardianUpdateAuth({
            newGuardian: NEW_GUARDIAN_A,
            salt: 1004,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 initiateNonce = _computeGuardianNonce(OperationType.InitiateUpdateGuardian, operationData, 1004);
        uint256 finalizeNonce = _computeGuardianNonce(OperationType.FinalizeUpdateGuardian, operationData, 1004);

        // Call
        vm.prank(GUARDIAN);
        harness.initiateGuardianUpdate(NEW_GUARDIAN_A, auth);

        // Verify
        assertTrue(harness.getUsedNonce(initiateNonce), "initiate nonce should be consumed");
        assertFalse(harness.getUsedNonce(finalizeNonce), "finalize nonce should remain unused");
    }

    /// @dev Verifies OGB-IGU-5: operation data binding includes `newGuardian`.
    function test_OGB_IGU_5_operationDataEncodesNewGuardian_bindingHolds() public {
        // Setup
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        (AdminAuthParams memory auth, bytes memory operationDataA) = _buildInitiateGuardianUpdateAuth({
            newGuardian: NEW_GUARDIAN_A,
            salt: 1005,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        bytes memory operationDataB = abi.encode(NEW_GUARDIAN_B);

        // Call
        vm.prank(GUARDIAN);
        harness.initiateGuardianUpdate(NEW_GUARDIAN_A, auth);

        // Verify
        uint256 nonceA = _computeGuardianNonce(OperationType.InitiateUpdateGuardian, operationDataA, 1005);
        uint256 nonceB = _computeGuardianNonce(OperationType.InitiateUpdateGuardian, operationDataB, 1005);
        assertTrue(harness.getUsedNonce(nonceA), "signed payload nonce should be consumed");
        assertFalse(harness.getUsedNonce(nonceB), "different newGuardian payload nonce should remain unused");
    }

    /// @dev Verifies OGB-IGU-6: successful base call delegates to library and writes pending state.
    function test_OGB_IGU_6_delegatesToLibrary_andWritesPendingState() public {
        // Setup
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        (AdminAuthParams memory auth,) = _buildInitiateGuardianUpdateAuth({
            newGuardian: NEW_GUARDIAN_A,
            salt: 1006,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 expectedFinalizeAt = block.timestamp + ADMIN_OPERATION_TIMELOCK;

        // Call
        vm.prank(GUARDIAN);
        harness.initiateGuardianUpdate(NEW_GUARDIAN_A, auth);

        // Verify
        assertEq(harness.pendingGuardian(), NEW_GUARDIAN_A, "pending guardian should match new guardian");
        assertEq(
            harness.pendingGuardianUpdateTimestamp(),
            expectedFinalizeAt,
            "pending timestamp should equal block.timestamp + timelock"
        );
        assertFalse(harness.isGuardianUpdateReadyForAcceptance(), "ready-for-acceptance should be false after initiate");
    }

    /// @dev Verifies OGB-IGU-7: rejection signatures cannot execute initiation.
    function test_OGB_IGU_7_rejectionSignatures_cannotExecuteInitiation() public {
        // Setup
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        (AdminAuthParams memory rejectionAuth, bytes memory operationData) = _buildInitiateGuardianUpdateAuth({
            newGuardian: NEW_GUARDIAN_A,
            salt: 1007,
            expiration: block.timestamp + 1 days,
            isApproval: false,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.initiateGuardianUpdate(NEW_GUARDIAN_A, rejectionAuth);

        // Verify
        uint256 nonce = _computeGuardianNonce(OperationType.InitiateUpdateGuardian, operationData, 1007);
        assertFalse(harness.getUsedNonce(nonce), "nonce should rollback on failed auth");
    }

    /// @dev Verifies OGB-IGU-8: signatures for a different operation type cannot authorize initiation.
    function test_OGB_IGU_8_differentOperationTypeSignatures_cannotAuthorizeInitiation() public {
        // Setup
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        bytes memory operationData = abi.encode(NEW_GUARDIAN_A);
        uint256 salt = 1008;
        AdminAuthParams memory wrongAuth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.FinalizeUpdateGuardian,
            operationData: operationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: block.timestamp + 1 days,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.initiateGuardianUpdate(NEW_GUARDIAN_A, wrongAuth);

        // Verify
        uint256 initiateNonce = _computeGuardianNonce(OperationType.InitiateUpdateGuardian, operationData, salt);
        uint256 finalizeNonce = _computeGuardianNonce(OperationType.FinalizeUpdateGuardian, operationData, salt);
        assertFalse(harness.getUsedNonce(initiateNonce), "initiate nonce should remain unused");
        assertFalse(harness.getUsedNonce(finalizeNonce), "finalize nonce should remain unused");
    }

    /// @dev Verifies OGB-IGU-9: signatures bound to `newGuardian=A` cannot execute with `newGuardian=B`.
    function test_OGB_IGU_9_signedOperationDataBinding_rejectsMutatedNewGuardian() public {
        // Setup
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        (AdminAuthParams memory auth, bytes memory signedOperationData) = _buildInitiateGuardianUpdateAuth({
            newGuardian: NEW_GUARDIAN_A,
            salt: 1009,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        bytes memory mutatedOperationData = abi.encode(NEW_GUARDIAN_B);

        // Call
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.initiateGuardianUpdate(NEW_GUARDIAN_B, auth);

        // Verify
        uint256 signedNonce = _computeGuardianNonce(OperationType.InitiateUpdateGuardian, signedOperationData, 1009);
        uint256 mutatedNonce = _computeGuardianNonce(OperationType.InitiateUpdateGuardian, mutatedOperationData, 1009);
        assertFalse(harness.getUsedNonce(signedNonce), "signed payload nonce should remain unused");
        assertFalse(harness.getUsedNonce(mutatedNonce), "mutated payload nonce should remain unused");
    }

    /// @dev Verifies OGB-IGU-10: downstream `GuardianUpdateAlreadyPending` revert rolls back nonce and allows retry.
    function test_OGB_IGU_10_downstreamPendingRevert_rollsBackNonceAndAllowsRetry_A() public {
        // Setup
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        guardianStateHarness.setPendingGuardian(NEW_GUARDIAN_B);
        guardianStateHarness.setPendingGuardianUpdateTimestamp(block.timestamp + 1 days);
        guardianStateHarness.setIsGuardianUpdateReadyForAcceptance(false);

        (AdminAuthParams memory auth, bytes memory operationData) = _buildInitiateGuardianUpdateAuth({
            newGuardian: NEW_GUARDIAN_A,
            salt: 1010,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 nonce = _computeGuardianNonce(OperationType.InitiateUpdateGuardian, operationData, 1010);

        // Call
        vm.expectRevert(IOrganizationGuardian.GuardianUpdateAlreadyPending.selector);
        vm.prank(GUARDIAN);
        harness.initiateGuardianUpdate(NEW_GUARDIAN_A, auth);

        // Verify
        assertFalse(harness.getUsedNonce(nonce), "nonce should rollback on downstream revert");

        guardianStateHarness.setPendingGuardian(address(0));
        guardianStateHarness.setPendingGuardianUpdateTimestamp(0);
        guardianStateHarness.setIsGuardianUpdateReadyForAcceptance(false);

        vm.prank(GUARDIAN);
        harness.initiateGuardianUpdate(NEW_GUARDIAN_A, auth);
        assertTrue(harness.getUsedNonce(nonce), "same signed request should succeed after fixing pending state");
        assertEq(harness.pendingGuardian(), NEW_GUARDIAN_A, "pending guardian should be updated on retry");
    }

    /// @dev Verifies OGB-IGU-10: downstream `InvalidGuardianAddress` revert rolls back nonce usage.
    function test_OGB_IGU_10_downstreamInvalidGuardianRevert_rollsBackNonce_B() public {
        // Setup
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        (AdminAuthParams memory auth, bytes memory operationData) = _buildInitiateGuardianUpdateAuth({
            newGuardian: address(0),
            salt: 1011,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 nonce = _computeGuardianNonce(OperationType.InitiateUpdateGuardian, operationData, 1011);

        // Call
        vm.expectRevert(IOrganizationGuardian.InvalidGuardianAddress.selector);
        vm.prank(GUARDIAN);
        harness.initiateGuardianUpdate(address(0), auth);

        // Verify
        assertFalse(harness.getUsedNonce(nonce), "nonce should rollback on invalid guardian downstream revert");
    }
}
