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
 * @dev Unit tests for enforcement helpers and internal wrappers in `LibOrganizationGuardianRecovery`.
 */
contract LibOrganizationGuardianRecoveryEnforcementAndInternalHelpersTest is LibOrganizationGuardianRecoverySuiteBase {
    /// @dev Verifies that enforce-only-recovery-address pass/fail behavior and revert payload fields.
    function test_enforceOnlyGuardianRecoveryAddress_behavesAsExpected() public {
        // Setup: reconfigure baseline recovery address and timelock.
        _resetAndConfigureRecovery();

        // Call: enforce recovery-address caller gate then reset guardian recovery storage via harness as
        // `GUARDIAN_RECOVERY_ADDRESS`, expecting authorization/state-validation revert.
        vm.prank(GUARDIAN_RECOVERY_ADDRESS);
        harness.enforceOnlyGuardianRecoveryAddressViaLibrary();

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.UnauthorizedGuardianRecoveryAddress.selector,
                NON_GUARDIAN,
                GUARDIAN_RECOVERY_ADDRESS
            )
        );
        vm.prank(NON_GUARDIAN);
        harness.enforceOnlyGuardianRecoveryAddressViaLibrary();

        harness.resetGuardianRecoveryStorageViaHarness();
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.UnauthorizedGuardianRecoveryAddress.selector, NON_GUARDIAN, address(0)
            )
        );
        vm.prank(NON_GUARDIAN);
        harness.enforceOnlyGuardianRecoveryAddressViaLibrary();

        // Verify: recovery address remains zero in unconfigured case.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().recoveryAddress,
            address(0),
            "recovery address should remain zero in unconfigured case"
        );
    }

    /// @dev Verifies that enforce-only-pending-guardian pass/fail behavior including cancel/accept transitions.
    function test_enforceOnlyRecoveryPendingGuardian_behavesAsExpected() public {
        // Setup: reconfigure baseline recovery address and timelock and seed pending recovery-guardian update.
        _resetAndConfigureRecovery();
        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_A);

        // Call: enforce pending-guardian caller gate, cancel recovery guardian update, then initiate recovery guardian
        // update as `NEW_GUARDIAN_A`, expecting authorization/state-validation revert.
        vm.prank(NEW_GUARDIAN_A);
        harness.enforceOnlyRecoveryPendingGuardianViaLibrary();

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.UnauthorizedRecoveryGuardianAcceptance.selector,
                NON_GUARDIAN,
                NEW_GUARDIAN_A
            )
        );
        vm.prank(NON_GUARDIAN);
        harness.enforceOnlyRecoveryPendingGuardianViaLibrary();

        harness.cancelRecoveryGuardianUpdateViaLibrary();
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.UnauthorizedRecoveryGuardianAcceptance.selector,
                NEW_GUARDIAN_A,
                address(0)
            )
        );
        vm.prank(NEW_GUARDIAN_A);
        harness.enforceOnlyRecoveryPendingGuardianViaLibrary();

        harness.initiateRecoveryGuardianUpdateViaLibrary(NEW_GUARDIAN_A);
        vm.warp(harness.getGuardianRecoveryStateViaStorage().pendingGuardianTimestamp);
        harness.finalizeRecoveryGuardianUpdateViaLibrary();
        harness.acceptGuardianRecoveryViaLibrary();
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.UnauthorizedRecoveryGuardianAcceptance.selector,
                NEW_GUARDIAN_A,
                address(0)
            )
        );
        vm.prank(NEW_GUARDIAN_A);
        harness.enforceOnlyRecoveryPendingGuardianViaLibrary();

        // Verify: pending guardian is cleared after cancel/accept flows.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().pendingGuardian,
            address(0),
            "pending guardian should be cleared after cancel/accept flows"
        );
    }

    /// @dev Verifies that internal clear helper resets pending-init and leaves other fields untouched.
    function test_clearPendingInit_helperBehavior() public {
        // Setup: reconfigure baseline recovery address and timelock, seed pending deferred-init tuple, and seed pending
        // recovery-guardian update.
        _resetAndConfigureRecovery();
        recoveryStateHarness.setGuardianRecoveryPendingUpdate(NEW_GUARDIAN_B, block.timestamp + 8 days, true);
        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS_B, 4 days, block.timestamp + 6 days
        );
        GuardianRecoveryState memory beforeState = harness.getGuardianRecoveryStateViaStorage();

        // Call: clear pending deferred-init tuple.
        harness.clearPendingGuardianRecoveryInitTimelockViaLibrary();
        harness.clearPendingGuardianRecoveryInitTimelockViaLibrary();

        // Verify: pending-init address clears; pending-init timelock clears.
        GuardianRecoveryState memory afterState = harness.getGuardianRecoveryStateViaStorage();
        assertEq(afterState.pendingInit.pendingRecoveryAddress, address(0), "pending-init address should clear");
        assertEq(afterState.pendingInit.pendingTimelockDurationSeconds, 0, "pending-init timelock should clear");
        assertEq(afterState.pendingInit.pendingTimestamp, 0, "pending-init timestamp should clear");
        assertEq(afterState.recoveryAddress, beforeState.recoveryAddress, "config recovery address should remain");
        assertEq(
            afterState.timelockDurationSeconds, beforeState.timelockDurationSeconds, "config timelock should remain"
        );
        assertEq(
            afterState.pendingGuardian, beforeState.pendingGuardian, "recovery-update pending guardian should remain"
        );
        assertEq(
            afterState.pendingGuardianTimestamp,
            beforeState.pendingGuardianTimestamp,
            "recovery-update pending timestamp should remain"
        );
        assertEq(
            afterState.isUpdateReadyForAcceptance,
            beforeState.isUpdateReadyForAcceptance,
            "recovery-update ready flag should remain"
        );
    }

    /// @dev Verifies that not-configured validation helper accepts all-zero and reverts on any configured field.
    function test_validateNotConfigured_helperBehavior() public {
        // Setup: start from clean recovery state.
        harness.resetGuardianRecoveryStorageViaHarness();

        // Call: validate not-configured precondition, expecting `GuardianRecoveryAlreadyConfigured` revert.
        harness.validateGuardianRecoveryNotConfiguredOrRevertViaLibrary();

        recoveryStateHarness.setGuardianRecoveryConfig(GUARDIAN_RECOVERY_ADDRESS, 0);
        vm.expectRevert(IOrganizationGuardianRecovery.GuardianRecoveryAlreadyConfigured.selector);
        harness.validateGuardianRecoveryNotConfiguredOrRevertViaLibrary();

        recoveryStateHarness.setGuardianRecoveryConfig(address(0), 4 days);
        vm.expectRevert(IOrganizationGuardianRecovery.GuardianRecoveryAlreadyConfigured.selector);
        harness.validateGuardianRecoveryNotConfiguredOrRevertViaLibrary();

        recoveryStateHarness.setGuardianRecoveryConfig(GUARDIAN_RECOVERY_ADDRESS, 4 days);
        vm.expectRevert(IOrganizationGuardianRecovery.GuardianRecoveryAlreadyConfigured.selector);
        harness.validateGuardianRecoveryNotConfiguredOrRevertViaLibrary();

        // Verify: configured state remains as set in final branch.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().timelockDurationSeconds,
            4 days,
            "configured state should remain as set in final branch"
        );
    }

    /// @dev Verifies that params validation helper enforces address checks, range checks, and boundaries.
    function test_validateParams_helperBehavior() public {
        // Setup: reuse suite baseline where recovery is preconfigured.

        // Call: validate boundary and non-boundary in-range recovery params, then assert invalid branches revert.
        harness.validateGuardianRecoveryParamsOrRevertViaLibrary(GUARDIAN_RECOVERY_ADDRESS, 2 days);
        harness.validateGuardianRecoveryParamsOrRevertViaLibrary(GUARDIAN_RECOVERY_ADDRESS, 7 days);
        harness.validateGuardianRecoveryParamsOrRevertViaLibrary(GUARDIAN_RECOVERY_ADDRESS, 30 days);

        vm.expectRevert(IOrganizationGuardianRecovery.InvalidGuardianRecoveryAddress.selector);
        harness.validateGuardianRecoveryParamsOrRevertViaLibrary(address(0), GUARDIAN_RECOVERY_TIMELOCK);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                1 days,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        harness.validateGuardianRecoveryParamsOrRevertViaLibrary(GUARDIAN_RECOVERY_ADDRESS, 1 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                31 days,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        harness.validateGuardianRecoveryParamsOrRevertViaLibrary(GUARDIAN_RECOVERY_ADDRESS, 31 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                0,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        harness.validateGuardianRecoveryParamsOrRevertViaLibrary(GUARDIAN_RECOVERY_ADDRESS, 0);

        vm.expectRevert(IOrganizationGuardianRecovery.InvalidGuardianRecoveryAddress.selector);
        harness.validateGuardianRecoveryParamsOrRevertViaLibrary(address(0), 31 days);

        // Verify: all validation branches executed as expected.
        assertTrue(true, "all validation branches executed as expected");
    }
}
