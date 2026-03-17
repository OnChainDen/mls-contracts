// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {
    OrganizationGuardianRecoveryBaseSuiteBase
} from "test/organization/base/OrganizationGuardianRecoveryBase/OrganizationGuardianRecoveryBaseSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";

/**
 * @dev Integration tests for cross-operation deferred-init auth binding and unconfigured access behavior.
 */
contract OrganizationGuardianRecoveryBaseIntegrationTest is OrganizationGuardianRecoveryBaseSuiteBase {
    /// @dev Verifies that stale finalize signatures become invalid after cancel + re-init with new params.
    function test_OGR_INT_11_staleFinalizeSignaturesInvalidAfterCancelAndReInit() public {
        // Setup: start from clean recovery state, set admin/member threshold, and prepare signed admin auth.
        recoveryStateHarness.resetGuardianRecoveryStorage();
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        (AdminAuthParams memory initAuthA,) = _buildInitiateInitializeGuardianRecoveryAuth({
            recoveryAddress: GUARDIAN_RECOVERY_ADDRESS,
            timelockDurationSeconds: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 31_001,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        harness.initiateInitializeGuardianRecovery(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, initAuthA);

        (AdminAuthParams memory staleFinalizeAuth,) = _buildFinalizeInitializeGuardianRecoveryAuth({
            pendingAddress: GUARDIAN_RECOVERY_ADDRESS,
            pendingTimelock: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 31_002,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        (AdminAuthParams memory cancelAuthA,) = _buildCancelInitializeGuardianRecoveryAuth({
            pendingAddress: GUARDIAN_RECOVERY_ADDRESS,
            pendingTimelock: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 31_003,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: cancel deferred recovery initialization, initiate deferred recovery initialization, then finalize
        // deferred recovery initialization as `GUARDIAN`, expecting authorization/state-validation revert.
        vm.prank(GUARDIAN);
        harness.cancelInitializeGuardianRecovery(cancelAuthA);

        (AdminAuthParams memory initAuthB,) = _buildInitiateInitializeGuardianRecoveryAuth({
            recoveryAddress: GUARDIAN_RECOVERY_ADDRESS_B,
            timelockDurationSeconds: 4 days,
            salt: 31_004,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        harness.initiateInitializeGuardianRecovery(GUARDIAN_RECOVERY_ADDRESS_B, 4 days, initAuthB);

        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.finalizeInitializeGuardianRecovery(staleFinalizeAuth);

        // Verify: pending tuple remains the newly initialized tuple.
        assertEq(
            harness.getGuardianRecoveryState().pendingInit.pendingRecoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS_B,
            "pending tuple should remain the newly initialized tuple"
        );
    }

    /// @dev Verifies that stale cancel signatures become invalid once pending params change.
    function test_OGR_INT_12_staleCancelSignaturesInvalidAfterPendingParamsChange() public {
        // Setup: start from clean recovery state, set admin/member threshold, and prepare signed admin auth.
        recoveryStateHarness.resetGuardianRecoveryStorage();
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        (AdminAuthParams memory initAuthA,) = _buildInitiateInitializeGuardianRecoveryAuth({
            recoveryAddress: GUARDIAN_RECOVERY_ADDRESS,
            timelockDurationSeconds: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 32_001,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        harness.initiateInitializeGuardianRecovery(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK, initAuthA);

        (AdminAuthParams memory staleCancelAuth,) = _buildCancelInitializeGuardianRecoveryAuth({
            pendingAddress: GUARDIAN_RECOVERY_ADDRESS,
            pendingTimelock: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 32_002,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        (AdminAuthParams memory cancelAuthA2,) = _buildCancelInitializeGuardianRecoveryAuth({
            pendingAddress: GUARDIAN_RECOVERY_ADDRESS,
            pendingTimelock: GUARDIAN_RECOVERY_TIMELOCK,
            salt: 32_003,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        harness.cancelInitializeGuardianRecovery(cancelAuthA2);

        (AdminAuthParams memory initAuthB,) = _buildInitiateInitializeGuardianRecoveryAuth({
            recoveryAddress: GUARDIAN_RECOVERY_ADDRESS_B,
            timelockDurationSeconds: 4 days,
            salt: 32_004,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        harness.initiateInitializeGuardianRecovery(GUARDIAN_RECOVERY_ADDRESS_B, 4 days, initAuthB);

        // Call: cancel deferred recovery initialization as `GUARDIAN`, expecting `SignerIsNotAdmin` revert.
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.cancelInitializeGuardianRecovery(staleCancelAuth);

        // Verify: pending tuple remains current tuple when stale cancel auth is used.
        assertEq(
            harness.getGuardianRecoveryState().pendingInit.pendingRecoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS_B,
            "pending tuple should remain current tuple when stale cancel auth is used"
        );
    }

    /// @dev Verifies that unconfigured recovery address causes base recovery entry points to revert via
    /// onlyGuardianRecoveryAddress.
    function test_OGR_INT_13_unconfiguredRecoveryAddress_baseRecoveryEntryPointsAlwaysRevertAndStateUnchanged() public {
        // Setup: start from clean recovery state.
        recoveryStateHarness.resetGuardianRecoveryStorage();

        // Call: initiate recovery guardian update, finalize recovery guardian update, then cancel recovery guardian
        // update as `GUARDIAN_RECOVERY_ADDRESS`, expecting revert from the recovery-address gate.
        _expectOnlyGuardianRecoveryAddressRevert(GUARDIAN_RECOVERY_ADDRESS, address(0));
        vm.prank(GUARDIAN_RECOVERY_ADDRESS);
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN_A);

        _expectOnlyGuardianRecoveryAddressRevert(GUARDIAN_RECOVERY_ADDRESS, address(0));
        vm.prank(GUARDIAN_RECOVERY_ADDRESS);
        harness.finalizeRecoveryGuardianUpdate();

        _expectOnlyGuardianRecoveryAddressRevert(GUARDIAN_RECOVERY_ADDRESS, address(0));
        vm.prank(GUARDIAN_RECOVERY_ADDRESS);
        harness.cancelRecoveryGuardianUpdate();

        // Verify: recovery address remains unset.
        assertEq(harness.getGuardianRecoveryState().recoveryAddress, address(0), "recovery address should remain unset");
        assertEq(
            harness.getGuardianRecoveryState().pendingGuardian,
            address(0),
            "pending guardian should remain unset in unconfigured mode"
        );
        assertEq(
            harness.getGuardianRecoveryState().pendingGuardianTimestamp, 0, "pending timestamp should remain unset"
        );
    }
}
