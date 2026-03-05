// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {IOrganizationSignatures} from "interfaces/organization/IOrganizationSignatures.sol";
import {TimelockUtils} from "libraries/TimelockUtils.sol";
import {
    OrganizationGuardianRecoveryBaseSuiteBase
} from "test/organization/base/OrganizationGuardianRecoveryBase/OrganizationGuardianRecoveryBaseSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Unit tests for `OrganizationGuardianRecoveryBase.initiateInitializeGuardianRecovery`.
 */
contract OrganizationGuardianRecoveryBaseInitiateInitializeGuardianRecoveryTest is
    OrganizationGuardianRecoveryBaseSuiteBase
{
    /// @dev Verifies `OrganizationGuardianRecoveryBase.initiateInitializeGuardianRecovery` reverts when called by a
    /// non-guardian.
    function test_OGRB_IIGR_1_nonGuardianCaller_revertsOnlyGuardian() public {
        // Setup: start from clean recovery state, set admin/member threshold, and prepare signed admin auth.
        recoveryStateHarness.resetGuardianRecoveryStorage();
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        (AdminAuthParams memory auth,) = _buildInitiateInitializeGuardianRecoveryAuth({
            recoveryAddress: GUARDIAN_RECOVERY_ADDRESS,
            timelockDurationSeconds: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 11_001,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: initiate deferred recovery initialization as `NON_GUARDIAN`, expecting revert from the guardian-only
        // gate.
        _expectOnlyGuardianRevert(NON_GUARDIAN);
        vm.prank(NON_GUARDIAN);
        harness.initiateInitializeGuardianRecovery(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, auth);

        // Verify: pending init timestamp remains clear.
        assertEq(
            harness.getGuardianRecoveryState().pendingInit.pendingTimestamp,
            0,
            "pending init timestamp should remain clear"
        );
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.initiateInitializeGuardianRecovery` insufficient admin
    /// signatures revert.
    function test_OGRB_IIGR_2_insufficientAdminSignatures_reverts() public {
        // Setup: start from clean recovery state, set admin/member threshold, and prepare signed admin auth.
        recoveryStateHarness.resetGuardianRecoveryStorage();
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});
        (AdminAuthParams memory auth,) = _buildInitiateInitializeGuardianRecoveryAuth({
            recoveryAddress: GUARDIAN_RECOVERY_ADDRESS,
            timelockDurationSeconds: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 11_002,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: initiate deferred recovery initialization as `GUARDIAN`, expecting `InsufficientAdminAuthorization`
        // revert.
        vm.expectRevert(IOrganizationAdmin.InsufficientAdminAuthorization.selector);
        vm.prank(GUARDIAN);
        harness.initiateInitializeGuardianRecovery(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, auth);

        // Verify: pending init timestamp remains clear.
        assertEq(
            harness.getGuardianRecoveryState().pendingInit.pendingTimestamp,
            0,
            "pending init timestamp should remain clear"
        );
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.initiateInitializeGuardianRecovery` successful nonce replay
    /// reverts with `NonceAlreadyUsed`.
    function test_OGRB_IIGR_3_replaySameNonce_revertsNonceAlreadyUsed() public {
        // Setup: start from clean recovery state, set admin/member threshold, and prepare signed admin auth.
        recoveryStateHarness.resetGuardianRecoveryStorage();
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        (AdminAuthParams memory auth, bytes memory operationData) = _buildInitiateInitializeGuardianRecoveryAuth({
            recoveryAddress: GUARDIAN_RECOVERY_ADDRESS,
            timelockDurationSeconds: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 11_003,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 nonce = _computeRecoveryNonce(OperationType.InitiateInitializeGuardianRecovery, operationData, 11_003);

        // Call: initiate deferred recovery initialization as `GUARDIAN`.
        vm.prank(GUARDIAN);
        harness.initiateInitializeGuardianRecovery(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, auth);

        // Verify: nonce is consumed on successful initiate-init.
        assertTrue(harness.getUsedNonce(nonce), "nonce should be consumed on successful initiate-init");
        vm.expectRevert(abi.encodeWithSelector(IOrganizationSignatures.NonceAlreadyUsed.selector, nonce));
        vm.prank(GUARDIAN);
        harness.initiateInitializeGuardianRecovery(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, auth);
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.initiateInitializeGuardianRecovery` initiate op-type/data
    /// binding with approval=true delegates and writes pending state.
    function test_OGRB_IIGR_4__OGRB_IIGR_5__OGRB_IIGR_6__OGRB_IIGR_7_approvalFlowBindsOpDataAndDelegates() public {
        // Setup: start from clean recovery state, set admin/member threshold, and prepare signed admin auth.
        recoveryStateHarness.resetGuardianRecoveryStorage();
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        uint256 expectedCanFinalizeAt = block.timestamp + ADMIN_OPERATION_TIMELOCK;
        (AdminAuthParams memory auth, bytes memory operationDataA) = _buildInitiateInitializeGuardianRecoveryAuth({
            recoveryAddress: GUARDIAN_RECOVERY_ADDRESS,
            timelockDurationSeconds: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 11_004,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        bytes memory operationDataB = abi.encode(GUARDIAN_RECOVERY_ADDRESS_B, GUARDIAN_RECOVERY_TIMELOCK);
        uint256 initiateNonce =
            _computeRecoveryNonce(OperationType.InitiateInitializeGuardianRecovery, operationDataA, 11_004);
        uint256 finalizeNonce =
            _computeRecoveryNonce(OperationType.FinalizeInitializeGuardianRecovery, operationDataA, 11_004);
        uint256 otherTupleNonce =
            _computeRecoveryNonce(OperationType.InitiateInitializeGuardianRecovery, operationDataB, 11_004);

        // Call: initiate deferred recovery initialization as `GUARDIAN`.
        vm.prank(GUARDIAN);
        harness.initiateInitializeGuardianRecovery(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, auth);

        // Verify: initiate nonce is consumed; finalize nonce remains unused.
        assertTrue(harness.getUsedNonce(initiateNonce), "initiate nonce should be consumed");
        assertFalse(harness.getUsedNonce(finalizeNonce), "finalize nonce should remain unused");
        assertFalse(harness.getUsedNonce(otherTupleNonce), "different tuple nonce should remain unused");

        assertEq(
            harness.getGuardianRecoveryState().pendingInit.pendingRecoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS,
            "pending init recovery address should match operationData"
        );
        assertEq(
            harness.getGuardianRecoveryState().pendingInit.pendingTimelockDurationSeconds,
            GUARDIAN_RECOVERY_TIMELOCK,
            "pending init timelock should match operationData"
        );
        assertEq(
            harness.getGuardianRecoveryState().pendingInit.pendingTimestamp,
            expectedCanFinalizeAt,
            "pending init timestamp should be computed via admin-operation timelock"
        );
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.initiateInitializeGuardianRecovery` downstream revert rolls back
    /// nonce and same signed request succeeds after state fix.
    function test_OGRB_IIGR_8_downstreamRevert_rollsBackNonceAndRetrySucceeds() public {
        // Setup: set admin/member threshold and prepare signed admin auth.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        (AdminAuthParams memory auth, bytes memory operationData) = _buildInitiateInitializeGuardianRecoveryAuth({
            recoveryAddress: GUARDIAN_RECOVERY_ADDRESS_B,
            timelockDurationSeconds: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 11_008,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 nonce = _computeRecoveryNonce(OperationType.InitiateInitializeGuardianRecovery, operationData, 11_008);

        // Call: initiate deferred recovery initialization as `GUARDIAN`, expecting `GuardianRecoveryAlreadyConfigured`
        // revert.
        vm.expectRevert(IOrganizationGuardianRecovery.GuardianRecoveryAlreadyConfigured.selector);
        vm.prank(GUARDIAN);
        harness.initiateInitializeGuardianRecovery(GUARDIAN_RECOVERY_ADDRESS_B, GUARDIAN_RECOVERY_TIMELOCK, auth);

        // Verify: nonce should rollback on downstream library revert; same signed request should succeed once root
        // cause is fixed.
        assertFalse(harness.getUsedNonce(nonce), "nonce should rollback on downstream library revert");

        recoveryStateHarness.resetGuardianRecoveryStorage();
        vm.prank(GUARDIAN);
        harness.initiateInitializeGuardianRecovery(GUARDIAN_RECOVERY_ADDRESS_B, GUARDIAN_RECOVERY_TIMELOCK, auth);

        assertTrue(harness.getUsedNonce(nonce), "same signed request should succeed once root cause is fixed");
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.initiateInitializeGuardianRecovery` signed operationData is
    /// bound to recoveryAddress and timelock tuple.
    function test_OGRB_IIGR_9__OGRB_IIGR_10_signedOperationDataBoundToAddressAndTimelock_rejectsMutations() public {
        // Setup: start from clean recovery state, set admin/member threshold, and prepare signed admin auth.
        recoveryStateHarness.resetGuardianRecoveryStorage();
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        (AdminAuthParams memory auth, bytes memory signedOperationData) = _buildInitiateInitializeGuardianRecoveryAuth({
            recoveryAddress: GUARDIAN_RECOVERY_ADDRESS,
            timelockDurationSeconds: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 11_009,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        bytes memory mutatedAddressData = abi.encode(GUARDIAN_RECOVERY_ADDRESS_B, GUARDIAN_RECOVERY_TIMELOCK);
        bytes memory mutatedTimelockData = abi.encode(GUARDIAN_RECOVERY_ADDRESS, 3 days);

        // Call: initiate deferred recovery initialization as `GUARDIAN`, expecting `SignerIsNotAdmin` revert.
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.initiateInitializeGuardianRecovery(GUARDIAN_RECOVERY_ADDRESS_B, GUARDIAN_RECOVERY_TIMELOCK, auth);

        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.initiateInitializeGuardianRecovery(GUARDIAN_RECOVERY_ADDRESS, 3 days, auth);

        // Verify: signed nonce remains unused after reverted mutations; mutated-address nonce remains unused.
        uint256 signedNonce =
            _computeRecoveryNonce(OperationType.InitiateInitializeGuardianRecovery, signedOperationData, 11_009);
        uint256 addressNonce =
            _computeRecoveryNonce(OperationType.InitiateInitializeGuardianRecovery, mutatedAddressData, 11_009);
        uint256 timelockNonce =
            _computeRecoveryNonce(OperationType.InitiateInitializeGuardianRecovery, mutatedTimelockData, 11_009);
        assertFalse(harness.getUsedNonce(signedNonce), "signed nonce should remain unused after reverted mutations");
        assertFalse(harness.getUsedNonce(addressNonce), "mutated-address nonce should remain unused");
        assertFalse(harness.getUsedNonce(timelockNonce), "mutated-timelock nonce should remain unused");
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.initiateInitializeGuardianRecovery` expired auth reverts, nonce
    /// is not burned, and fresh signatures can reuse same nonce.
    function test_OGRB_IIGR_11_expiredAuth_revertsWithoutBurningNonce_andFreshSignaturesSucceed() public {
        // Setup: start from clean recovery state, set admin/member threshold, and prepare signed admin auth.
        recoveryStateHarness.resetGuardianRecoveryStorage();
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        (AdminAuthParams memory expiredAuth, bytes memory operationData) = _buildInitiateInitializeGuardianRecoveryAuth({
            recoveryAddress: GUARDIAN_RECOVERY_ADDRESS,
            timelockDurationSeconds: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 11_011,
            expiration: block.timestamp - 1,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 nonce = _computeRecoveryNonce(OperationType.InitiateInitializeGuardianRecovery, operationData, 11_011);

        // Call: initiate deferred recovery initialization as `GUARDIAN`, expecting authorization/state-validation
        // revert.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdmin.AdminOperationExpired.selector, block.timestamp - 1, block.timestamp
            )
        );
        vm.prank(GUARDIAN);
        harness.initiateInitializeGuardianRecovery(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, expiredAuth);

        // Verify: expired auth does not burn nonce.
        assertFalse(harness.getUsedNonce(nonce), "expired auth must not burn nonce");

        (AdminAuthParams memory freshAuth,) = _buildInitiateInitializeGuardianRecoveryAuth({
            recoveryAddress: GUARDIAN_RECOVERY_ADDRESS,
            timelockDurationSeconds: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 11_011,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        harness.initiateInitializeGuardianRecovery(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, freshAuth);
        assertTrue(
            harness.getUsedNonce(nonce), "fresh signatures with same operationType+operationData+salt should work"
        );
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.initiateInitializeGuardianRecovery` rejection signatures cannot
    /// execute initiate-initialize.
    function test_OGRB_IIGR_12_rejectionSignatures_cannotExecuteInitiateInitialize() public {
        // Setup: start from clean recovery state, set admin/member threshold, and prepare signed admin auth.
        recoveryStateHarness.resetGuardianRecoveryStorage();
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        (AdminAuthParams memory rejectionAuth,) = _buildInitiateInitializeGuardianRecoveryAuth({
            recoveryAddress: GUARDIAN_RECOVERY_ADDRESS,
            timelockDurationSeconds: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 11_012,
            expiration: block.timestamp + 1 days,
            isApproval: false,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: initiate deferred recovery initialization as `GUARDIAN`, expecting `SignerIsNotAdmin` revert.
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.initiateInitializeGuardianRecovery(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, rejectionAuth);

        // Verify: rejection signatures does not execute initiation.
        assertEq(
            harness.getGuardianRecoveryState().pendingInit.pendingTimestamp,
            0,
            "rejection signatures must not execute initiation"
        );
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.initiateInitializeGuardianRecovery` signatures for different
    /// operation type cannot authorize initiation.
    function test_OGRB_IIGR_13_signaturesForDifferentOperationType_cannotAuthorizeInitiation() public {
        // Setup: start from clean recovery state and set admin/member threshold.
        recoveryStateHarness.resetGuardianRecoveryStorage();
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        bytes memory operationData = abi.encode(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);
        AdminAuthParams memory wrongAuth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.FinalizeInitializeGuardianRecovery,
            operationData: operationData,
            isApproval: true,
            salt: 11_013,
            expirationTimestamp: block.timestamp + 1 days,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: initiate deferred recovery initialization as `GUARDIAN`, expecting `SignerIsNotAdmin` revert.
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.initiateInitializeGuardianRecovery(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, wrongAuth);

        // Verify: initiate nonce remains unused.
        uint256 initiateNonce =
            _computeRecoveryNonce(OperationType.InitiateInitializeGuardianRecovery, operationData, 11_013);
        assertFalse(harness.getUsedNonce(initiateNonce), "initiate nonce should remain unused");
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.initiateInitializeGuardianRecovery` timelock range for initiate
    /// flow is enforced to [2 days, 30 days].
    function test_OGRB_IIGR_14_timelockOutOfRange_revertsInvalidTimelockDuration() public {
        // Setup: start from clean recovery state, set admin/member threshold, and prepare signed admin auth.
        recoveryStateHarness.resetGuardianRecoveryStorage();
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        (AdminAuthParams memory belowMinAuth,) = _buildInitiateInitializeGuardianRecoveryAuth({
            recoveryAddress: GUARDIAN_RECOVERY_ADDRESS,
            timelockDurationSeconds: 1 days,
            salt: 11_014,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        (AdminAuthParams memory aboveMaxAuth,) = _buildInitiateInitializeGuardianRecoveryAuth({
            recoveryAddress: GUARDIAN_RECOVERY_ADDRESS,
            timelockDurationSeconds: 31 days,
            salt: 11_015,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: initiate deferred recovery initialization as `GUARDIAN`, expecting authorization/state-validation
        // revert.
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                1 days,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        vm.prank(GUARDIAN);
        harness.initiateInitializeGuardianRecovery(GUARDIAN_RECOVERY_ADDRESS, 1 days, belowMinAuth);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                31 days,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        vm.prank(GUARDIAN);
        harness.initiateInitializeGuardianRecovery(GUARDIAN_RECOVERY_ADDRESS, 31 days, aboveMaxAuth);

        // Verify: out-of-range timelock should not create pending init state.
        assertEq(
            harness.getGuardianRecoveryState().pendingInit.pendingTimestamp,
            0,
            "out-of-range timelock should not create pending init state"
        );
    }
}
