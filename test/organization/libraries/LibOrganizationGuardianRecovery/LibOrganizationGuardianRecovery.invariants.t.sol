// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {TimelockUtils} from "libraries/TimelockUtils.sol";
import {
    LibOrganizationGuardianRecoveryInvariantHandler
} from "test/organization/libraries/LibOrganizationGuardianRecovery/LibOrganizationGuardianRecoveryInvariantHandler.sol";
import {
    LibOrganizationGuardianRecoverySuiteBase
} from "test/organization/libraries/LibOrganizationGuardianRecovery/LibOrganizationGuardianRecoverySuiteBase.sol";
import {GuardianRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Stateful invariant tests for `LibOrganizationGuardianRecovery`.
 */
contract LibOrganizationGuardianRecoveryInvariants is LibOrganizationGuardianRecoverySuiteBase {
    /// @dev Stateful mutation handler.
    LibOrganizationGuardianRecoveryInvariantHandler internal handler;

    /**
     * @dev Deploys handler, seeds tx-recovery fixture, and registers fuzz target.
     */
    function setUp() public override {
        super.setUp();
        _seedNonZeroTxRecoveryState();
        handler = new LibOrganizationGuardianRecoveryInvariantHandler(harness);
        targetContract(address(handler));
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery` recovery and normal pending flows remain isolated from one
    /// another.
    function invariant_OGR_INV_1_recoveryIsolation_pendingFlowsDoNotCrossMutate() public view {
        // Setup: reuse suite baseline where recovery is preconfigured.

        // Call: evaluate invariant predicate on current state.

        // Verify: no invariant-violation flags were raised.
        assertFalse(
            handler.recoveryTouchedNormalFlowViolation(), "recovery operations should not mutate normal pending flow"
        );
        assertFalse(
            handler.normalTouchedRecoveryFlowViolation(), "normal operations should not mutate recovery flow state"
        );
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery` guardian is always non-zero.
    function invariant_OGR_INV_2_guardianAlwaysValid_nonZero() public view {
        // Setup: reuse suite baseline where recovery is preconfigured.

        // Call: evaluate invariant predicate on current state.
        address currentGuardian = harness.getGuardianViaLibrary();

        // Verify: invariant coherence checks hold for this state snapshot.
        assertTrue(currentGuardian != address(0), "guardian should never be zero");
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery` recovery guardian cannot change without timelock/finalize/accept
    /// preconditions.
    function invariant_OGR_INV_3_timelockEnforcement_noBypass() public view {
        // Setup: reuse suite baseline where recovery is preconfigured.

        // Call: evaluate invariant predicate on current state.

        // Verify: no invariant-violation flags were raised.
        assertFalse(
            handler.timelockBypassViolation(), "timelock/finalize/accept preconditions should never be bypassed"
        );
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery` if no recovery pending guardian then pending timestamp=0 and
    /// ready=false.
    function invariant_OGR_INV_4_stateConsistency_noPendingImpliesTimestampZeroAndReadyFalse() public view {
        // Setup: reuse suite baseline where recovery is preconfigured.
        GuardianRecoveryState memory state = harness.getGuardianRecoveryStateViaStorage();

        // Call: evaluate invariant predicate on current state.
        if (state.pendingGuardian == address(0)) {
            // Verify: invariant coherence checks hold for this state snapshot.
            assertEq(state.pendingGuardianTimestamp, 0, "pending timestamp must be zero when no pending guardian");
            assertFalse(state.isUpdateReadyForAcceptance, "ready flag must be false when no pending guardian");
        }
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery` successful accept always clears recovery pending fields.
    function invariant_OGR_INV_5_acceptClearsAllRecoveryPendingFields() public view {
        // Setup: reuse suite baseline where recovery is preconfigured.

        // Call: evaluate invariant predicate on current state.

        // Verify: no invariant-violation flags were raised.
        assertFalse(
            handler.acceptDidNotClearRecoveryPendingViolation(),
            "successful accept must clear all recovery pending fields"
        );
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery` recovery config is immutable after first initialization.
    function invariant_OGR_INV_6_configImmutability_afterInitialization() public view {
        // Setup: reuse suite baseline where recovery is preconfigured.

        // Call: evaluate invariant predicate on current state.

        // Verify: no invariant-violation flags were raised.
        assertFalse(
            handler.configMutatedAfterFirstInitializationViolation(),
            "recovery config should not mutate after first initialization"
        );
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery` if deferred-init pending timestamp is zero then deferred-init
    /// tuple is fully cleared.
    function invariant_OGR_INV_7_deferredInitStateConsistency_zeroTimestampImpliesZeroTuple() public view {
        // Setup: reuse suite baseline where recovery is preconfigured.
        GuardianRecoveryState memory state = harness.getGuardianRecoveryStateViaStorage();

        // Call: evaluate invariant predicate on current state.
        if (state.pendingInit.pendingTimestamp == 0) {
            // Verify: invariant coherence checks hold for this state snapshot.
            assertEq(state.pendingInit.pendingRecoveryAddress, address(0), "pending-init address must be zero");
            assertEq(state.pendingInit.pendingTimelockDurationSeconds, 0, "pending-init timelock must be zero");
        }
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery` guardian-recovery operations never mutate tx-recovery state.
    function invariant_OGR_INV_8_txRecoveryIsolation_neverMutatedByGuardianRecoveryOps() public view {
        // Setup: reuse suite baseline where recovery is preconfigured.

        // Call: evaluate invariant predicate on current state.

        // Verify: no invariant-violation flags were raised.
        assertFalse(handler.txRecoveryMutationViolation(), "guardian-recovery ops must not mutate tx-recovery state");
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery` accept path must not mutate recovery config fields.
    function invariant_OGR_INV_9_acceptDoesNotMutateRecoveryConfigFields() public view {
        // Setup: reuse suite baseline where recovery is preconfigured.

        // Call: evaluate invariant predicate on current state.

        // Verify: no invariant-violation flags were raised.
        assertFalse(handler.acceptMutatedRecoveryConfigViolation(), "accept should not mutate recovery config fields");
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery` ready=true implies pending guardian and pending timestamp are
    /// both set.
    function invariant_OGR_INV_10_readyStateReverseCoherence_readyImpliesPendingTuple() public view {
        // Setup: reuse suite baseline where recovery is preconfigured.
        GuardianRecoveryState memory state = harness.getGuardianRecoveryStateViaStorage();

        // Call: evaluate invariant predicate on current state.
        if (state.isUpdateReadyForAcceptance) {
            // Verify: invariant coherence checks hold for this state snapshot.
            assertTrue(state.pendingGuardian != address(0), "ready=true requires pending guardian");
            assertTrue(state.pendingGuardianTimestamp != 0, "ready=true requires pending timestamp");
        }
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery` deferred-init pending timestamp implies non-zero address and
    /// in-range timelock.
    function invariant_OGR_INV_11_deferredInitReverseCoherence_pendingTimestampImpliesValidTuple() public view {
        // Setup: reuse suite baseline where recovery is preconfigured.
        GuardianRecoveryState memory state = harness.getGuardianRecoveryStateViaStorage();

        // Call: evaluate invariant predicate on current state.
        if (state.pendingInit.pendingTimestamp != 0) {
            // Verify: invariant coherence checks hold for this state snapshot.
            assertTrue(
                state.pendingInit.pendingRecoveryAddress != address(0), "pending-init timestamp requires address"
            );
            assertGe(
                state.pendingInit.pendingTimelockDurationSeconds,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                "pending-init timelock should be >= min"
            );
            assertLe(
                state.pendingInit.pendingTimelockDurationSeconds,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS,
                "pending-init timelock should be <= max"
            );
        }
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery` non-zero pending guardian implies non-zero pending timestamp.
    function invariant_OGR_INV_12_pendingTimestampCoherence_pendingGuardianImpliesTimestamp() public view {
        // Setup: reuse suite baseline where recovery is preconfigured.
        GuardianRecoveryState memory state = harness.getGuardianRecoveryStateViaStorage();

        // Call: evaluate invariant predicate on current state.
        if (state.pendingGuardian != address(0)) {
            // Verify: invariant coherence checks hold for this state snapshot.
            assertTrue(state.pendingGuardianTimestamp != 0, "pending guardian requires non-zero pending timestamp");
        }
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery` config coherence (`recoveryAddress==0` iff `timelock==0`) and
    /// in-range timelock when configured.
    function invariant_OGR_INV_13_configCoherence_addressAndTimelockConsistency() public view {
        // Setup: reuse suite baseline where recovery is preconfigured.
        GuardianRecoveryState memory state = harness.getGuardianRecoveryStateViaStorage();

        // Call: evaluate invariant predicate on current state.
        bool addressConfigured = state.recoveryAddress != address(0);
        bool timelockConfigured = state.timelockDurationSeconds != 0;

        // Verify: invariant coherence checks hold for this state snapshot.
        assertEq(addressConfigured, timelockConfigured, "recoveryAddress==0 iff timelock==0 must hold");
        if (addressConfigured) {
            assertGe(
                state.timelockDurationSeconds,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                "configured timelock should be >= min"
            );
            assertLe(
                state.timelockDurationSeconds,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS,
                "configured timelock should be <= max"
            );
        }
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery` guardian cannot change in recovery flow except through
    /// successful accept.
    function invariant_OGR_INV_14_guardianMutationPoint_onlyRecoveryAcceptCanMutateGuardian() public view {
        // Setup: reuse suite baseline where recovery is preconfigured.

        // Call: evaluate invariant predicate on current state.

        // Verify: no invariant-violation flags were raised.
        assertFalse(
            handler.guardianChangedOutsideRecoveryAcceptViolation(),
            "guardian should only mutate via successful recovery accept"
        );
    }

    /// @dev Verifies `LibOrganizationGuardianRecovery` recovery-update and deferred-init operations do not cross-mutate
    /// each other's fields.
    function invariant_OGR_INV_15_flowFieldIsolation_updateFlowVsDeferredInitFlowIsolation() public view {
        // Setup: reuse suite baseline where recovery is preconfigured.

        // Call: evaluate invariant predicate on current state.

        // Verify: no invariant-violation flags were raised.
        assertFalse(
            handler.flowFieldIsolationViolation(),
            "recovery-update and deferred-init operations should not cross-mutate fields"
        );
    }
}
