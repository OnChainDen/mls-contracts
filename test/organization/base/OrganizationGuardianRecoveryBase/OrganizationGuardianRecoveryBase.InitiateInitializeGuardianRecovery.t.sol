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
    function test_nonGuardianCaller_revertsOnlyGuardian() public {
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
    function test_insufficientAdminSignatures_reverts() public {
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
    function test_replaySameNonce_revertsNonceAlreadyUsed() public {
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

    /// @dev Verifies deferred guardian-recovery initialization consumes the correct initiate nonce and stages the
    /// pending tuple that later finalization will commit.
    function test_approvalFlowBindsOpDataAndDelegates() public {
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

    /// @dev Verifies `OrganizationGuardianRecoveryBase.initiateInitializeGuardianRecovery` fails closed once guardian
    /// recovery is already configured and does not burn the signed nonce.
    function test_downstreamRevert_rollsBackNonceAndRetrySucceeds() public {
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
    function test_signedOperationDataBoundToAddressAndTimelock_rejectsMutations() public {
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
    function test_expiredAuth_revertsWithoutBurningNonce_andFreshSignaturesSucceed() public {
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
    function test_rejectionSignatures_cannotExecuteInitiateInitialize() public {
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
    function test_signaturesForDifferentOperationType_cannotAuthorizeInitiation() public {
        // Setup: start from clean recovery state and set admin/member threshold.
        recoveryStateHarness.resetGuardianRecoveryStorage();
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        bytes memory operationData = abi.encode(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);
        AdminAuthParams memory wrongAuth = _buildAdminAuthParamsForEoa({
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
    function test_timelockOutOfRange_revertsInvalidTimelockDuration() public {
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

    /// @dev Verifies cancelled deferred guardian-recovery initialization leaves the mechanism re-initiable with a new
    /// auth salt for the same tuple.
    function test_initiateInitializeGuardianRecovery_sameParamsDifferentSalts_canSucceedAcrossReinitiation() public {
        // Setup: reset storage, configure one-admin auth, and prepare two initiate salts around an intermediate
        // cancel.
        recoveryStateHarness.resetGuardianRecoveryStorage();
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        (AdminAuthParams memory firstInitiateAuth, bytes memory operationData) = _buildInitiateInitializeGuardianRecoveryAuth({
            recoveryAddress: GUARDIAN_RECOVERY_ADDRESS_B,
            timelockDurationSeconds: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 11_020,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        (AdminAuthParams memory secondInitiateAuth,) = _buildInitiateInitializeGuardianRecoveryAuth({
            recoveryAddress: GUARDIAN_RECOVERY_ADDRESS_B,
            timelockDurationSeconds: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 11_022,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 firstNonce =
            _computeRecoveryNonce(OperationType.InitiateInitializeGuardianRecovery, operationData, 11_020);
        uint256 secondNonce =
            _computeRecoveryNonce(OperationType.InitiateInitializeGuardianRecovery, operationData, 11_022);

        // Call: initiate once, cancel the pending deferred-init tuple, then re-initiate the identical params with a
        // new admin-auth salt.
        vm.prank(GUARDIAN);
        harness.initiateInitializeGuardianRecovery(
            GUARDIAN_RECOVERY_ADDRESS_B, GUARDIAN_RECOVERY_TIMELOCK, firstInitiateAuth
        );

        // Build cancelAuth after initiation so the attempt ID in the digest matches the incremented counter.
        (AdminAuthParams memory cancelAuth,) = _buildCancelInitializeGuardianRecoveryAuth({
            pendingAddress: GUARDIAN_RECOVERY_ADDRESS_B,
            pendingTimelock: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 11_021,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        harness.cancelInitializeGuardianRecovery(cancelAuth);

        vm.prank(GUARDIAN);
        harness.initiateInitializeGuardianRecovery(
            GUARDIAN_RECOVERY_ADDRESS_B, GUARDIAN_RECOVERY_TIMELOCK, secondInitiateAuth
        );

        // Verify: both initiate nonces are isolated by salt, and the second call restores the same pending tuple.
        assertTrue(firstNonce != secondNonce, "different salts should isolate initiate nonces");
        assertTrue(harness.getUsedNonce(firstNonce), "first initiate nonce should remain consumed");
        assertTrue(harness.getUsedNonce(secondNonce), "second initiate nonce should be consumed");
        assertEq(
            harness.getGuardianRecoveryState().pendingInit.pendingRecoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS_B,
            "re-initiated pending address should match the original tuple"
        );
        assertEq(
            harness.getGuardianRecoveryState().pendingInit.pendingTimelockDurationSeconds,
            GUARDIAN_RECOVERY_TIMELOCK,
            "re-initiated pending timelock should match the original tuple"
        );
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.initiateInitializeGuardianRecovery` invalid params and
    /// already-pending branches both roll back nonce usage.
    function test_initiateInitializeGuardianRecovery_invalidParamsAndPendingState_rollBackNonce() public {
        // Setup: reset storage, configure one-admin auth, and prepare one invalid-address payload plus one
        // already-pending payload.
        recoveryStateHarness.resetGuardianRecoveryStorage();
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        (AdminAuthParams memory invalidAddressAuth, bytes memory invalidAddressData) = _buildInitiateInitializeGuardianRecoveryAuth({
            recoveryAddress: address(0),
            timelockDurationSeconds: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 11_023,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 invalidAddressNonce =
            _computeRecoveryNonce(OperationType.InitiateInitializeGuardianRecovery, invalidAddressData, 11_023);

        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, block.timestamp + ADMIN_OPERATION_TIMELOCK
        );
        (AdminAuthParams memory pendingAuth, bytes memory pendingData) = _buildInitiateInitializeGuardianRecoveryAuth({
            recoveryAddress: GUARDIAN_RECOVERY_ADDRESS_B,
            timelockDurationSeconds: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 11_024,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 pendingNonce =
            _computeRecoveryNonce(OperationType.InitiateInitializeGuardianRecovery, pendingData, 11_024);

        // Call: first use an invalid recovery address, then hit the already-pending branch with a valid signed tuple.
        recoveryStateHarness.resetGuardianRecoveryStorage();
        vm.expectRevert(IOrganizationGuardianRecovery.InvalidGuardianRecoveryAddress.selector);
        vm.prank(GUARDIAN);
        harness.initiateInitializeGuardianRecovery(address(0), GUARDIAN_RECOVERY_TIMELOCK, invalidAddressAuth);

        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, block.timestamp + ADMIN_OPERATION_TIMELOCK
        );
        vm.expectRevert(IOrganizationGuardianRecovery.GuardianRecoveryInitializationAlreadyPending.selector);
        vm.prank(GUARDIAN);
        harness.initiateInitializeGuardianRecovery(GUARDIAN_RECOVERY_ADDRESS_B, GUARDIAN_RECOVERY_TIMELOCK, pendingAuth);

        // Verify: both downstream revert branches leave their computed nonces unused and preserve the pending tuple.
        assertFalse(harness.getUsedNonce(invalidAddressNonce), "invalid-address revert should not burn nonce");
        assertFalse(harness.getUsedNonce(pendingNonce), "already-pending revert should not burn nonce");
        assertEq(
            harness.getGuardianRecoveryState().pendingInit.pendingRecoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS,
            "already-pending revert should preserve the existing pending address"
        );
        assertEq(
            harness.getGuardianRecoveryState().pendingInit.pendingTimelockDurationSeconds,
            GUARDIAN_RECOVERY_TIMELOCK,
            "already-pending revert should preserve the existing pending timelock"
        );
    }
}
