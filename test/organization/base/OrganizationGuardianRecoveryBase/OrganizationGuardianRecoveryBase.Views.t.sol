// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    OrganizationGuardianRecoveryBaseSuiteBase
} from "test/organization/base/OrganizationGuardianRecoveryBase/OrganizationGuardianRecoveryBaseSuiteBase.sol";
import {GuardianRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Unit tests for `OrganizationGuardianRecoveryBase.getGuardianRecoveryState`.
 */
contract OrganizationGuardianRecoveryBaseViewsTest is OrganizationGuardianRecoveryBaseSuiteBase {
    /// @dev Verifies `OrganizationGuardianRecoveryBase.getGuardianRecoveryState` getter returns full storage struct and
    /// is callable by any address.
    function test_OGRB_GGRS_1__OGRB_GGRS_2_getterReturnsFullStructAndIsPublic() public {
        // Setup: seed a pending deferred-init timelock tuple.
        _setPendingRecoveryUpdate(NEW_GUARDIAN_A, block.timestamp + 3 days, true);
        _setPendingInit(GUARDIAN_RECOVERY_ADDRESS_B, 3 days, block.timestamp + 5 days);

        // Call: invoke `OrganizationGuardianRecoveryBase.getGuardianRecoveryState` as `NON_GUARDIAN`.
        vm.prank(NON_GUARDIAN);
        GuardianRecoveryState memory state = harness.getGuardianRecoveryState();

        // Verify: confirm pending deferred-init fields, pending recovery-update fields, recovery configuration fields.
        assertEq(state.recoveryAddress, GUARDIAN_RECOVERY_ADDRESS, "recovery address should match storage");
        assertTrue(state.isUpdateReadyForAcceptance, "ready flag should match storage");
        assertEq(state.pendingGuardian, NEW_GUARDIAN_A, "pending guardian should match storage");
        assertEq(state.timelockDurationSeconds, GUARDIAN_RECOVERY_TIMELOCK, "timelock should match storage");
        assertEq(
            state.pendingGuardianTimestamp, block.timestamp + 3 days, "pending guardian timestamp should match storage"
        );
        assertEq(
            state.pendingInit.pendingRecoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS_B,
            "pending-init address should match storage"
        );
        assertEq(state.pendingInit.pendingTimelockDurationSeconds, 3 days, "pending-init timelock should match storage");
        assertEq(
            state.pendingInit.pendingTimestamp, block.timestamp + 5 days, "pending-init timestamp should match storage"
        );
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.getGuardianRecoveryState` getter returns zeroed struct when
    /// recovery has not been configured.
    function test_OGRB_GGRS_3_noRecoveryConfigured_returnsZeroedStruct() public {
        // Setup: reset guardian-recovery storage.
        recoveryStateHarness.resetGuardianRecoveryStorage();

        // Call: invoke `OrganizationGuardianRecoveryBase.getGuardianRecoveryState`.
        GuardianRecoveryState memory state = harness.getGuardianRecoveryState();

        // Verify: confirm pending deferred-init fields, pending recovery-update fields, recovery configuration fields.
        assertEq(state.recoveryAddress, address(0), "recovery address should be zero");
        assertFalse(state.isUpdateReadyForAcceptance, "ready flag should be false");
        assertEq(state.pendingGuardian, address(0), "pending guardian should be zero");
        assertEq(state.timelockDurationSeconds, 0, "timelock should be zero");
        assertEq(state.pendingGuardianTimestamp, 0, "pending guardian timestamp should be zero");
        assertEq(state.pendingInit.pendingRecoveryAddress, address(0), "pending-init address should be zero");
        assertEq(state.pendingInit.pendingTimelockDurationSeconds, 0, "pending-init timelock should be zero");
        assertEq(state.pendingInit.pendingTimestamp, 0, "pending-init timestamp should be zero");
    }

    /// @dev Verifies `OrganizationGuardianRecoveryBase.getGuardianRecoveryState` getter reflects configured,
    /// recovery-update pending, and deferred-init pending states.
    function test_OGRB_GGRS_4__OGRB_GGRS_5__OGRB_GGRS_6_getterReflectsConfiguredAndBothPendingFlows() public {
        // Setup: seed a pending deferred-init timelock tuple.
        _setPendingRecoveryUpdate(NEW_GUARDIAN_B, block.timestamp + 2 days, false);
        _setPendingInit(GUARDIAN_RECOVERY_ADDRESS_B, 4 days, block.timestamp + 7 days);

        // Call: invoke `OrganizationGuardianRecoveryBase.getGuardianRecoveryState`.
        GuardianRecoveryState memory state = harness.getGuardianRecoveryState();

        // Verify: confirm pending deferred-init fields, pending recovery-update fields, recovery configuration fields.
        assertEq(state.recoveryAddress, GUARDIAN_RECOVERY_ADDRESS, "configured recovery address should remain set");
        assertEq(
            state.timelockDurationSeconds, GUARDIAN_RECOVERY_TIMELOCK, "configured recovery timelock should remain set"
        );
        assertEq(state.pendingGuardian, NEW_GUARDIAN_B, "recovery-update pending guardian should match storage");
        assertEq(
            state.pendingGuardianTimestamp,
            block.timestamp + 2 days,
            "recovery-update pending timestamp should match storage"
        );
        assertFalse(state.isUpdateReadyForAcceptance, "recovery-update ready flag should match storage");
        assertEq(
            state.pendingInit.pendingRecoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS_B,
            "deferred-init pending address should match storage"
        );
        assertEq(
            state.pendingInit.pendingTimelockDurationSeconds,
            4 days,
            "deferred-init pending timelock should match storage"
        );
        assertEq(
            state.pendingInit.pendingTimestamp,
            block.timestamp + 7 days,
            "deferred-init pending timestamp should match storage"
        );
    }
}
