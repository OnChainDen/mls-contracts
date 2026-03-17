// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdminOperationTimelock} from "interfaces/organization/IOrganizationAdminOperationTimelock.sol";
import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {IOrganizationTxRecovery} from "interfaces/organization/IOrganizationTxRecovery.sol";
import {TimelockUtils} from "libraries/TimelockUtils.sol";
import {
    LibOrganizationInitializationHarness
} from "test/organization/OrganizationFactory/OrganizationFactoryHarnesses.sol";
import {
    InitializationSuiteBase
} from "test/organization/base/OrganizationInitializationBase/OrganizationInitializationBaseSuiteBase.sol";
import {
    OrganizationAdminOperationTimelockCrossFileHarness
} from "test/organization/integration/OrganizationAdminOperationTimelockCrossFileHarness.sol";
import {InitializationParams} from "types/CommonTypes.sol";
import {GuardianRecoveryState, PendingRecoveryInitTimelock, TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Cross-file fuzz coverage for admin-operation timelock consumers and shared helper guarantees.
 */
contract OrganizationAdminOperationTimelockCrossFileFuzzTest is InitializationSuiteBase {
    address internal constant NEW_GUARDIAN = address(0xC201);
    address internal constant GUARDIAN_RECOVERY_B = address(0xC202);
    address internal constant TX_RECOVERY_B = address(0xC203);

    /**
     * @dev Verifies all admin-operation timelock initiation call sites compute `pendingTimestamp = start + duration`.
     * @param durationSeconds Fuzzed in-range admin-operation timelock duration shared across the three call sites.
     */
    function testFuzz_AOT_FUZ_1_allAdminTimelockInitiationsComputePendingTimestampFromConfiguredDuration(uint256 durationSeconds)
        public
    {
        // Setup: bound the shared admin-operation timelock and deploy one fresh harness per initiation path.
        uint256 boundedDuration = bound(
            durationSeconds, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        );
        OrganizationAdminOperationTimelockCrossFileHarness guardianHarness = _newCrossFileHarness(boundedDuration);
        OrganizationAdminOperationTimelockCrossFileHarness guardianRecoveryHarness =
            _newCrossFileHarness(boundedDuration);
        OrganizationAdminOperationTimelockCrossFileHarness txRecoveryHarness = _newCrossFileHarness(boundedDuration);

        // Call: initiate each admin-operation-timelocked flow from the current block timestamp.
        guardianHarness.initiateGuardianUpdateViaLibrary(NEW_GUARDIAN);
        guardianRecoveryHarness.initiateInitializeGuardianRecoveryViaLibrary(
            GUARDIAN_RECOVERY_B, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS
        );
        txRecoveryHarness.initiateInitializeTxRecoveryViaLibrary(
            TX_RECOVERY_B, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        );

        // Verify: every pending timestamp uses the shared admin-operation timelock duration, not flow-specific data.
        assertEq(
            guardianHarness.getPendingGuardianUpdateTimestampViaLibrary(),
            block.timestamp + boundedDuration,
            "guardian update should use the configured admin-operation timelock"
        );
        assertEq(
            guardianRecoveryHarness.getGuardianRecoveryStateViaStorage().pendingInit.pendingTimestamp,
            block.timestamp + boundedDuration,
            "guardian recovery deferred-init should use the configured admin-operation timelock"
        );
        assertEq(
            txRecoveryHarness.getTxRecoveryStateViaStorage().pendingInit.pendingTimestamp,
            block.timestamp + boundedDuration,
            "tx recovery deferred-init should use the configured admin-operation timelock"
        );
    }

    /**
     * @dev Verifies every admin-operation-timelocked finalize path behaves as revert/succeed/succeed at `t-1`, `t`,
     * and `t+1`.
     * @param durationSeconds Fuzzed in-range admin-operation timelock duration shared across the finalize paths.
     */
    function testFuzz_AOT_FUZ_2_finalizeTimingUsesSharedTimelockBoundaryAcrossAllCallSites(uint256 durationSeconds)
        public
    {
        // Setup: bound the shared admin-operation timelock used by every timing assertion below.
        uint256 boundedDuration = bound(
            durationSeconds, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        );

        // Call: exercise `t-1`, `t`, and `t+1` timing behavior for each finalize path on fresh harness instances.
        _assertGuardianFinalizeTiming(boundedDuration);
        _assertGuardianRecoveryFinalizeTiming(boundedDuration);
        _assertTxRecoveryFinalizeTiming(boundedDuration);
    }

    /**
     * @dev Verifies out-of-range admin-operation timelock durations always revert organization initialization.
     * @param durationSeconds Fuzzed candidate admin-operation timelock duration.
     */
    function testFuzz_AOT_FUZ_3_outOfRangeAdminTimelockDurationsAlwaysRevertInitialization(uint256 durationSeconds)
        public
    {
        // Setup: deploy a fresh initialization harness and skip in-range durations that belong to the success path.
        vm.assume(
            durationSeconds < TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS
                || durationSeconds > TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        );
        LibOrganizationInitializationHarness harness = _newInitializationHarness();
        InitializationParams memory params = _defaultInitializationParams();
        params.adminOperationTimelockDurationSeconds = durationSeconds;

        // Call: initialize with the out-of-range admin-operation timelock, expecting the exact timelock revert data.
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                durationSeconds,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        harness.initializeViaLibrary(params);

        // Verify: the reverted initialization leaves the admin-operation timelock storage unset.
        assertEq(
            harness.getAdminOperationTimelockStorage(),
            0,
            "reverted initialization should not persist the admin-operation timelock"
        );
    }

    /**
     * @dev Verifies deferred-init cancel/re-init cycles clear pending fields and recompute fresh timestamps for both
     * guardian recovery and tx recovery.
     * @param durationSeconds Fuzzed in-range admin-operation timelock duration shared across both deferred-init flows.
     * @param warpGap Seconds to advance before re-initiating each deferred-init flow.
     */
    function testFuzz_AOT_FUZ_4_cancelAndReinitCyclesClearPendingFieldsAndComputeFreshTimestamps(
        uint256 durationSeconds,
        uint256 warpGap
    ) public {
        // Setup: bound the shared admin-operation timelock and the time gap between cancel and re-init.
        uint256 boundedDuration = bound(
            durationSeconds, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        );
        uint256 boundedWarpGap = bound(warpGap, 1, 30 days);
        OrganizationAdminOperationTimelockCrossFileHarness guardianRecoveryHarness =
            _newCrossFileHarness(boundedDuration);
        OrganizationAdminOperationTimelockCrossFileHarness txRecoveryHarness = _newCrossFileHarness(boundedDuration);

        // Call: cancel and re-initiate both deferred-init flows after advancing time.
        guardianRecoveryHarness.initiateInitializeGuardianRecoveryViaLibrary(
            GUARDIAN_RECOVERY, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS
        );
        guardianRecoveryHarness.cancelInitializeGuardianRecoveryViaLibrary();

        txRecoveryHarness.initiateInitializeTxRecoveryViaLibrary(
            TX_RECOVERY, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        );
        txRecoveryHarness.cancelInitializeTxRecoveryViaLibrary();

        vm.warp(block.timestamp + boundedWarpGap);
        uint256 expectedFreshPendingTimestamp = block.timestamp + boundedDuration;

        guardianRecoveryHarness.initiateInitializeGuardianRecoveryViaLibrary(
            GUARDIAN_RECOVERY_B, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        );
        txRecoveryHarness.initiateInitializeTxRecoveryViaLibrary(
            TX_RECOVERY_B, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS
        );

        // Verify: cancel clears every pending field and re-initiation recomputes timestamps from the new start time.
        GuardianRecoveryState memory guardianRecoveryState =
            guardianRecoveryHarness.getGuardianRecoveryStateViaStorage();
        TxRecoveryState memory txRecoveryState = txRecoveryHarness.getTxRecoveryStateViaStorage();
        assertEq(
            guardianRecoveryState.pendingInit.pendingRecoveryAddress,
            GUARDIAN_RECOVERY_B,
            "guardian recovery re-init should store the new pending address"
        );
        assertEq(
            guardianRecoveryState.pendingInit.pendingTimestamp,
            expectedFreshPendingTimestamp,
            "guardian recovery re-init should compute a fresh pending timestamp"
        );
        assertEq(
            txRecoveryState.pendingInit.pendingRecoveryAddress,
            TX_RECOVERY_B,
            "tx recovery re-init should store the new pending address"
        );
        assertEq(
            txRecoveryState.pendingInit.pendingTimestamp,
            expectedFreshPendingTimestamp,
            "tx recovery re-init should compute a fresh pending timestamp"
        );
    }

    /**
     * @dev Verifies partially configured guardian-recovery and tx-recovery states always fail the internal
     * `notConfigured` guards.
     * @param recoveryAddressSet Whether the configuration address field is non-zero.
     * @param timelockSet Whether the configuration timelock field is non-zero.
     */
    function testFuzz_AOT_FUZ_5_partialRecoveryConfigurationsAlwaysFailInternalNotConfiguredGuards(
        bool recoveryAddressSet,
        bool timelockSet
    ) public {
        // Setup: deploy fresh harnesses and seed either all-zero or partially configured recovery states.
        OrganizationAdminOperationTimelockCrossFileHarness guardianRecoveryHarness =
            _newCrossFileHarness(TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS);
        OrganizationAdminOperationTimelockCrossFileHarness txRecoveryHarness =
            _newCrossFileHarness(TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS);

        address configuredAddress = recoveryAddressSet ? GUARDIAN_RECOVERY : address(0);
        uint256 configuredTimelock = timelockSet ? TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS : 0;
        guardianRecoveryHarness.resetGuardianRecoveryStorage();
        guardianRecoveryHarness.setGuardianRecoveryConfig(configuredAddress, configuredTimelock);
        txRecoveryHarness.resetTxRecoveryStorageViaHarness();
        txRecoveryHarness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: recoveryAddressSet ? TX_RECOVERY : address(0),
                isEnabled: false,
                timelockDurationSeconds: timelockSet ? TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS : 0,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );

        // Call: validate the internal configuration guards against the seeded states.
        if (recoveryAddressSet || timelockSet) {
            vm.expectRevert(IOrganizationGuardianRecovery.GuardianRecoveryAlreadyConfigured.selector);
            guardianRecoveryHarness.validateGuardianRecoveryNotConfiguredOrRevertViaLibrary();

            vm.expectRevert(IOrganizationTxRecovery.TransactionRecoveryAlreadyConfigured.selector);
            txRecoveryHarness.validateTxRecoveryNotConfiguredOrRevertViaLibrary();
        } else {
            guardianRecoveryHarness.validateGuardianRecoveryNotConfiguredOrRevertViaLibrary();
            txRecoveryHarness.validateTxRecoveryNotConfiguredOrRevertViaLibrary();
        }

        // Verify: the seeded configuration bits remain unchanged by the pure validation helpers.
        assertEq(
            guardianRecoveryHarness.getGuardianRecoveryStateViaStorage().recoveryAddress,
            configuredAddress,
            "guardian recovery validation should not mutate the configured address"
        );
        assertEq(
            guardianRecoveryHarness.getGuardianRecoveryStateViaStorage().timelockDurationSeconds,
            configuredTimelock,
            "guardian recovery validation should not mutate the configured timelock"
        );
        assertEq(
            txRecoveryHarness.getTxRecoveryStateViaStorage().recoveryAddress,
            recoveryAddressSet ? TX_RECOVERY : address(0),
            "tx recovery validation should not mutate the configured address"
        );
        assertEq(
            txRecoveryHarness.getTxRecoveryStateViaStorage().timelockDurationSeconds,
            timelockSet ? TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS : 0,
            "tx recovery validation should not mutate the configured timelock"
        );
    }

    /**
     * @dev Deploys a fresh cross-file harness with canonical guardian state and a configured admin-operation
     * timelock.
     * @param durationSeconds Admin-operation timelock duration to persist through the shared library helper.
     * @return harness Newly deployed cross-file harness.
     */
    function _newCrossFileHarness(uint256 durationSeconds)
        internal
        returns (OrganizationAdminOperationTimelockCrossFileHarness harness)
    {
        harness = new OrganizationAdminOperationTimelockCrossFileHarness();
        harness.initializeAdminOperationTimelockViaLibrary(durationSeconds);
        harness.initializeGuardianViaLibrary(GUARDIAN);
    }

    /**
     * @dev Deploys a fresh initialization harness with the prerequisite whitelist and deployer storage seeded.
     * @return harness Newly deployed initialization harness.
     */
    function _newInitializationHarness() internal returns (LibOrganizationInitializationHarness harness) {
        harness = new LibOrganizationInitializationHarness();
        harness.setWhitelistAddressStorage(address(whitelist));
        harness.setDeployerAddressStorage(AUTHORIZED_DEPLOYER);
    }

    /**
     * @dev Asserts guardian-update finalize reverts at `t-1` and succeeds at `t` and `t+1`.
     * @param durationSeconds Admin-operation timelock duration to configure on each fresh harness.
     */
    function _assertGuardianFinalizeTiming(uint256 durationSeconds) internal {
        // Setup: create three fresh guardian-update harnesses so each timestamp branch runs from the same baseline.
        OrganizationAdminOperationTimelockCrossFileHarness beforeHarness = _newCrossFileHarness(durationSeconds);
        OrganizationAdminOperationTimelockCrossFileHarness exactHarness = _newCrossFileHarness(durationSeconds);
        OrganizationAdminOperationTimelockCrossFileHarness afterHarness = _newCrossFileHarness(durationSeconds);

        // Call: initiate and attempt to finalize at `t-1`, then on separate harnesses finalize at `t` and `t+1`.
        beforeHarness.initiateGuardianUpdateViaLibrary(NEW_GUARDIAN);
        uint256 beforePendingTimestamp = beforeHarness.getPendingGuardianUpdateTimestampViaLibrary();
        vm.warp(beforePendingTimestamp - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdminOperationTimelock.TimelockNotExpired.selector,
                beforePendingTimestamp,
                beforePendingTimestamp - 1
            )
        );
        beforeHarness.finalizeGuardianUpdateViaLibrary();

        exactHarness.initiateGuardianUpdateViaLibrary(NEW_GUARDIAN);
        uint256 exactPendingTimestamp = exactHarness.getPendingGuardianUpdateTimestampViaLibrary();
        vm.warp(exactPendingTimestamp);
        exactHarness.finalizeGuardianUpdateViaLibrary();

        afterHarness.initiateGuardianUpdateViaLibrary(NEW_GUARDIAN);
        uint256 afterPendingTimestamp = afterHarness.getPendingGuardianUpdateTimestampViaLibrary();
        vm.warp(afterPendingTimestamp + 1);
        afterHarness.finalizeGuardianUpdateViaLibrary();

        // Verify: the exact-boundary and post-boundary cases succeed by marking the update ready for acceptance.
        assertTrue(
            exactHarness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(),
            "guardian finalize should succeed at the exact admin-operation timelock boundary"
        );
        assertTrue(
            afterHarness.getIsGuardianUpdateReadyForAcceptanceViaLibrary(),
            "guardian finalize should succeed after the admin-operation timelock boundary"
        );
    }

    /**
     * @dev Asserts deferred guardian-recovery finalize reverts at `t-1` and succeeds at `t` and `t+1`.
     * @param durationSeconds Admin-operation timelock duration to configure on each fresh harness.
     */
    function _assertGuardianRecoveryFinalizeTiming(uint256 durationSeconds) internal {
        // Setup: create three fresh deferred-init harnesses so each timestamp branch runs from the same baseline.
        OrganizationAdminOperationTimelockCrossFileHarness beforeHarness = _newCrossFileHarness(durationSeconds);
        OrganizationAdminOperationTimelockCrossFileHarness exactHarness = _newCrossFileHarness(durationSeconds);
        OrganizationAdminOperationTimelockCrossFileHarness afterHarness = _newCrossFileHarness(durationSeconds);

        // Call: initiate and attempt to finalize at `t-1`, then on separate harnesses finalize at `t` and `t+1`.
        beforeHarness.initiateInitializeGuardianRecoveryViaLibrary(
            GUARDIAN_RECOVERY, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS
        );
        uint256 beforePendingTimestamp = beforeHarness.getGuardianRecoveryStateViaStorage().pendingInit.pendingTimestamp;
        vm.warp(beforePendingTimestamp - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdminOperationTimelock.TimelockNotExpired.selector,
                beforePendingTimestamp,
                beforePendingTimestamp - 1
            )
        );
        beforeHarness.finalizeInitializeGuardianRecoveryViaLibrary();

        exactHarness.initiateInitializeGuardianRecoveryViaLibrary(
            GUARDIAN_RECOVERY, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        );
        uint256 exactPendingTimestamp = exactHarness.getGuardianRecoveryStateViaStorage().pendingInit.pendingTimestamp;
        vm.warp(exactPendingTimestamp);
        exactHarness.finalizeInitializeGuardianRecoveryViaLibrary();

        afterHarness.initiateInitializeGuardianRecoveryViaLibrary(
            GUARDIAN_RECOVERY_B, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS
        );
        uint256 afterPendingTimestamp = afterHarness.getGuardianRecoveryStateViaStorage().pendingInit.pendingTimestamp;
        vm.warp(afterPendingTimestamp + 1);
        afterHarness.finalizeInitializeGuardianRecoveryViaLibrary();

        // Verify: exact-boundary and post-boundary finalization configure the pending recovery tuple successfully.
        assertEq(
            exactHarness.getGuardianRecoveryStateViaStorage().recoveryAddress,
            GUARDIAN_RECOVERY,
            "guardian recovery finalize should succeed at the exact admin-operation timelock boundary"
        );
        assertEq(
            afterHarness.getGuardianRecoveryStateViaStorage().recoveryAddress,
            GUARDIAN_RECOVERY_B,
            "guardian recovery finalize should succeed after the admin-operation timelock boundary"
        );
    }

    /**
     * @dev Asserts deferred tx-recovery finalize reverts at `t-1` and succeeds at `t` and `t+1`.
     * @param durationSeconds Admin-operation timelock duration to configure on each fresh harness.
     */
    function _assertTxRecoveryFinalizeTiming(uint256 durationSeconds) internal {
        // Setup: create three fresh deferred-init harnesses so each timestamp branch runs from the same baseline.
        OrganizationAdminOperationTimelockCrossFileHarness beforeHarness = _newCrossFileHarness(durationSeconds);
        OrganizationAdminOperationTimelockCrossFileHarness exactHarness = _newCrossFileHarness(durationSeconds);
        OrganizationAdminOperationTimelockCrossFileHarness afterHarness = _newCrossFileHarness(durationSeconds);

        // Call: initiate and attempt to finalize at `t-1`, then on separate harnesses finalize at `t` and `t+1`.
        beforeHarness.initiateInitializeTxRecoveryViaLibrary(TX_RECOVERY, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS);
        uint256 beforePendingTimestamp = beforeHarness.getTxRecoveryStateViaStorage().pendingInit.pendingTimestamp;
        vm.warp(beforePendingTimestamp - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdminOperationTimelock.TimelockNotExpired.selector,
                beforePendingTimestamp,
                beforePendingTimestamp - 1
            )
        );
        beforeHarness.finalizeInitializeTxRecoveryViaLibrary();

        exactHarness.initiateInitializeTxRecoveryViaLibrary(TX_RECOVERY, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS);
        uint256 exactPendingTimestamp = exactHarness.getTxRecoveryStateViaStorage().pendingInit.pendingTimestamp;
        vm.warp(exactPendingTimestamp);
        exactHarness.finalizeInitializeTxRecoveryViaLibrary();

        afterHarness.initiateInitializeTxRecoveryViaLibrary(TX_RECOVERY_B, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS);
        uint256 afterPendingTimestamp = afterHarness.getTxRecoveryStateViaStorage().pendingInit.pendingTimestamp;
        vm.warp(afterPendingTimestamp + 1);
        afterHarness.finalizeInitializeTxRecoveryViaLibrary();

        // Verify: exact-boundary and post-boundary finalization configure the pending recovery tuple successfully.
        assertEq(
            exactHarness.getTxRecoveryStateViaStorage().recoveryAddress,
            TX_RECOVERY,
            "tx recovery finalize should succeed at the exact admin-operation timelock boundary"
        );
        assertEq(
            afterHarness.getTxRecoveryStateViaStorage().recoveryAddress,
            TX_RECOVERY_B,
            "tx recovery finalize should succeed after the admin-operation timelock boundary"
        );
    }
}
