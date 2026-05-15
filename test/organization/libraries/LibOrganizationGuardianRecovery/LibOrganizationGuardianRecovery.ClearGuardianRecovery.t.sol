// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {
    LibOrganizationGuardianRecoverySuiteBase
} from "test/organization/libraries/LibOrganizationGuardianRecovery/LibOrganizationGuardianRecoverySuiteBase.sol";
import {GuardianRecoveryState, PendingRecoveryInitTimelock, TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Library-focused tests for `LibOrganizationGuardianRecovery.clearGuardianRecovery`.
 *      Verifies the clear resets every guardian-recovery field, emits the cleared event with the prior recovery
 *      address, preserves the monotonic `initAttemptId`, is idempotent against already-cleared state, and does not
 *      touch the sibling tx-recovery storage.
 *
 *      Designed to be structurally symmetric with
 *      `test/organization/libraries/LibOrganizationTxRecovery/LibOrganizationTxRecovery.ClearTxRecovery.t.sol`,
 *      so a reviewer can compare the two tracks' clear semantics side-by-side.
 */
contract LibOrganizationGuardianRecoveryClearGuardianRecoveryTest is LibOrganizationGuardianRecoverySuiteBase {
    /// @dev Deterministic tx-recovery fixtures used by the cross-track non-mutation test.
    address internal constant TX_RECOVERY_ADDRESS = address(0xBB11);
    address internal constant TX_RECOVERY_ADDRESS_B = address(0xBB12);

    /// @dev Tx-recovery timelock used by the cross-track non-mutation test.
    uint256 internal constant TX_RECOVERY_TIMELOCK = 2 days;

    /**
     * @dev Builds a fully-loaded `GuardianRecoveryState` fixture used by tests that need every field non-zero.
     *      Caller supplies the `initAttemptId` so the preservation test can target a known value.
     */
    function _buildFullyLoadedGuardianRecoveryState(uint256 initAttemptId)
        internal
        view
        returns (GuardianRecoveryState memory)
    {
        return GuardianRecoveryState({
            recoveryAddress: GUARDIAN_RECOVERY_ADDRESS,
            isUpdateReadyForAcceptance: true,
            pendingGuardian: NEW_GUARDIAN_A,
            timelockDurationSeconds: GUARDIAN_RECOVERY_TIMELOCK,
            pendingGuardianTimestamp: block.timestamp + 1 hours,
            pendingInit: PendingRecoveryInitTimelock({
                pendingRecoveryAddress: GUARDIAN_RECOVERY_ADDRESS_B,
                pendingTimelockDurationSeconds: GUARDIAN_RECOVERY_TIMELOCK + 1 days,
                pendingTimestamp: block.timestamp + 2 hours
            }),
            initAttemptId: initAttemptId
        });
    }

    /// @dev Verifies the full before/after profile of `clearGuardianRecovery` over a fully-loaded state:
    ///   - BEFORE clear:
    ///       * Every typed configuration and pending field reads back the seeded non-zero value, so the clear has
    ///         something to do.
    ///       * `_validateGuardianRecoveryNotConfiguredOrRevert` reverts with `GuardianRecoveryAlreadyConfigured`.
    ///       * `initiateInitializeGuardianRecovery` reverts with `GuardianRecoveryAlreadyConfigured`.
    ///   - The clear itself emits `GuardianRecoveryCleared` with the prior recovery address.
    ///   - AFTER clear:
    ///       * Every typed configuration and pending field is zero; `initAttemptId` is preserved unchanged.
    ///       * `_validateGuardianRecoveryNotConfiguredOrRevert` returns successfully (does not revert).
    ///       * `initiateInitializeGuardianRecovery` succeeds and stages a fresh pending-init tuple.
    function test_clearGuardianRecovery_resetsAllConfigAndPendingFields_emitsEvent() public {
        // Setup: seed every field with non-zero values, including pending recovery-guardian update and pending
        // deferred initialization state, so the clear has the maximum surface area to wipe. Use a known
        // `initAttemptId` so the preservation assertion is meaningful. Snapshot the seeded values so the before/after
        // assertions reference the same source of truth without rebuilding expectations.
        uint256 seededInitAttemptId = 3;
        uint256 expectedPendingGuardianTimestamp = block.timestamp + 1 hours;
        uint256 expectedPendingTimelockDurationSeconds = GUARDIAN_RECOVERY_TIMELOCK + 1 days;
        uint256 expectedPendingTimestamp = block.timestamp + 2 hours;
        recoveryStateHarness.setGuardianRecoveryState(_buildFullyLoadedGuardianRecoveryState(seededInitAttemptId));

        // Verify (BEFORE clear): every typed field reads back its seeded non-zero value via the harness getter, so
        // the clear has something to do. Asserting via the same surface we use after the clear keeps the test's
        // before/after style consistent.
        GuardianRecoveryState memory stateBefore = harness.getGuardianRecoveryStateViaStorage();
        assertEq(
            stateBefore.recoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS,
            "seeded recovery address should be present before clear"
        );
        assertTrue(
            stateBefore.isUpdateReadyForAcceptance, "seeded ready-for-acceptance flag should be true before clear"
        );
        assertEq(stateBefore.pendingGuardian, NEW_GUARDIAN_A, "seeded pending guardian should be present before clear");
        assertEq(
            stateBefore.timelockDurationSeconds,
            GUARDIAN_RECOVERY_TIMELOCK,
            "seeded timelock duration should be present before clear"
        );
        assertEq(
            stateBefore.pendingGuardianTimestamp,
            expectedPendingGuardianTimestamp,
            "seeded pending guardian timestamp should be present before clear"
        );
        assertEq(
            stateBefore.pendingInit.pendingRecoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS_B,
            "seeded pending init address should be present before clear"
        );
        assertEq(
            stateBefore.pendingInit.pendingTimelockDurationSeconds,
            expectedPendingTimelockDurationSeconds,
            "seeded pending init timelock should be present before clear"
        );
        assertEq(
            stateBefore.pendingInit.pendingTimestamp,
            expectedPendingTimestamp,
            "seeded pending init timestamp should be present before clear"
        );
        assertEq(stateBefore.initAttemptId, seededInitAttemptId, "seeded initAttemptId should be present before clear");

        // Verify (BEFORE clear): `_validateGuardianRecoveryNotConfiguredOrRevert` reverts because state is configured.
        vm.expectRevert(IOrganizationGuardianRecovery.GuardianRecoveryAlreadyConfigured.selector);
        harness.validateGuardianRecoveryNotConfiguredOrRevertViaLibrary();

        // Verify (BEFORE clear): the deferred-init entry point reverts with the same `AlreadyConfigured` error, so
        // no fresh initialization can begin while state is populated. Uses a different recovery address than the
        // seeded one to prove the revert is triggered by configured state rather than by a duplicate address.
        vm.expectRevert(IOrganizationGuardianRecovery.GuardianRecoveryAlreadyConfigured.selector);
        harness.initiateInitializeGuardianRecoveryViaLibrary(
            GUARDIAN_RECOVERY_ADDRESS_B, GUARDIAN_RECOVERY_TIMELOCK + 1 days
        );

        // Call: expect `GuardianRecoveryCleared` with the prior recovery address, then clear via the library.
        vm.expectEmit(true, true, true, true);
        emit IOrganizationGuardianRecovery.GuardianRecoveryCleared(GUARDIAN_RECOVERY_ADDRESS);
        harness.clearGuardianRecoveryViaLibrary();

        // Verify (AFTER clear): every typed configuration and pending field is reset to its zero value; the
        // monotonic `initAttemptId` is preserved so finalize/cancel replay protection survives the clear.
        GuardianRecoveryState memory stateAfter = harness.getGuardianRecoveryStateViaStorage();
        assertEq(stateAfter.recoveryAddress, address(0), "recovery address should clear");
        assertFalse(stateAfter.isUpdateReadyForAcceptance, "ready-for-acceptance flag should clear");
        assertEq(stateAfter.timelockDurationSeconds, 0, "timelock duration should clear");
        assertEq(stateAfter.pendingGuardian, address(0), "pending guardian should clear");
        assertEq(stateAfter.pendingGuardianTimestamp, 0, "pending guardian timestamp should clear");
        assertEq(stateAfter.pendingInit.pendingRecoveryAddress, address(0), "pending init address should clear");
        assertEq(stateAfter.pendingInit.pendingTimelockDurationSeconds, 0, "pending init timelock should clear");
        assertEq(stateAfter.pendingInit.pendingTimestamp, 0, "pending init timestamp should clear");
        assertEq(stateAfter.initAttemptId, seededInitAttemptId, "initAttemptId should be preserved across clear");

        // Verify (AFTER clear): `_validateGuardianRecoveryNotConfiguredOrRevert` returns successfully, unblocking
        // fresh initialization. The before/after pair around this call is the single most direct proof that the
        // clear toggled the validator's gating predicate.
        harness.validateGuardianRecoveryNotConfiguredOrRevertViaLibrary();

        // Verify (AFTER clear): the deferred-init entry point now succeeds and stages a fresh pending-init tuple
        // bound to the new recovery address + timelock. Confirms the cleared state is genuinely re-initializable
        // via the user-facing flow, not just the internal `initialize` helper.
        harness.initiateInitializeGuardianRecoveryViaLibrary(
            GUARDIAN_RECOVERY_ADDRESS_B, GUARDIAN_RECOVERY_TIMELOCK + 1 days
        );
        GuardianRecoveryState memory afterInitState = harness.getGuardianRecoveryStateViaStorage();
        assertEq(
            afterInitState.pendingInit.pendingRecoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS_B,
            "post-clear initiate-init should stage the new recovery address"
        );
        assertEq(
            afterInitState.pendingInit.pendingTimelockDurationSeconds,
            GUARDIAN_RECOVERY_TIMELOCK + 1 days,
            "post-clear initiate-init should stage the new timelock"
        );
        assertEq(
            afterInitState.pendingInit.pendingTimestamp,
            block.timestamp + ADMIN_OPERATION_TIMELOCK,
            "post-clear initiate-init should stage the pending timestamp at the admin-op timelock horizon"
        );
    }

    /// @dev Verifies the monotonic `initAttemptId` is preserved across `clearGuardianRecovery`. The counter is
    /// intentionally NOT part of the reset surface because it provides cross-cycle replay protection for
    /// finalize/cancel signatures bound to a specific initiation attempt. A clear that reset it could let admins
    /// replay signatures from a prior cycle on a future cycle.
    function test_clearGuardianRecovery_preservesInitAttemptIdCounter() public {
        // Setup: seed full state with `initAttemptId = 7` so the preservation assertion is meaningful.
        uint256 expectedInitAttemptId = 7;
        recoveryStateHarness.setGuardianRecoveryState(_buildFullyLoadedGuardianRecoveryState(expectedInitAttemptId));

        // Call: clear via the library.
        harness.clearGuardianRecoveryViaLibrary();

        // Verify: every other field is reset, but `initAttemptId` retains its prior value.
        GuardianRecoveryState memory state = harness.getGuardianRecoveryStateViaStorage();
        assertEq(state.recoveryAddress, address(0), "recovery address should clear");
        assertEq(state.timelockDurationSeconds, 0, "timelock duration should clear");
        assertEq(
            state.initAttemptId,
            expectedInitAttemptId,
            "initAttemptId must be preserved across clear so finalize/cancel replay protection survives"
        );

        // Verify: a subsequent clear over already-zeroed (but counter-bearing) state still preserves the counter.
        harness.clearGuardianRecoveryViaLibrary();
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().initAttemptId,
            expectedInitAttemptId,
            "initAttemptId must continue to be preserved across repeated clears"
        );
    }

    /// @dev Verifies the clear is idempotent against already-cleared state. Calling it on a zeroed track must succeed
    /// and still emit `GuardianRecoveryCleared(address(0))`, so admins can call it defensively without first
    /// inspecting storage. Idempotency also guarantees the consolidated `clearRecovery` entrypoint never fails
    /// because one of the two tracks happened to be empty already.
    function test_clearGuardianRecovery_idempotentAgainstAlreadyClearedState() public {
        // Setup: wipe guardian recovery storage to baseline zeros (suite base seeds it in setUp).
        recoveryStateHarness.resetGuardianRecoveryStorage();
        GuardianRecoveryState memory preState = harness.getGuardianRecoveryStateViaStorage();
        assertEq(preState.recoveryAddress, address(0), "test sanity: recovery address should already be zero");
        assertEq(preState.timelockDurationSeconds, 0, "test sanity: timelock duration should already be zero");

        // Call: expect the cleared event with `address(0)`, then clear.
        vm.expectEmit(true, true, true, true);
        emit IOrganizationGuardianRecovery.GuardianRecoveryCleared(address(0));
        harness.clearGuardianRecoveryViaLibrary();

        // Verify: state remains all-zero, no spurious mutation.
        GuardianRecoveryState memory postState = harness.getGuardianRecoveryStateViaStorage();
        assertEq(postState.recoveryAddress, address(0), "recovery address should remain zero");
        assertEq(postState.isUpdateReadyForAcceptance, false, "ready-for-acceptance flag should remain false");
        assertEq(postState.timelockDurationSeconds, 0, "timelock duration should remain zero");
        assertEq(postState.pendingGuardian, address(0), "pending guardian should remain zero");

        // Call: a second back-to-back clear still succeeds, proving repeated invocations are safe.
        vm.expectEmit(true, true, true, true);
        emit IOrganizationGuardianRecovery.GuardianRecoveryCleared(address(0));
        harness.clearGuardianRecoveryViaLibrary();
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().recoveryAddress,
            address(0),
            "back-to-back clear should remain a no-op"
        );
    }

    /// @dev Verifies the clear is strictly scoped to the guardian-recovery sub-struct and does not mutate any field
    /// of the sibling tx-recovery storage. Critical because both substructs share a single ERC-7201 namespaced slot
    /// root: a slot-offset bug in the library could silently wipe the wrong track's state.
    function test_clearGuardianRecovery_doesNotMutateTxRecoveryStorage() public {
        // Setup: seed both tracks. Guardian recovery uses the full fixture; tx recovery uses a non-trivial state with
        // pending enable and pending init so any unintended write would be detectable.
        recoveryStateHarness.setGuardianRecoveryState(_buildFullyLoadedGuardianRecoveryState(0));
        TxRecoveryState memory txBefore = TxRecoveryState({
            recoveryAddress: TX_RECOVERY_ADDRESS,
            isEnabled: true,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            pendingEnableTimestamp: block.timestamp + 3 hours,
            pendingInit: PendingRecoveryInitTimelock({
                pendingRecoveryAddress: TX_RECOVERY_ADDRESS_B,
                pendingTimelockDurationSeconds: TX_RECOVERY_TIMELOCK + 1 days,
                pendingTimestamp: block.timestamp + 4 hours
            }),
            initAttemptId: 9
        });
        recoveryStateHarness.setTxRecoveryState(txBefore);

        // Call: clear only the guardian recovery track via the library.
        harness.clearGuardianRecoveryViaLibrary();

        // Verify: guardian recovery is wiped, tx recovery is byte-for-byte identical to its pre-call snapshot.
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().recoveryAddress,
            address(0),
            "guardian recovery address should clear"
        );
        TxRecoveryState memory txAfter = recoveryStateHarness.getTxRecoveryStateStorage();
        assertEq(txAfter.recoveryAddress, txBefore.recoveryAddress, "tx recovery address must not change");
        assertEq(txAfter.isEnabled, txBefore.isEnabled, "tx recovery isEnabled must not change");
        assertEq(
            txAfter.timelockDurationSeconds, txBefore.timelockDurationSeconds, "tx recovery timelock must not change"
        );
        assertEq(
            txAfter.pendingEnableTimestamp,
            txBefore.pendingEnableTimestamp,
            "tx recovery pending enable timestamp must not change"
        );
        assertEq(
            txAfter.pendingInit.pendingRecoveryAddress,
            txBefore.pendingInit.pendingRecoveryAddress,
            "tx recovery pending init address must not change"
        );
        assertEq(
            txAfter.pendingInit.pendingTimelockDurationSeconds,
            txBefore.pendingInit.pendingTimelockDurationSeconds,
            "tx recovery pending init timelock must not change"
        );
        assertEq(
            txAfter.pendingInit.pendingTimestamp,
            txBefore.pendingInit.pendingTimestamp,
            "tx recovery pending init timestamp must not change"
        );
        assertEq(txAfter.initAttemptId, txBefore.initAttemptId, "tx recovery initAttemptId must not change");
    }
}
