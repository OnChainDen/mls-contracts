// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationTxRecovery} from "interfaces/organization/IOrganizationTxRecovery.sol";
import {TimelockUtils} from "libraries/TimelockUtils.sol";
import {
    MockAccountForOrganizationTransaction
} from "test/organization/base/OrganizationAccountTransactionBase/OrganizationAccountTransactionBaseMocks.sol";
import {
    OrganizationTxRecoveryBaseInvariantHandler,
    TxRecoveryInvariantReceiver
} from "test/organization/base/OrganizationTxRecoveryBase/OrganizationTxRecoveryBaseInvariantHandler.sol";
import {
    OrganizationTxRecoveryBaseSuiteBase
} from "test/organization/base/OrganizationTxRecoveryBase/OrganizationTxRecoveryBaseSuiteBase.sol";
import {GuardianRecoveryState, PendingRecoveryInitTimelock, TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Invariant coverage for tx-recovery plan rows `TXR-INV-1` through `TXR-INV-21`.
 */
contract OrganizationTxRecoveryBaseInvariants is OrganizationTxRecoveryBaseSuiteBase {
    MockAccountForOrganizationTransaction internal account;
    TxRecoveryInvariantReceiver internal receiver;
    OrganizationTxRecoveryBaseInvariantHandler internal handler;
    GuardianRecoveryState internal guardianRecoveryBaseline;

    /**
     * @dev Seeds tx-recovery/account fixtures and registers the stateful handler target.
     */
    function setUp() public override {
        super.setUp();

        account = new MockAccountForOrganizationTransaction(address(harness));
        receiver = new TxRecoveryInvariantReceiver();
        harness.setDeployedAccount(address(account), true);
        harness.setPoliciesRoot(bytes32(uint256(0xABCD1234)));

        guardianRecoveryBaseline = GuardianRecoveryState({
            recoveryAddress: address(0xABC1),
            isUpdateReadyForAcceptance: true,
            pendingGuardian: address(0xABC2),
            timelockDurationSeconds: 5 days,
            pendingGuardianTimestamp: block.timestamp + 1234,
            pendingInit: PendingRecoveryInitTimelock({
                pendingRecoveryAddress: address(0xABC3),
                pendingTimelockDurationSeconds: 4 days,
                pendingTimestamp: block.timestamp + 4321
            })
        });
        harness.setGuardianRecoveryState(guardianRecoveryBaseline);

        handler = new OrganizationTxRecoveryBaseInvariantHandler({
            harness_: harness,
            account_: account,
            receiver_: receiver,
            txRecoveryAddress_: TX_RECOVERY,
            trackedAdmin1_: admin1,
            trackedAdmin2_: admin2
        });
        targetContract(address(handler));
    }

    /// @dev Verifies `OrganizationTxRecoveryBase` only allows the configured tx recovery address to invoke protected
    /// state-changing entrypoints.
    function invariant_TXR_INV_1_TXRC_INV_4_onlyTxRecoveryAddressCanCallTxRecoveryProtectedEntrypoints() public {
        // Setup: use the seeded tx-recovery baseline and handler-owned mock account.

        // Call: attempt each protected entrypoint from non-recovery callers.
        for (uint8 i = 0; i < 5; i++) {
            handler.attemptUnauthorizedTxRecoveryEntrypoint(i, uint256(i) + 1);
        }

        // Verify: no unauthorized caller successfully entered a protected path.
        assertFalse(
            handler.unauthorizedTxRecoveryBypassViolation(),
            "TXR-INV-1 violated: non-recovery caller bypassed tx-recovery access control"
        );
    }

    /// @dev Verifies `OrganizationTxRecoveryBase` keeps tx-recovery config write-once after initial configuration.
    function invariant_TXR_INV_2_TXRC_INV_1_txRecoveryConfigWriteOnce_afterInitialization() public {
        // Setup: exercise enable/disable transitions around the configured baseline.
        handler.initiateEnable();
        handler.finalizeEnable(true);
        handler.disableRecovery();

        // Call: read current tx-recovery state snapshot.
        TxRecoveryState memory state = harness.getTxRecoveryState();

        // Verify: configured address/timelock remain immutable.
        assertEq(state.recoveryAddress, TX_RECOVERY, "TXR-INV-2 violated: recovery address mutated");
        assertEq(state.timelockDurationSeconds, TX_RECOVERY_TIMELOCK, "TXR-INV-2 violated: timelock duration mutated");
    }

    /// @dev Verifies `OrganizationTxRecoveryBase` only allows `isEnabled` transitions from false to true through a
    /// successful finalize-enable path.
    function invariant_TXR_INV_3_isEnabledTrueOnlyViaFinalizeEnable() public {
        // Setup: drive representative tx-recovery transitions.
        handler.initiateEnable();
        handler.finalizeEnable(true);
        handler.cancelEnable();

        // Call

        // Verify: no non-finalize path transitioned `isEnabled` to true.
        assertFalse(
            handler.enabledBecameTrueOutsideFinalizeViolation(),
            "TXR-INV-3 violated: non-finalize operation set isEnabled=true"
        );
    }

    /// @dev Verifies `OrganizationTxRecoveryBase` only allows `isEnabled` transitions from true to false through the
    /// disable path (excluding initialization default false).
    function invariant_TXR_INV_4_isEnabledFalseOnlyViaDisableOrInitialFalse() public {
        // Setup: transition enabled->disabled through the handler.
        handler.initiateEnable();
        handler.finalizeEnable(true);
        handler.disableRecovery();

        // Call

        // Verify: no non-disable path transitioned `isEnabled` from true to false.
        assertFalse(
            handler.enabledBecameFalseOutsideDisableViolation(),
            "TXR-INV-4 violated: non-disable operation set isEnabled=false"
        );
    }

    /// @dev Verifies `OrganizationTxRecoveryBase` enabled state implies non-zero config and no pending enable.
    function invariant_TXR_INV_5_enabledStateRequiresConfiguredAndNoPendingEnable() public {
        // Setup: attempt a successful recovery execution path.
        handler.executeRecoveryToReceiver(1, 0);

        // Call: read current tx-recovery state snapshot.
        TxRecoveryState memory state = harness.getTxRecoveryState();

        // Verify: enabled coherence holds whenever `isEnabled` is true.
        if (state.isEnabled) {
            assertTrue(state.recoveryAddress != address(0), "TXR-INV-5 violated: enabled state has zero address");
            assertTrue(state.timelockDurationSeconds != 0, "TXR-INV-5 violated: enabled state has zero timelock");
            assertEq(state.pendingEnableTimestamp, 0, "TXR-INV-5 violated: enabled state has pending enable");
        }
    }

    /// @dev Verifies `OrganizationTxRecoveryBase` pending-enable state implies `isEnabled == false`.
    function invariant_TXR_INV_6_pendingEnableImpliesDisabled() public view {
        // Setup

        // Call: read current tx-recovery state snapshot.
        TxRecoveryState memory state = harness.getTxRecoveryState();

        // Verify: pending-enable and enabled flags are never simultaneously active.
        if (state.pendingEnableTimestamp != 0) {
            assertFalse(state.isEnabled, "TXR-INV-6 violated: pending enable coexists with isEnabled=true");
        }
    }

    /// @dev Verifies `OrganizationTxRecoveryBase` pending-enable state implies configured non-zero tx-recovery
    /// fields.
    function invariant_TXR_INV_7_pendingEnableImpliesConfiguredFields() public view {
        // Setup

        // Call: read current tx-recovery state snapshot.
        TxRecoveryState memory state = harness.getTxRecoveryState();

        // Verify: pending-enable requires both config fields to be non-zero.
        if (state.pendingEnableTimestamp != 0) {
            assertTrue(
                state.recoveryAddress != address(0), "TXR-INV-7 violated: pending enable has zero recovery address"
            );
            assertTrue(state.timelockDurationSeconds != 0, "TXR-INV-7 violated: pending enable has zero timelock");
        }
    }

    /// @dev Verifies `OrganizationTxRecoveryBase` successful disable always clears pending-enable timestamp.
    function invariant_TXR_INV_8_successfulDisableAlwaysClearsPendingEnable() public {
        // Setup: create pending-enable state and attempt disable.
        handler.initiateEnable();
        handler.disableRecovery();

        // Call

        // Verify: no successful disable left pending-enable uncleared.
        assertFalse(
            handler.disableDidNotClearPendingEnableViolation(),
            "TXR-INV-8 violated: disable succeeded without clearing pending enable"
        );
    }

    /// @dev Verifies `OrganizationTxRecoveryBase` zero deferred-init timestamp implies zero deferred-init tuple.
    function invariant_TXR_INV_9_TXRC_INV_10__AOT_INV_4_zeroPendingInitTimestampImpliesZeroDeferredInitTuple()
        public
        view
    {
        // Setup

        // Call: read current tx-recovery state snapshot.
        TxRecoveryState memory state = harness.getTxRecoveryState();

        // Verify: pending-init tuple is fully cleared when timestamp is zero.
        if (state.pendingInit.pendingTimestamp == 0) {
            assertEq(
                state.pendingInit.pendingRecoveryAddress,
                address(0),
                "TXR-INV-9 violated: pending init address not cleared"
            );
            assertEq(
                state.pendingInit.pendingTimelockDurationSeconds,
                0,
                "TXR-INV-9 violated: pending init timelock not cleared"
            );
        }
    }

    /// @dev Verifies the tx-recovery deferred-init tuple is fully well-formed whenever its pending timestamp is
    /// non-zero.
    function invariant_AOT_INV_5_pendingInitTimestampImpliesValidTxRecoveryDeferredInitTuple() public view {
        // Setup

        // Call: read current tx-recovery state snapshot.
        TxRecoveryState memory state = harness.getTxRecoveryState();

        // Verify: non-zero pending timestamps always imply a non-zero address and in-range timelock.
        if (state.pendingInit.pendingTimestamp != 0) {
            assertTrue(
                state.pendingInit.pendingRecoveryAddress != address(0),
                "AOT-INV-5 violated: pending init timestamp requires a recovery address"
            );
            assertGe(
                state.pendingInit.pendingTimelockDurationSeconds,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                "AOT-INV-5 violated: pending init timelock must be >= min"
            );
            assertLe(
                state.pendingInit.pendingTimelockDurationSeconds,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS,
                "AOT-INV-5 violated: pending init timelock must be <= max"
            );
        }
    }

    /// @dev Verifies `OrganizationTxRecoveryBase` configured tx-recovery state cannot overlap with deferred-init
    /// pending state.
    function invariant_TXR_INV_10_configuredStateCannotOverlapWithDeferredInitPending() public view {
        // Setup

        // Call: read current tx-recovery state snapshot.
        TxRecoveryState memory state = harness.getTxRecoveryState();
        bool configured = state.recoveryAddress != address(0) && state.timelockDurationSeconds != 0;

        // Verify: configured state keeps deferred-init pending fields cleared.
        if (configured) {
            assertEq(
                state.pendingInit.pendingRecoveryAddress,
                address(0),
                "TXR-INV-10 violated: configured state has pending init address"
            );
            assertEq(
                state.pendingInit.pendingTimelockDurationSeconds,
                0,
                "TXR-INV-10 violated: configured state has pending init timelock"
            );
            assertEq(state.pendingInit.pendingTimestamp, 0, "TXR-INV-10 violated: configured state has pending init");
        }
    }

    /// @dev Verifies `OrganizationTxRecoveryBase` recovery transaction execution never mutates tx-recovery state.
    function invariant_TXR_INV_11_recoveryExecutionNeverMutatesTxRecoveryState() public {
        // Setup: execute recovery against a receiver target.
        handler.executeRecoveryToReceiver(2, 123);

        // Call

        // Verify: no recovery execution changed tx-recovery config or pending fields.
        assertFalse(
            handler.executeMutatedTxRecoveryViolation(),
            "TXR-INV-11 violated: recovery execution mutated tx-recovery state"
        );
    }

    /// @dev Verifies `OrganizationTxRecoveryBase` recovery-driven account call chains targeting `modifyAdmins` cannot
    /// mutate admin set or voting threshold.
    function invariant_TXR_INV_12_modifyAdminsChainCannotMutateAdminSetOrThreshold() public {
        // Setup: attempt the recovery->account->organization `modifyAdmins` chain.
        handler.attemptModifyAdminsReentrant(3);

        // Call

        // Verify: admin mapping/count/threshold remain unchanged.
        assertFalse(
            handler.modifyAdminsMutationViolation(),
            "TXR-INV-12 violated: modifyAdmins chain mutated admin state or threshold"
        );
    }

    /// @dev Verifies `OrganizationTxRecoveryBase` recovery-driven account call chains targeting `modifyMembers` cannot
    /// mutate member/admin membership mappings.
    function invariant_TXR_INV_13_modifyMembersChainCannotMutateMembershipMappings() public {
        // Setup: attempt the recovery->account->organization `modifyMembers` chain.
        handler.attemptModifyMembersReentrant(4);

        // Call

        // Verify: membership/admin mappings remain unchanged.
        assertFalse(
            handler.modifyMembersMutationViolation(),
            "TXR-INV-13 violated: modifyMembers chain mutated membership/admin mappings"
        );
    }

    /// @dev Verifies `OrganizationTxRecoveryBase` recovery-driven account call chains targeting `setPolicies` cannot
    /// mutate policy state.
    function invariant_TXR_INV_14_setPoliciesChainCannotMutatePolicyState() public {
        // Setup: attempt the recovery->account->organization `setPolicies` chain.
        handler.attemptSetPoliciesReentrant(5);

        // Call

        // Verify: policy root/state remains unchanged.
        assertFalse(
            handler.setPoliciesMutationViolation(), "TXR-INV-14 violated: setPolicies chain mutated policy state"
        );
    }

    /// @dev Verifies `OrganizationTxRecoveryBase` recovery-driven account call chains targeting tx-recovery management
    /// entrypoints cannot mutate tx-recovery state.
    function invariant_TXR_INV_15_txRecoveryManagementChainCannotMutateTxRecoveryState() public {
        // Setup: attempt each tx-recovery management selector through account call-chaining.
        for (uint8 i = 0; i < 4; i++) {
            handler.attemptTxRecoveryManagementReentrant(i);
        }

        // Call

        // Verify: tx-recovery config/enable/pending state remains unchanged.
        assertFalse(
            handler.txRecoveryManagementMutationViolation(),
            "TXR-INV-15 violated: tx-recovery management chain mutated tx-recovery state"
        );
    }

    /// @dev Verifies `OrganizationTxRecoveryBase` reentrancy attempts targeting state-changing organization selectors
    /// cannot succeed during recovery execution.
    function invariant_TXR_INV_16_reentrantOrganizationSelectorsCannotSucceed() public {
        // Setup: attempt a broad organization selector sweep via recovery call-chaining.
        for (uint8 i = 0; i < 30; i++) {
            handler.attemptOrganizationStateChangingSelector(i, uint256(i) + 11);
        }

        // Call

        // Verify: no organization state-changing selector succeeded reentrantly.
        assertFalse(
            handler.reentrantOrganizationSuccessViolation(),
            "TXR-INV-16 violated: reentrant organization state-changing selector succeeded"
        );
    }

    /// @dev Verifies `OrganizationTxRecoveryBase` reentrancy attempts targeting state-changing account selectors cannot
    /// succeed during recovery execution.
    function invariant_TXR_INV_17_reentrantAccountSelectorsCannotSucceed() public {
        // Setup: attempt account `executeTransaction` reentrancy through `to=account`.
        handler.attemptAccountStateChangingSelector(address(harness), 7, 1, 1, 21);

        // Call

        // Verify: no account state-changing selector succeeded reentrantly.
        assertFalse(
            handler.reentrantAccountSuccessViolation(),
            "TXR-INV-17 violated: reentrant account state-changing selector succeeded"
        );
    }

    /// @dev Verifies `OrganizationTxRecoveryBase` reentrancy attempts through `to=organization` and `to=account`
    /// preserve organization/account/tx-recovery snapshots.
    function invariant_TXR_INV_18_reentrancyAttemptsPreserveAllSnapshots() public {
        // Setup: attempt one organization-target and one account-target reentrancy path.
        handler.attemptOrganizationStateChangingSelector(0, 31);
        handler.attemptAccountStateChangingSelector(address(account), 0, 9, 9, 32);

        // Call

        // Verify: no snapshot drift was observed after reentrancy attempts.
        assertFalse(
            handler.reentrantStateDriftViolation(),
            "TXR-INV-18 violated: reentrancy attempt changed organization/account/tx-recovery snapshot"
        );
    }

    /// @dev Verifies `OrganizationTxRecoveryBase` recovery-transaction validation reverts whenever `isEnabled ==
    /// false`.
    function invariant_TXR_INV_19_validateRecoveryTransactionAllowedRevertsWhenDisabled() public {
        // Setup: force disabled state through the tx-recovery disable path.
        handler.disableRecovery();

        // Call: read tx-recovery state and invoke validation when disabled.
        TxRecoveryState memory state = harness.getTxRecoveryState();
        if (!state.isEnabled) {
            vm.expectRevert(IOrganizationTxRecovery.TxRecoveryNotEnabled.selector);
            harness.validateRecoveryAccountTransactionAllowedOrRevertViaHarness();
        }

        // Verify: disabled state is never accepted by transaction-allowed validation.
    }

    /// @dev Verifies `OrganizationTxRecoveryBase` tx-recovery transitions never mutate guardian-recovery state.
    function invariant_TXR_INV_20_TXRC_INV_7_txRecoveryTransitionsNeverMutateGuardianRecoveryState() public {
        // Setup: execute representative tx-recovery transitions.
        handler.initiateEnable();
        handler.finalizeEnable(true);
        handler.disableRecovery();

        // Call: read guardian-recovery snapshot after tx-recovery operations.
        GuardianRecoveryState memory state = harness.getGuardianRecoveryState();

        // Verify: guardian-recovery state remains byte-for-byte equal to baseline.
        assertFalse(
            handler.guardianRecoveryMutationViolation(),
            "TXR-INV-20 violated: tx-recovery transition mutated guardian-recovery state"
        );
        assertEq(state.recoveryAddress, guardianRecoveryBaseline.recoveryAddress, "guardian recovery address mutated");
        assertEq(
            state.isUpdateReadyForAcceptance,
            guardianRecoveryBaseline.isUpdateReadyForAcceptance,
            "guardian ready flag mutated"
        );
        assertEq(state.pendingGuardian, guardianRecoveryBaseline.pendingGuardian, "pending guardian mutated");
        assertEq(
            state.timelockDurationSeconds, guardianRecoveryBaseline.timelockDurationSeconds, "guardian timelock mutated"
        );
        assertEq(
            state.pendingGuardianTimestamp,
            guardianRecoveryBaseline.pendingGuardianTimestamp,
            "guardian pending timestamp mutated"
        );
        assertEq(
            state.pendingInit.pendingRecoveryAddress,
            guardianRecoveryBaseline.pendingInit.pendingRecoveryAddress,
            "guardian pending-init address mutated"
        );
        assertEq(
            state.pendingInit.pendingTimelockDurationSeconds,
            guardianRecoveryBaseline.pendingInit.pendingTimelockDurationSeconds,
            "guardian pending-init timelock mutated"
        );
        assertEq(
            state.pendingInit.pendingTimestamp,
            guardianRecoveryBaseline.pendingInit.pendingTimestamp,
            "guardian pending-init timestamp mutated"
        );
    }

    /// @dev Verifies `OrganizationTxRecoveryBase` successful recovery execution always uses `nonce=0` and
    /// `policyId=0`.
    function invariant_TXR_INV_21_TXRC_INV_6_successfulRecoveryExecutionAlwaysUsesNonceZeroAndPolicyIdZero() public {
        // Setup: execute recovery against a non-reverting target.
        handler.executeRecoveryToReceiver(6, 456);

        // Call

        // Verify: no successful recovery execution observed non-zero nonce/policy tuple.
        assertFalse(
            handler.successfulRecoveryExecutionUsedNonZeroTupleViolation(),
            "TXR-INV-21 violated: successful recovery execution used non-zero nonce or policyId"
        );
    }
}
