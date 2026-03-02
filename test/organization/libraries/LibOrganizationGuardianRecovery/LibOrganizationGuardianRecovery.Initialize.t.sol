// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {TimelockUtils} from "libraries/TimelockUtils.sol";
import {
    LibOrganizationGuardianRecoverySuiteBase
} from "test/organization/libraries/LibOrganizationGuardianRecovery/LibOrganizationGuardianRecoverySuiteBase.sol";
import {GuardianRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Unit tests for `LibOrganizationGuardianRecovery.initializeGuardianRecovery`.
 */
contract LibOrganizationGuardianRecoveryInitializeTest is LibOrganizationGuardianRecoverySuiteBase {
    /// @dev Verifies `LibOrganizationGuardianRecovery.initializeGuardianRecovery` valid config sets recovery address
    /// and timelock, and values are readable.
    function test_LOGR_IGR_1__LOGR_IGR_2__LOGR_IGR_8_validConfig_setsAndIsReadable() public {
        // Setup: reset library recovery state.
        _resetRecoveryState();

        // Call: invoke `LibOrganizationGuardianRecovery.initializeGuardianRecovery`.
        harness.initializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);
        GuardianRecoveryState memory state = harness.getGuardianRecoveryStateViaStorage();

        // Verify: confirm recovery configuration fields.
        assertEq(state.recoveryAddress, GUARDIAN_RECOVERY_ADDRESS, "recovery address should be configured");
        assertEq(state.timelockDurationSeconds, GUARDIAN_RECOVERY_TIMELOCK, "timelock should be configured");
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.initializeGuardianRecovery` zero recovery address reverts with
    /// `InvalidGuardianRecoveryAddress`.
    function test_LOGR_IGR_3_zeroAddress_revertsInvalidGuardianRecoveryAddress() public {
        // Setup: reset library recovery state.
        _resetRecoveryState();

        // Call: invoke `LibOrganizationGuardianRecovery.initializeGuardianRecovery` and assert the expected revert.
        vm.expectRevert(IOrganizationGuardianRecovery.InvalidGuardianRecoveryAddress.selector);
        harness.initializeGuardianRecoveryViaLibrary(address(0), GUARDIAN_RECOVERY_TIMELOCK);

        // Verify: confirm recovery configuration fields.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().recoveryAddress,
            address(0),
            "recovery address should remain unset"
        );
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.initializeGuardianRecovery` below-min and above-max timelock
    /// values revert `InvalidTimelockDuration`.
    function test_LOGR_IGR_4__LOGR_IGR_5_outOfRangeTimelock_revertsInvalidTimelockDuration() public {
        // Setup: reset library recovery state.
        _resetRecoveryState();

        // Call: invoke `LibOrganizationGuardianRecovery.initializeGuardianRecovery` and assert the expected revert.
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                1 days,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        harness.initializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, 1 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                31 days,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        harness.initializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, 31 days);

        // Verify: confirm recovery configuration fields.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().timelockDurationSeconds,
            0,
            "timelock should remain unset on revert"
        );
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.initializeGuardianRecovery` any preconfigured recovery field
    /// causes `GuardianRecoveryAlreadyConfigured`.
    function test_LOGR_IGR_6__LOGR_IGR_7_eitherPreconfiguredField_revertsGuardianRecoveryAlreadyConfigured() public {
        // Setup: reset library recovery state.
        _resetRecoveryState();
        recoveryStateHarness.setGuardianRecoveryConfig(GUARDIAN_RECOVERY_ADDRESS_B, 0);

        // Call: invoke `LibOrganizationGuardianRecovery.initializeGuardianRecovery` and assert the expected revert.
        vm.expectRevert(IOrganizationGuardianRecovery.GuardianRecoveryAlreadyConfigured.selector);
        harness.initializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);

        recoveryStateHarness.setGuardianRecoveryConfig(address(0), 4 days);
        vm.expectRevert(IOrganizationGuardianRecovery.GuardianRecoveryAlreadyConfigured.selector);
        harness.initializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);

        // Verify: confirm recovery configuration fields.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().recoveryAddress,
            address(0),
            "second scenario should preserve zero recovery address"
        );
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().timelockDurationSeconds,
            4 days,
            "second scenario should preserve preconfigured timelock"
        );
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.initializeGuardianRecovery` initialize only mutates config fields
    /// and does not change pending/update init state.
    function test_LOGR_IGR_9_initializeOnlyMutatesConfigFields_pendingStateUnchanged() public {
        // Setup: reset library recovery state; seed a pending deferred-init timelock tuple; seed a pending
        // recovery-guardian update.
        _resetRecoveryState();
        recoveryStateHarness.setGuardianRecoveryPendingUpdate(NEW_GUARDIAN_A, block.timestamp + 5 days, true);
        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS_B, 5 days, block.timestamp + 7 days
        );

        // Call: invoke `LibOrganizationGuardianRecovery.initializeGuardianRecovery`.
        harness.initializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);

        // Verify: confirm the pending deferred-init state remains unchanged.
        GuardianRecoveryState memory state = harness.getGuardianRecoveryStateViaStorage();
        assertEq(state.recoveryAddress, GUARDIAN_RECOVERY_ADDRESS, "config recovery address should update");
        assertEq(state.timelockDurationSeconds, GUARDIAN_RECOVERY_TIMELOCK, "config timelock should update");
        assertEq(state.pendingGuardian, NEW_GUARDIAN_A, "pending guardian should remain unchanged");
        assertEq(state.pendingGuardianTimestamp, block.timestamp + 5 days, "pending timestamp should remain unchanged");
        assertTrue(state.isUpdateReadyForAcceptance, "ready flag should remain unchanged");
        assertEq(
            state.pendingInit.pendingRecoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS_B,
            "pending init recovery address should remain unchanged"
        );
        assertEq(
            state.pendingInit.pendingTimelockDurationSeconds, 5 days, "pending init timelock should remain unchanged"
        );
        assertEq(
            state.pendingInit.pendingTimestamp,
            block.timestamp + 7 days,
            "pending init timestamp should remain unchanged"
        );
    }
}
