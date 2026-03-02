// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

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
        // Setup: reset guardian-recovery storage; configure admin quorum for signature validation; build signed
        // admin-auth payloads.
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

        // Call: run the multi-step flow (`OrganizationGuardianRecoveryBase.cancelInitializeGuardianRecovery`,
        // `OrganizationGuardianRecoveryBase.initiateInitializeGuardianRecovery`,
        // `OrganizationGuardianRecoveryBase.finalizeInitializeGuardianRecovery`) and assert the revert branch.
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

        vm.expectRevert();
        vm.prank(GUARDIAN);
        harness.finalizeInitializeGuardianRecovery(staleFinalizeAuth);

        // Verify: confirm pending deferred-init fields.
        assertEq(
            harness.getGuardianRecoveryState().pendingInit.pendingRecoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS_B,
            "pending tuple should remain the newly initialized tuple"
        );
    }

    /// @dev Verifies that stale cancel signatures become invalid once pending params change.
    function test_OGR_INT_12_staleCancelSignaturesInvalidAfterPendingParamsChange() public {
        // Setup: reset guardian-recovery storage; configure admin quorum for signature validation; build signed
        // admin-auth payloads.
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

        // Call: invoke `OrganizationGuardianRecoveryBase.cancelInitializeGuardianRecovery` as `GUARDIAN` and assert the
        // expected revert.
        vm.expectRevert();
        vm.prank(GUARDIAN);
        harness.cancelInitializeGuardianRecovery(staleCancelAuth);

        // Verify: confirm pending deferred-init fields.
        assertEq(
            harness.getGuardianRecoveryState().pendingInit.pendingRecoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS_B,
            "pending tuple should remain current tuple when stale cancel auth is used"
        );
    }

    /// @dev Verifies that unconfigured recovery address causes base recovery entry points to revert via
    /// onlyGuardianRecoveryAddress.
    function test_OGR_INT_13_unconfiguredRecoveryAddress_baseRecoveryEntryPointsAlwaysRevertAndStateUnchanged() public {
        // Setup: reset guardian-recovery storage.
        recoveryStateHarness.resetGuardianRecoveryStorage();

        // Call: run the multi-step flow (`OrganizationGuardianRecoveryBase.initiateRecoveryGuardianUpdate`,
        // `OrganizationGuardianRecoveryBase.finalizeRecoveryGuardianUpdate`,
        // `OrganizationGuardianRecoveryBase.cancelRecoveryGuardianUpdate`).
        _expectOnlyGuardianRecoveryAddressRevert(GUARDIAN_RECOVERY_ADDRESS, address(0));
        vm.prank(GUARDIAN_RECOVERY_ADDRESS);
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN_A);

        _expectOnlyGuardianRecoveryAddressRevert(GUARDIAN_RECOVERY_ADDRESS, address(0));
        vm.prank(GUARDIAN_RECOVERY_ADDRESS);
        harness.finalizeRecoveryGuardianUpdate();

        _expectOnlyGuardianRecoveryAddressRevert(GUARDIAN_RECOVERY_ADDRESS, address(0));
        vm.prank(GUARDIAN_RECOVERY_ADDRESS);
        harness.cancelRecoveryGuardianUpdate();

        // Verify: confirm pending recovery-update fields, recovery configuration fields.
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
