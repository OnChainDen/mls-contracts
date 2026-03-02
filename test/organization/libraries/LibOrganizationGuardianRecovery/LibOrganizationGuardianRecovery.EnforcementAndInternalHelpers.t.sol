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
    function test_LOGR_EOGRA_1__LOGR_EOGRA_2__LOGR_EOGRA_3__LOGR_EOGRA_4_enforceOnlyGuardianRecoveryAddress_behavesAsExpected()
        public
    {
        // Setup: configure recovery address/timelock on a clean state.
        _resetAndConfigureRecovery();

        // Call: invoke `LibOrganizationGuardianRecovery.enforceOnlyGuardianRecoveryAddress` as
        // `GUARDIAN_RECOVERY_ADDRESS` and assert the expected revert.
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

        _resetRecoveryState();
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.UnauthorizedGuardianRecoveryAddress.selector, NON_GUARDIAN, address(0)
            )
        );
        vm.prank(NON_GUARDIAN);
        harness.enforceOnlyGuardianRecoveryAddressViaLibrary();

        // Verify: confirm recovery configuration fields.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().recoveryAddress,
            address(0),
            "recovery address should remain zero in unconfigured case"
        );
    }

    /// @dev Verifies that enforce-only-pending-guardian pass/fail behavior including cancel/accept transitions.
    function test_LOGR_EORPG_1__LOGR_EORPG_2__LOGR_EORPG_3__LOGR_EORPG_4__LOGR_EORPG_5_enforceOnlyRecoveryPendingGuardian_behavesAsExpected()
        public
    {
        // Setup: configure recovery address/timelock on a clean state; seed a pending recovery-guardian update.
        _resetAndConfigureRecovery();
        _initiateRecoveryUpdate(NEW_GUARDIAN_A);

        // Call: run the multi-step flow (`LibOrganizationGuardianRecovery.enforceOnlyRecoveryPendingGuardian`,
        // `LibOrganizationGuardianRecovery.cancelRecoveryGuardianUpdate`,
        // `LibOrganizationGuardianRecovery.initiateRecoveryGuardianUpdate`) and assert the revert branch.
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

        _initiateRecoveryUpdate(NEW_GUARDIAN_A);
        _finalizeRecoveryUpdateAfterTimelock();
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

        // Verify: confirm pending recovery-update fields are fully cleared.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().pendingGuardian,
            address(0),
            "pending guardian should be cleared after cancel/accept flows"
        );
    }

    /// @dev Verifies that internal clear helper resets pending-init and leaves other fields untouched.
    function test_LOGR_CPGRIT_1__LOGR_CPGRIT_2__LOGR_CPGRIT_3__LOGR_CPGRIT_4__LOGR_CPGRIT_5_clearPendingInit_helperBehavior()
        public
    {
        // Setup: configure recovery address/timelock on a clean state; seed a pending deferred-init timelock tuple;
        // seed a pending recovery-guardian update.
        _resetAndConfigureRecovery();
        recoveryStateHarness.setGuardianRecoveryPendingUpdate(NEW_GUARDIAN_B, block.timestamp + 8 days, true);
        recoveryStateHarness.setGuardianRecoveryPendingInit(
            GUARDIAN_RECOVERY_ADDRESS_B, 4 days, block.timestamp + 6 days
        );
        GuardianRecoveryState memory beforeState = harness.getGuardianRecoveryStateViaStorage();

        // Call: invoke `LibOrganizationGuardianRecovery._clearPendingGuardianRecoveryInitTimelock`.
        harness.clearPendingGuardianRecoveryInitTimelockViaLibrary();
        harness.clearPendingGuardianRecoveryInitTimelockViaLibrary();

        // Verify: confirm the pending deferred-init tuple is fully cleared.
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
    function test_LOGR_VGRNCOR_1__LOGR_VGRNCOR_2__LOGR_VGRNCOR_3__LOGR_VGRNCOR_4_validateNotConfigured_helperBehavior()
        public
    {
        // Setup: reset library recovery state.
        _resetRecoveryState();

        // Call: invoke `LibOrganizationGuardianRecovery.validateGuardianRecoveryNotConfiguredOrRevert` and assert the
        // expected revert.
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

        // Verify: confirm recovery configuration fields.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().timelockDurationSeconds,
            4 days,
            "configured state should remain as set in final branch"
        );
    }

    /// @dev Verifies that params validation helper enforces address checks, range checks, and boundaries.
    function test_LOGR_VGRPOR_1__LOGR_VGRPOR_2__LOGR_VGRPOR_3__LOGR_VGRPOR_4__LOGR_VGRPOR_5__LOGR_VGRPOR_6__LOGR_VGRPOR_7__LOGR_VGRPOR_8_validateParams_helperBehavior()
        public
    {
        // Setup: use default fixture state.

        // Call: invoke `LibOrganizationGuardianRecovery.validateGuardianRecoveryParamsOrRevert` and assert the expected
        // revert.
        harness.validateGuardianRecoveryParamsOrRevertViaLibrary(GUARDIAN_RECOVERY_ADDRESS, 2 days);
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

        // Verify: confirm the asserted post-conditions.
        assertTrue(true, "all validation branches executed as expected");
    }
}
