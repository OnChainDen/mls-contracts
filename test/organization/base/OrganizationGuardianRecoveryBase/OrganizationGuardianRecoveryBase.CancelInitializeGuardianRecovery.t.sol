// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {IOrganizationSignatures} from "interfaces/organization/IOrganizationSignatures.sol";
import {
    OrganizationGuardianRecoveryBaseSuiteBase
} from "test/organization/base/OrganizationGuardianRecoveryBase/OrganizationGuardianRecoveryBaseSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Unit tests for `OrganizationGuardianRecoveryBase.cancelInitializeGuardianRecovery`.
 */
contract OrganizationGuardianRecoveryBaseCancelInitializeGuardianRecoveryTest is
    OrganizationGuardianRecoveryBaseSuiteBase
{
    /// @dev Verifies `OrganizationGuardianRecoveryBase.cancelInitializeGuardianRecovery` reverts when called by a
    /// non-guardian.
    function test_OGRB_CIGR_1_nonGuardianCaller_revertsOnlyGuardian() public {
        // Setup: start from clean recovery state, seed pending deferred-init tuple, and set admin/member threshold.
        recoveryStateHarness.resetGuardianRecoveryStorage();
        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, block.timestamp + 1
        );
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        (AdminAuthParams memory auth,) = _buildCancelInitializeGuardianRecoveryAuth({
            pendingAddress: GUARDIAN_RECOVERY_ADDRESS,
            pendingTimelock: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 13_001,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: cancel deferred recovery initialization as `NON_GUARDIAN`, expecting revert from the guardian-only gate.
        _expectOnlyGuardianRevert(NON_GUARDIAN);
        vm.prank(NON_GUARDIAN);
        harness.cancelInitializeGuardianRecovery(auth);

        // Verify: pending init remains unchanged.
        assertEq(
            harness.getGuardianRecoveryState().pendingInit.pendingTimestamp,
            block.timestamp + 1,
            "pending init should remain unchanged"
        );
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.cancelInitializeGuardianRecovery` insufficient admin signatures
    /// revert.
    function test_OGRB_CIGR_2_insufficientAdminSignatures_reverts() public {
        // Setup: start from clean recovery state, seed pending deferred-init tuple, and set admin/member threshold.
        recoveryStateHarness.resetGuardianRecoveryStorage();
        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, block.timestamp + 1
        );
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});

        (AdminAuthParams memory auth,) = _buildCancelInitializeGuardianRecoveryAuth({
            pendingAddress: GUARDIAN_RECOVERY_ADDRESS,
            pendingTimelock: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 13_002,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: cancel deferred recovery initialization as `GUARDIAN`, expecting `InsufficientAdminAuthorization` revert.
        vm.expectRevert(IOrganizationAdmin.InsufficientAdminAuthorization.selector);
        vm.prank(GUARDIAN);
        harness.cancelInitializeGuardianRecovery(auth);

        // Verify: pending init remains unchanged.
        assertEq(
            harness.getGuardianRecoveryState().pendingInit.pendingTimestamp,
            block.timestamp + 1,
            "pending init should remain unchanged"
        );
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.cancelInitializeGuardianRecovery` successful nonce replay
    /// reverts with `NonceAlreadyUsed`.
    function test_OGRB_CIGR_3_replaySameNonce_revertsNonceAlreadyUsed() public {
        // Setup: start from clean recovery state, seed pending deferred-init tuple, and set admin/member threshold.
        recoveryStateHarness.resetGuardianRecoveryStorage();
        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, block.timestamp + 1
        );
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        (AdminAuthParams memory auth, bytes memory operationData) = _buildCancelInitializeGuardianRecoveryAuth({
            pendingAddress: GUARDIAN_RECOVERY_ADDRESS,
            pendingTimelock: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 13_003,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        uint256 nonce = _computeRecoveryNonce(OperationType.CancelInitializeGuardianRecovery, operationData, 13_003);

        // Call: cancel deferred recovery initialization as `GUARDIAN`.
        vm.prank(GUARDIAN);
        harness.cancelInitializeGuardianRecovery(auth);

        // Verify: nonce is consumed on successful cancel-initialize.
        assertTrue(harness.getUsedNonce(nonce), "nonce should be consumed on successful cancel-initialize");

        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, block.timestamp + 1
        );
        vm.expectRevert(abi.encodeWithSelector(IOrganizationSignatures.NonceAlreadyUsed.selector, nonce));
        vm.prank(GUARDIAN);
        harness.cancelInitializeGuardianRecovery(auth);
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.cancelInitializeGuardianRecovery` cancel approval path binds
    /// pending tuple and delegates to library cancellation.
    function test_OGRB_CIGR_4__OGRB_CIGR_5__OGRB_CIGR_6__OGRB_CIGR_7_cancelApprovalPathBindsPendingTupleAndDelegates()
        public
    {
        // Setup: start from clean recovery state, seed pending deferred-init tuple, and set admin/member threshold.
        recoveryStateHarness.resetGuardianRecoveryStorage();
        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, block.timestamp + 1
        );
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        (AdminAuthParams memory auth, bytes memory pendingTupleData) = _buildCancelInitializeGuardianRecoveryAuth({
            pendingAddress: GUARDIAN_RECOVERY_ADDRESS,
            pendingTimelock: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 13_004,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        bytes memory staleData = abi.encode(GUARDIAN_RECOVERY_ADDRESS_B, GUARDIAN_RECOVERY_TIMELOCK);
        uint256 cancelNonce =
            _computeRecoveryNonce(OperationType.CancelInitializeGuardianRecovery, pendingTupleData, 13_004);
        uint256 finalizeNonce =
            _computeRecoveryNonce(OperationType.FinalizeInitializeGuardianRecovery, pendingTupleData, 13_004);
        uint256 staleNonce = _computeRecoveryNonce(OperationType.CancelInitializeGuardianRecovery, staleData, 13_004);

        // Call: cancel deferred recovery initialization as `GUARDIAN`.
        vm.prank(GUARDIAN);
        harness.cancelInitializeGuardianRecovery(auth);

        // Verify: cancel nonce is consumed; finalize nonce remains unused.
        assertTrue(harness.getUsedNonce(cancelNonce), "cancel nonce should be consumed");
        assertFalse(harness.getUsedNonce(finalizeNonce), "finalize nonce should remain unused");
        assertFalse(harness.getUsedNonce(staleNonce), "stale tuple nonce should remain unused");
        assertEq(
            harness.getGuardianRecoveryState().pendingInit.pendingRecoveryAddress,
            address(0),
            "pending recovery address should clear"
        );
        assertEq(
            harness.getGuardianRecoveryState().pendingInit.pendingTimelockDurationSeconds,
            0,
            "pending timelock should clear"
        );
        assertEq(harness.getGuardianRecoveryState().pendingInit.pendingTimestamp, 0, "pending timestamp should clear");
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.cancelInitializeGuardianRecovery` cancel requires dedicated
    /// op-type and signatures are bound to current pending tuple.
    function test_OGRB_CIGR_8__OGRB_CIGR_10__OGRB_CIGR_11_cancelAuthBoundToCurrentPendingTupleAndOpType() public {
        // Setup: start from clean recovery state, seed pending deferred-init tuple, and set admin/member threshold.
        recoveryStateHarness.resetGuardianRecoveryStorage();
        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, block.timestamp + 1
        );
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        (AdminAuthParams memory staleCancelAuth, bytes memory staleData) = _buildCancelInitializeGuardianRecoveryAuth({
            pendingAddress: GUARDIAN_RECOVERY_ADDRESS,
            pendingTimelock: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 13_008,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        recoveryStateHarness.setGuardianRecoveryPendingInit(GUARDIAN_RECOVERY_ADDRESS_B, 3 days, block.timestamp + 2);

        // Call: cancel deferred recovery initialization as `GUARDIAN`, expecting authorization/state-validation revert.
        vm.expectRevert();
        vm.prank(GUARDIAN);
        harness.cancelInitializeGuardianRecovery(staleCancelAuth);

        bytes memory currentData = abi.encode(GUARDIAN_RECOVERY_ADDRESS_B, 3 days);
        AdminAuthParams memory wrongOpTypeAuth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.FinalizeInitializeGuardianRecovery,
            operationData: currentData,
            isApproval: true,
            salt: 13_008,
            expirationTimestamp: block.timestamp + 1 days,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.expectRevert();
        vm.prank(GUARDIAN);
        harness.cancelInitializeGuardianRecovery(wrongOpTypeAuth);

        // Verify: stale tuple nonce remains unused; current tuple nonce remains unused.
        uint256 staleNonce = _computeRecoveryNonce(OperationType.CancelInitializeGuardianRecovery, staleData, 13_008);
        uint256 currentNonce =
            _computeRecoveryNonce(OperationType.CancelInitializeGuardianRecovery, currentData, 13_008);
        assertFalse(harness.getUsedNonce(staleNonce), "stale tuple nonce should remain unused");
        assertFalse(harness.getUsedNonce(currentNonce), "current tuple nonce should remain unused");
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.cancelInitializeGuardianRecovery` downstream no-pending revert
    /// rolls back nonce usage.
    function test_OGRB_CIGR_9_downstreamNoPendingRevert_rollsBackNonce() public {
        // Setup: start from clean recovery state, set admin/member threshold, and prepare signed admin auth.
        recoveryStateHarness.resetGuardianRecoveryStorage();
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        (AdminAuthParams memory auth, bytes memory operationData) = _buildCancelInitializeGuardianRecoveryAuth({
            pendingAddress: address(0),
            pendingTimelock: 0,
            salt: 13_009,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        uint256 nonce = _computeRecoveryNonce(OperationType.CancelInitializeGuardianRecovery, operationData, 13_009);

        // Call: cancel deferred recovery initialization as `GUARDIAN`, expecting `NoGuardianRecoveryInitializationPending` revert.
        vm.expectRevert(IOrganizationGuardianRecovery.NoGuardianRecoveryInitializationPending.selector);
        vm.prank(GUARDIAN);
        harness.cancelInitializeGuardianRecovery(auth);

        // Verify: nonce should rollback on downstream no-pending revert.
        assertFalse(harness.getUsedNonce(nonce), "nonce should rollback on downstream no-pending revert");
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.cancelInitializeGuardianRecovery` expired auth reverts without
    /// burning nonce and fresh signatures can reuse same nonce.
    function test_OGRB_CIGR_12_expiredAuth_revertsWithoutBurningNonce_andFreshSignaturesSucceed() public {
        // Setup: start from clean recovery state, seed pending deferred-init tuple, and set admin/member threshold.
        recoveryStateHarness.resetGuardianRecoveryStorage();
        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, block.timestamp + 1
        );
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        (AdminAuthParams memory expiredAuth, bytes memory operationData) = _buildCancelInitializeGuardianRecoveryAuth({
            pendingAddress: GUARDIAN_RECOVERY_ADDRESS,
            pendingTimelock: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 13_012,
            expiration: block.timestamp - 1,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        uint256 nonce = _computeRecoveryNonce(OperationType.CancelInitializeGuardianRecovery, operationData, 13_012);

        // Call: cancel deferred recovery initialization as `GUARDIAN`, expecting authorization/state-validation revert.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdmin.AdminOperationExpired.selector, block.timestamp - 1, block.timestamp
            )
        );
        vm.prank(GUARDIAN);
        harness.cancelInitializeGuardianRecovery(expiredAuth);

        // Verify: expired auth should not burn nonce; fresh signatures with same tuple+salt should succeed.
        assertFalse(harness.getUsedNonce(nonce), "expired auth should not burn nonce");

        (AdminAuthParams memory freshAuth,) = _buildCancelInitializeGuardianRecoveryAuth({
            pendingAddress: GUARDIAN_RECOVERY_ADDRESS,
            pendingTimelock: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 13_012,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        harness.cancelInitializeGuardianRecovery(freshAuth);
        assertTrue(harness.getUsedNonce(nonce), "fresh signatures with same tuple+salt should succeed");
    }
}
