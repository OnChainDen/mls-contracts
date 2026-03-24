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
    function test_validConfig_setsAndIsReadable() public {
        // Setup: start from clean recovery state.
        harness.resetGuardianRecoveryStorageViaHarness();

        // Call: initialize guardian-recovery config.
        harness.initializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);
        GuardianRecoveryState memory state = harness.getGuardianRecoveryStateViaStorage();

        // Verify: recovery address is configured; timelock is configured.
        assertEq(state.recoveryAddress, GUARDIAN_RECOVERY_ADDRESS, "recovery address should be configured");
        assertEq(state.timelockDurationSeconds, GUARDIAN_RECOVERY_TIMELOCK, "timelock should be configured");
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.initializeGuardianRecovery` zero recovery address reverts with
    /// `InvalidGuardianRecoveryAddress`.
    function test_zeroAddress_revertsInvalidGuardianRecoveryAddress() public {
        // Setup: start from clean recovery state.
        harness.resetGuardianRecoveryStorageViaHarness();

        // Call: initialize guardian-recovery config, expecting `InvalidGuardianRecoveryAddress` revert.
        vm.expectRevert(IOrganizationGuardianRecovery.InvalidGuardianRecoveryAddress.selector);
        harness.initializeGuardianRecoveryViaLibrary(address(0), GUARDIAN_RECOVERY_TIMELOCK);

        // Verify: recovery address remains unset.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().recoveryAddress,
            address(0),
            "recovery address should remain unset"
        );
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.initializeGuardianRecovery` below-min and above-max timelock
    /// values revert `InvalidTimelockDuration`.
    function test_outOfRangeTimelock_revertsInvalidTimelockDuration() public {
        // Setup: start from clean recovery state.
        harness.resetGuardianRecoveryStorageViaHarness();

        // Call: initialize guardian-recovery config, expecting authorization/state-validation revert.
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

        // Verify: timelock remains unset on revert.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().timelockDurationSeconds,
            0,
            "timelock should remain unset on revert"
        );
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery.initializeGuardianRecovery` any preconfigured recovery field
    /// causes `GuardianRecoveryAlreadyConfigured`.
    function test_eitherPreconfiguredField_revertsGuardianRecoveryAlreadyConfigured() public {
        // Setup: start from clean recovery state.
        harness.resetGuardianRecoveryStorageViaHarness();
        recoveryStateHarness.setGuardianRecoveryConfig(GUARDIAN_RECOVERY_ADDRESS_B, 0);

        // Call: initialize guardian-recovery config, expecting `GuardianRecoveryAlreadyConfigured` revert.
        vm.expectRevert(IOrganizationGuardianRecovery.GuardianRecoveryAlreadyConfigured.selector);
        harness.initializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);

        recoveryStateHarness.setGuardianRecoveryConfig(address(0), 4 days);
        vm.expectRevert(IOrganizationGuardianRecovery.GuardianRecoveryAlreadyConfigured.selector);
        harness.initializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);

        // Verify: second scenario should preserve zero recovery address; second scenario should preserve preconfigured
        // timelock.
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
    function test_initializeOnlyMutatesConfigFields_pendingStateUnchanged() public {
        // Setup: start from clean recovery state, seed pending deferred-init tuple, and seed pending recovery-guardian
        // update.
        harness.resetGuardianRecoveryStorageViaHarness();
        recoveryStateHarness.setGuardianRecoveryPendingUpdate(NEW_GUARDIAN_A, block.timestamp + 5 days, true);
        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS_B, 5 days, block.timestamp + 7 days
        );

        // Call: initialize guardian-recovery config.
        harness.initializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);

        // Verify: config recovery address updates; config timelock updates.
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
