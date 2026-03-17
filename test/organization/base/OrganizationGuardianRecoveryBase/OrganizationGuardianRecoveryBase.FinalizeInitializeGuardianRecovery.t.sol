// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {IOrganizationAdminOperationTimelock} from "interfaces/organization/IOrganizationAdminOperationTimelock.sol";
import {IOrganizationSignatures} from "interfaces/organization/IOrganizationSignatures.sol";
import {
    OrganizationGuardianRecoveryBaseHarness
} from "test/organization/base/OrganizationGuardianRecoveryBase/OrganizationGuardianRecoveryBaseHarness.sol";
import {
    OrganizationGuardianRecoveryBaseSuiteBase
} from "test/organization/base/OrganizationGuardianRecoveryBase/OrganizationGuardianRecoveryBaseSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Unit tests for `OrganizationGuardianRecoveryBase.finalizeInitializeGuardianRecovery`.
 */
contract OrganizationGuardianRecoveryBaseFinalizeInitializeGuardianRecoveryTest is
    OrganizationGuardianRecoveryBaseSuiteBase
{
    /// @dev Verifies `OrganizationGuardianRecoveryBase.finalizeInitializeGuardianRecovery` reverts when called by a
    /// non-guardian.
    function test_nonGuardianCaller_revertsOnlyGuardian() public {
        // Setup: start from clean recovery state, seed pending deferred-init tuple, and set admin/member threshold.
        recoveryStateHarness.resetGuardianRecoveryStorage();
        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, block.timestamp
        );
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        (AdminAuthParams memory auth,) = _buildFinalizeInitializeGuardianRecoveryAuth({
            pendingAddress: GUARDIAN_RECOVERY_ADDRESS,
            pendingTimelock: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 12_001,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: finalize deferred recovery initialization as `NON_GUARDIAN`, expecting revert from the guardian-only
        // gate.
        _expectOnlyGuardianRevert(NON_GUARDIAN);
        vm.prank(NON_GUARDIAN);
        harness.finalizeInitializeGuardianRecovery(auth);

        // Verify: recovery address remains unset after unauthorized call.
        assertEq(
            harness.getGuardianRecoveryState().recoveryAddress,
            address(0),
            "recovery address should remain unset after unauthorized call"
        );
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.finalizeInitializeGuardianRecovery` insufficient admin
    /// signatures revert.
    function test_insufficientAdminSignatures_reverts() public {
        // Setup: start from clean recovery state, seed pending deferred-init tuple, and set admin/member threshold.
        recoveryStateHarness.resetGuardianRecoveryStorage();
        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, block.timestamp
        );
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});

        (AdminAuthParams memory auth,) = _buildFinalizeInitializeGuardianRecoveryAuth({
            pendingAddress: GUARDIAN_RECOVERY_ADDRESS,
            pendingTimelock: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 12_002,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: finalize deferred recovery initialization as `GUARDIAN`, expecting `InsufficientAdminAuthorization`
        // revert.
        vm.expectRevert(IOrganizationAdmin.InsufficientAdminAuthorization.selector);
        vm.prank(GUARDIAN);
        harness.finalizeInitializeGuardianRecovery(auth);

        // Verify: recovery config remains unset.
        assertEq(harness.getGuardianRecoveryState().recoveryAddress, address(0), "recovery config should remain unset");
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.finalizeInitializeGuardianRecovery` successful nonce replay
    /// reverts with `NonceAlreadyUsed`.
    function test_replaySameNonce_revertsNonceAlreadyUsed() public {
        // Setup: start from clean recovery state, seed pending deferred-init tuple, and set admin/member threshold.
        recoveryStateHarness.resetGuardianRecoveryStorage();
        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, block.timestamp
        );
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        (AdminAuthParams memory auth, bytes memory operationData) = _buildFinalizeInitializeGuardianRecoveryAuth({
            pendingAddress: GUARDIAN_RECOVERY_ADDRESS,
            pendingTimelock: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 12_003,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        uint256 nonce = _computeRecoveryNonce(OperationType.FinalizeInitializeGuardianRecovery, operationData, 12_003);

        // Call: finalize deferred recovery initialization as `GUARDIAN`.
        vm.prank(GUARDIAN);
        harness.finalizeInitializeGuardianRecovery(auth);

        // Verify: nonce is consumed on successful finalization.
        assertTrue(harness.getUsedNonce(nonce), "nonce should be consumed on successful finalization");
        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, block.timestamp
        );
        vm.expectRevert(abi.encodeWithSelector(IOrganizationSignatures.NonceAlreadyUsed.selector, nonce));
        vm.prank(GUARDIAN);
        harness.finalizeInitializeGuardianRecovery(auth);
    }

    /// @dev Verifies deferred guardian-recovery finalization commits the staged tuple after the admin timelock and
    /// preserves helper-enforced storage integrity.
    function test_finalizeApprovalPathBindsPendingTupleAndDelegates()
        public
    {
        // Setup: start from clean recovery state, seed pending deferred-init tuple, and set admin/member threshold.
        recoveryStateHarness.resetGuardianRecoveryStorage();
        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, block.timestamp
        );
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        (AdminAuthParams memory auth, bytes memory pendingTupleData) = _buildFinalizeInitializeGuardianRecoveryAuth({
            pendingAddress: GUARDIAN_RECOVERY_ADDRESS,
            pendingTimelock: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 12_004,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        bytes memory staleData = abi.encode(GUARDIAN_RECOVERY_ADDRESS_B, GUARDIAN_RECOVERY_TIMELOCK);

        uint256 finalizeNonce =
            _computeRecoveryNonce(OperationType.FinalizeInitializeGuardianRecovery, pendingTupleData, 12_004);
        uint256 initiateNonce =
            _computeRecoveryNonce(OperationType.InitiateInitializeGuardianRecovery, pendingTupleData, 12_004);
        uint256 staleNonce = _computeRecoveryNonce(OperationType.FinalizeInitializeGuardianRecovery, staleData, 12_004);

        // Call: finalize deferred recovery initialization as `GUARDIAN`.
        vm.prank(GUARDIAN);
        harness.finalizeInitializeGuardianRecovery(auth);

        // Verify: finalize nonce is consumed; initiate nonce remains unused.
        assertTrue(harness.getUsedNonce(finalizeNonce), "finalize nonce should be consumed");
        assertFalse(harness.getUsedNonce(initiateNonce), "initiate nonce should remain unused");
        assertFalse(harness.getUsedNonce(staleNonce), "stale tuple nonce should remain unused");

        assertEq(
            harness.getGuardianRecoveryState().recoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS,
            "finalize should set recovery address from pending tuple"
        );
        assertEq(
            harness.getGuardianRecoveryState().timelockDurationSeconds,
            GUARDIAN_RECOVERY_TIMELOCK,
            "finalize should set timelock from pending tuple"
        );
        assertEq(
            harness.getGuardianRecoveryState().pendingInit.pendingTimestamp,
            0,
            "pending init should clear after successful finalization"
        );
    }

    /// @dev Verifies deferred guardian-recovery finalize and cancel signatures are bound to the current pending tuple
    /// values, so stale signatures fail after any pending-value mutation.
    function test_stalePendingTupleSignatures_revertAfterPendingValuesChange()
        public
    {
        // Setup: start from clean recovery state, seed pending deferred-init tuple, and set admin/member threshold.
        recoveryStateHarness.resetGuardianRecoveryStorage();
        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, block.timestamp
        );
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        (AdminAuthParams memory staleAuth, bytes memory staleData) = _buildFinalizeInitializeGuardianRecoveryAuth({
            pendingAddress: GUARDIAN_RECOVERY_ADDRESS,
            pendingTimelock: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 12_008,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        recoveryStateHarness.setGuardianRecoveryPendingInit(GUARDIAN_RECOVERY_ADDRESS_B, 3 days, block.timestamp);

        // Call: finalize deferred recovery initialization as `GUARDIAN`, expecting `SignerIsNotAdmin` revert.
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.finalizeInitializeGuardianRecovery(staleAuth);

        // Verify: stale tuple nonce remains unused; current tuple nonce remains unused.
        bytes memory currentData = abi.encode(GUARDIAN_RECOVERY_ADDRESS_B, 3 days);
        uint256 staleNonce = _computeRecoveryNonce(OperationType.FinalizeInitializeGuardianRecovery, staleData, 12_008);
        uint256 currentNonce =
            _computeRecoveryNonce(OperationType.FinalizeInitializeGuardianRecovery, currentData, 12_008);
        assertFalse(harness.getUsedNonce(staleNonce), "stale tuple nonce should remain unused");
        assertFalse(harness.getUsedNonce(currentNonce), "current tuple nonce should remain unused");

        assertEq(
            harness.getGuardianRecoveryState().recoveryAddress,
            address(0),
            "recovery address should remain unset after stale-signature revert"
        );
        assertEq(
            harness.getGuardianRecoveryState().timelockDurationSeconds,
            0,
            "timelock duration should remain unset after stale-signature revert"
        );
        assertEq(
            harness.getGuardianRecoveryState().pendingInit.pendingRecoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS_B,
            "current pending address should be preserved after stale-signature revert"
        );
        assertEq(
            harness.getGuardianRecoveryState().pendingInit.pendingTimelockDurationSeconds,
            3 days,
            "current pending timelock should be preserved after stale-signature revert"
        );
        assertNotEq(
            harness.getGuardianRecoveryState().pendingInit.pendingTimestamp,
            0,
            "current pending timestamp should be preserved after stale-signature revert"
        );
    }

    /// @dev Verifies deferred guardian-recovery finalization reverts before the admin timelock expires and succeeds
    /// at the exact boundary without requiring new signatures.
    function test_downstreamRevert_rollsBackNonceAndAllowsRetry() public {
        // Setup: start from clean recovery state, seed pending deferred-init tuple, and set admin/member threshold.
        recoveryStateHarness.resetGuardianRecoveryStorage();
        uint256 canFinalizeAt = block.timestamp + 1 days;
        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, canFinalizeAt
        );
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        (AdminAuthParams memory auth, bytes memory operationData) = _buildFinalizeInitializeGuardianRecoveryAuth({
            pendingAddress: GUARDIAN_RECOVERY_ADDRESS,
            pendingTimelock: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 12_009,
            expiration: block.timestamp + 2 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        uint256 nonce = _computeRecoveryNonce(OperationType.FinalizeInitializeGuardianRecovery, operationData, 12_009);

        // Call: finalize deferred recovery initialization as `GUARDIAN`, expecting authorization/state-validation
        // revert.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdminOperationTimelock.TimelockNotExpired.selector, canFinalizeAt, block.timestamp
            )
        );
        vm.prank(GUARDIAN);
        harness.finalizeInitializeGuardianRecovery(auth);

        // Verify: nonce should rollback on downstream timelock revert; same signed request should succeed once timelock
        // expires.
        assertFalse(harness.getUsedNonce(nonce), "nonce should rollback on downstream timelock revert");

        vm.warp(canFinalizeAt);
        vm.prank(GUARDIAN);
        harness.finalizeInitializeGuardianRecovery(auth);
        assertTrue(harness.getUsedNonce(nonce), "same signed request should succeed once timelock expires");
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.finalizeInitializeGuardianRecovery` expired auth reverts and
    /// nonce is not burned.
    function test_expiredAuth_revertsWithoutBurningNonce_andFreshSignaturesSucceed() public {
        // Setup: start from clean recovery state, seed pending deferred-init tuple, and set admin/member threshold.
        recoveryStateHarness.resetGuardianRecoveryStorage();
        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, block.timestamp
        );
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        (AdminAuthParams memory expiredAuth, bytes memory operationData) = _buildFinalizeInitializeGuardianRecoveryAuth({
            pendingAddress: GUARDIAN_RECOVERY_ADDRESS,
            pendingTimelock: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 12_012,
            expiration: block.timestamp - 1,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        uint256 nonce = _computeRecoveryNonce(OperationType.FinalizeInitializeGuardianRecovery, operationData, 12_012);

        // Call: finalize deferred recovery initialization as `GUARDIAN`, expecting authorization/state-validation
        // revert.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdmin.AdminOperationExpired.selector, block.timestamp - 1, block.timestamp
            )
        );
        vm.prank(GUARDIAN);
        harness.finalizeInitializeGuardianRecovery(expiredAuth);

        // Verify: expired auth should not burn nonce; fresh signatures for same tuple+salt should succeed.
        assertFalse(harness.getUsedNonce(nonce), "expired auth should not burn nonce");

        (AdminAuthParams memory freshAuth,) = _buildFinalizeInitializeGuardianRecoveryAuth({
            pendingAddress: GUARDIAN_RECOVERY_ADDRESS,
            pendingTimelock: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 12_012,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        harness.finalizeInitializeGuardianRecovery(freshAuth);
        assertTrue(harness.getUsedNonce(nonce), "fresh signatures for same tuple+salt should succeed");
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.finalizeInitializeGuardianRecovery` rejection signatures cannot
    /// execute finalization.
    function test_rejectionSignatures_cannotExecuteFinalization() public {
        // Setup: start from clean recovery state, seed pending deferred-init tuple, and set admin/member threshold.
        recoveryStateHarness.resetGuardianRecoveryStorage();
        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, block.timestamp
        );
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        (AdminAuthParams memory rejectionAuth,) = _buildFinalizeInitializeGuardianRecoveryAuth({
            pendingAddress: GUARDIAN_RECOVERY_ADDRESS,
            pendingTimelock: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 12_013,
            expiration: block.timestamp + 1 days,
            isApproval: false,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: finalize deferred recovery initialization as `GUARDIAN`, expecting `SignerIsNotAdmin` revert.
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.finalizeInitializeGuardianRecovery(rejectionAuth);

        // Verify: rejection signatures does not finalize initialization.
        assertEq(
            harness.getGuardianRecoveryState().recoveryAddress,
            address(0),
            "rejection signatures must not finalize initialization"
        );
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.finalizeInitializeGuardianRecovery` signatures for a different
    /// operation type cannot authorize finalization.
    function test_signaturesForDifferentOperationType_cannotAuthorizeFinalization() public {
        // Setup: start from clean recovery state, seed pending deferred-init tuple, and set admin/member threshold.
        recoveryStateHarness.resetGuardianRecoveryStorage();
        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, block.timestamp
        );
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        bytes memory operationData = abi.encode(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);
        AdminAuthParams memory wrongAuth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.CancelInitializeGuardianRecovery,
            operationData: operationData,
            isApproval: true,
            salt: 12_014,
            expirationTimestamp: block.timestamp + 1 days,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: finalize deferred recovery initialization as `GUARDIAN`, expecting `SignerIsNotAdmin` revert.
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.finalizeInitializeGuardianRecovery(wrongAuth);

        // Verify: finalize nonce remains unused.
        uint256 finalizeNonce =
            _computeRecoveryNonce(OperationType.FinalizeInitializeGuardianRecovery, operationData, 12_014);
        assertFalse(harness.getUsedNonce(finalizeNonce), "finalize nonce should remain unused");
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.finalizeInitializeGuardianRecovery` can finalize the same
    /// pending tuple on fresh organization instances with different salts.
    function test_finalizeInitializeGuardianRecovery_samePendingTupleDifferentSalts_succeedsPerFreshOrg()
        public
    {
        // Setup: deploy two fresh harnesses with the same pending deferred-init tuple and build finalize auth with
        // different salts for each organization address.
        OrganizationGuardianRecoveryBaseHarness secondHarness = new OrganizationGuardianRecoveryBaseHarness();
        secondHarness.setGuardian(GUARDIAN);
        secondHarness.setAdminOperationTimelockDurationSeconds(ADMIN_OPERATION_TIMELOCK);
        secondHarness.setMemberStatus(admin1, true);
        secondHarness.setAdminStatus(admin1, true);
        secondHarness.setAdminCount(1);
        secondHarness.setVotingThreshold(1);
        secondHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, block.timestamp
        );

        recoveryStateHarness.resetGuardianRecoveryStorage();
        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, block.timestamp
        );
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        (AdminAuthParams memory firstAuth, bytes memory operationData) = _buildFinalizeInitializeGuardianRecoveryAuth({
            pendingAddress: GUARDIAN_RECOVERY_ADDRESS,
            pendingTimelock: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 12_015,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        bytes32 secondOperationHash = secondHarness.getAdminOperationHash({
            operationType: OperationType.FinalizeInitializeGuardianRecovery,
            operationData: operationData,
            salt: 12_016,
            expirationTimestamp: block.timestamp + 1 days,
            isApproval: true
        });
        AdminAuthParams memory secondAuth = AdminAuthParams({
            salt: 12_016,
            expirationTimestamp: block.timestamp + 1 days,
            signatures: _buildSortedEoaSignatures(secondOperationHash, buildUint256Array(ADMIN_PK_1))
        });
        uint256 firstNonce =
            _computeRecoveryNonce(OperationType.FinalizeInitializeGuardianRecovery, operationData, 12_015);
        uint256 secondNonce =
            secondHarness.computeNonce(OperationType.FinalizeInitializeGuardianRecovery, operationData, 12_016);

        // Call: finalize the identical pending tuple once per fresh organization instance, each with its own salt.
        vm.prank(GUARDIAN);
        harness.finalizeInitializeGuardianRecovery(firstAuth);

        vm.prank(GUARDIAN);
        secondHarness.finalizeInitializeGuardianRecovery(secondAuth);

        // Verify: each fresh organization consumes only its own finalize nonce while writing the same configured
        // recovery tuple.
        assertTrue(firstNonce != secondNonce, "organization address and salt should isolate finalize nonces");
        assertTrue(harness.getUsedNonce(firstNonce), "first finalize nonce should be consumed");
        assertTrue(secondHarness.getUsedNonce(secondNonce), "second finalize nonce should be consumed");
        assertEq(
            harness.getGuardianRecoveryState().recoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS,
            "first organization should finalize the configured recovery address"
        );
        assertEq(
            secondHarness.getGuardianRecoveryState().recoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS,
            "second organization should finalize the configured recovery address"
        );
        assertEq(
            harness.getGuardianRecoveryState().timelockDurationSeconds,
            GUARDIAN_RECOVERY_TIMELOCK,
            "first organization should finalize the configured timelock"
        );
        assertEq(
            secondHarness.getGuardianRecoveryState().timelockDurationSeconds,
            GUARDIAN_RECOVERY_TIMELOCK,
            "second organization should finalize the configured timelock"
        );
    }
}
