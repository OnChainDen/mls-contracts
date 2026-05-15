// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";

import {IOrganizationTxRecovery} from "interfaces/organization/IOrganizationTxRecovery.sol";
import {LibOrganizationTxRecovery} from "organization/libraries/LibOrganizationTxRecovery.sol";
import {
    LibOrganizationAdminOperationTimelockStorage
} from "organization/libraries/storage/LibOrganizationAdminOperationTimelockStorage.sol";
import {LibOrganizationRecoveryStorage} from "organization/libraries/storage/LibOrganizationRecoveryStorage.sol";
import {GuardianRecoveryState, PendingRecoveryInitTimelock, TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Minimal harness wrapping the library functions and storage accessors needed to exercise
 *      `LibOrganizationTxRecovery.clearTxRecovery` at the library level. Defined inline to match the
 *      self-contained-harness pattern already used by `LibOrganizationTxRecovery.Comprehensive.t.sol`.
 */
contract LibOrganizationTxRecoveryClearTxRecoveryHarness {
    function clearTxRecovery() external {
        LibOrganizationTxRecovery.clearTxRecovery();
    }

    function initializeTxRecovery(address recoveryAddress, uint256 timelockDurationSeconds) external {
        LibOrganizationTxRecovery.initializeTxRecovery(recoveryAddress, timelockDurationSeconds);
    }

    function initiateInitializeTxRecovery(address recoveryAddress, uint256 timelockDurationSeconds) external {
        LibOrganizationTxRecovery.initiateInitializeTxRecovery(recoveryAddress, timelockDurationSeconds);
    }

    function validateTxRecoveryNotConfiguredOrRevert() external view {
        LibOrganizationTxRecovery._validateTxRecoveryNotConfiguredOrRevert(
            LibOrganizationRecoveryStorage.layout().txRecovery
        );
    }

    function setAdminOperationTimelockDurationSeconds(uint256 duration) external {
        LibOrganizationAdminOperationTimelockStorage.layout().adminOperationTimelockDurationSeconds = duration;
    }

    function setTxRecoveryState(TxRecoveryState calldata state) external {
        LibOrganizationRecoveryStorage.layout().txRecovery = state;
    }

    function getTxRecoveryState() external view returns (TxRecoveryState memory) {
        return LibOrganizationRecoveryStorage.layout().txRecovery;
    }

    function setGuardianRecoveryState(GuardianRecoveryState calldata state) external {
        LibOrganizationRecoveryStorage.layout().guardianRecovery = state;
    }

    function getGuardianRecoveryState() external view returns (GuardianRecoveryState memory) {
        return LibOrganizationRecoveryStorage.layout().guardianRecovery;
    }
}

/**
 * @dev Library-focused tests for `LibOrganizationTxRecovery.clearTxRecovery`.
 *      Verifies the clear resets every tx-recovery field, emits the cleared event with the prior recovery address,
 *      preserves the monotonic `initAttemptId`, is idempotent against already-cleared state, and does not touch the
 *      sibling guardian recovery storage.
 *
 *      Designed to be structurally symmetric with
 *      `test/organization/libraries/LibOrganizationGuardianRecovery/LibOrganizationGuardianRecovery.ClearGuardianRecovery.t.sol`,
 *      so a reviewer can compare the two tracks' clear semantics side-by-side.
 */
contract LibOrganizationTxRecoveryClearTxRecoveryTest is Test {
    /// @dev Deterministic recovery-address fixtures shared by every test in this suite.
    address internal constant TX_RECOVERY_ADDRESS = address(0xBB11);
    address internal constant TX_RECOVERY_ADDRESS_B = address(0xBB12);
    address internal constant GUARDIAN_RECOVERY_ADDRESS = address(0xAA11);
    address internal constant PENDING_GUARDIAN = address(0xAB11);

    /// @dev Default timelocks used by both recovery tracks.
    uint256 internal constant TX_RECOVERY_TIMELOCK = 2 days;
    uint256 internal constant GUARDIAN_RECOVERY_TIMELOCK = 2 days;

    /// @dev Admin operation timelock used by `initiateInitializeTxRecovery` to compute the pending-init timestamp.
    uint256 internal constant ADMIN_OPERATION_TIMELOCK = 3 days;

    /// @dev Self-contained harness exposing the library entry points + storage accessors used by every case.
    LibOrganizationTxRecoveryClearTxRecoveryHarness internal harness;

    /**
     * @dev Deploys a fresh harness per test for storage isolation and seeds the admin operation timelock used by
     *      the deferred-init flow.
     */
    function setUp() public {
        harness = new LibOrganizationTxRecoveryClearTxRecoveryHarness();
        harness.setAdminOperationTimelockDurationSeconds(ADMIN_OPERATION_TIMELOCK);
    }

    /**
     * @dev Builds a fully-loaded `TxRecoveryState` fixture used by tests that need every field non-zero.
     *      Caller supplies the `initAttemptId` so the preservation test can target a known value.
     */
    function _buildFullyLoadedTxRecoveryState(uint256 initAttemptId) internal view returns (TxRecoveryState memory) {
        return TxRecoveryState({
            recoveryAddress: TX_RECOVERY_ADDRESS,
            isEnabled: true,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            pendingEnableTimestamp: block.timestamp + 1 hours,
            pendingInit: PendingRecoveryInitTimelock({
                pendingRecoveryAddress: TX_RECOVERY_ADDRESS_B,
                pendingTimelockDurationSeconds: TX_RECOVERY_TIMELOCK + 1 days,
                pendingTimestamp: block.timestamp + 2 hours
            }),
            initAttemptId: initAttemptId
        });
    }

    /// @dev Verifies the full before/after profile of `clearTxRecovery` over a fully-loaded state:
    ///   - BEFORE clear:
    ///       * Every typed configuration and pending field reads back the seeded non-zero value, so the clear has
    ///         something to do.
    ///       * `_validateTxRecoveryNotConfiguredOrRevert` reverts with `TransactionRecoveryAlreadyConfigured`.
    ///       * `initiateInitializeTxRecovery` reverts with `TransactionRecoveryAlreadyConfigured`.
    ///   - The clear itself emits `TxRecoveryCleared` with the prior recovery address.
    ///   - AFTER clear:
    ///       * Every typed configuration and pending field is zero; `initAttemptId` is preserved unchanged.
    ///       * `_validateTxRecoveryNotConfiguredOrRevert` returns successfully (does not revert).
    ///       * `initiateInitializeTxRecovery` succeeds and stages a fresh pending-init tuple.
    function test_clearTxRecovery_resetsAllConfigAndPendingFields_emitsEvent() public {
        // Setup: seed every field with non-zero values, including pending enable and pending deferred initialization
        // state, so the clear has the maximum surface area to wipe. Use a known `initAttemptId` so the preservation
        // assertion is meaningful. Snapshot the seeded values so the before/after assertions reference the same
        // source of truth without rebuilding expectations.
        uint256 seededInitAttemptId = 3;
        uint256 expectedPendingEnableTimestamp = block.timestamp + 1 hours;
        uint256 expectedPendingTimelockDurationSeconds = TX_RECOVERY_TIMELOCK + 1 days;
        uint256 expectedPendingTimestamp = block.timestamp + 2 hours;
        harness.setTxRecoveryState(_buildFullyLoadedTxRecoveryState(seededInitAttemptId));

        // Verify (BEFORE clear): every typed field reads back its seeded non-zero value via the harness getter, so
        // the clear has something to do. Asserting via the same surface we use after the clear keeps the test's
        // before/after style consistent.
        TxRecoveryState memory stateBefore = harness.getTxRecoveryState();
        assertEq(
            stateBefore.recoveryAddress, TX_RECOVERY_ADDRESS, "seeded recovery address should be present before clear"
        );
        assertTrue(stateBefore.isEnabled, "seeded isEnabled flag should be true before clear");
        assertEq(
            stateBefore.timelockDurationSeconds,
            TX_RECOVERY_TIMELOCK,
            "seeded timelock duration should be present before clear"
        );
        assertEq(
            stateBefore.pendingEnableTimestamp,
            expectedPendingEnableTimestamp,
            "seeded pending enable timestamp should be present before clear"
        );
        assertEq(
            stateBefore.pendingInit.pendingRecoveryAddress,
            TX_RECOVERY_ADDRESS_B,
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

        // Verify (BEFORE clear): `_validateTxRecoveryNotConfiguredOrRevert` reverts because state is configured.
        vm.expectRevert(IOrganizationTxRecovery.TransactionRecoveryAlreadyConfigured.selector);
        harness.validateTxRecoveryNotConfiguredOrRevert();

        // Verify (BEFORE clear): the deferred-init entry point reverts with the same `AlreadyConfigured` error, so
        // no fresh initialization can begin while state is populated. Uses a different recovery address than the
        // seeded one to prove the revert is triggered by configured state rather than by a duplicate address.
        vm.expectRevert(IOrganizationTxRecovery.TransactionRecoveryAlreadyConfigured.selector);
        harness.initiateInitializeTxRecovery(TX_RECOVERY_ADDRESS_B, TX_RECOVERY_TIMELOCK + 1 days);

        // Call: expect `TxRecoveryCleared` with the prior recovery address, then clear via the library.
        vm.expectEmit(true, true, true, true);
        emit IOrganizationTxRecovery.TxRecoveryCleared(TX_RECOVERY_ADDRESS);
        harness.clearTxRecovery();

        // Verify (AFTER clear): every typed configuration and pending field is reset to its zero value; the
        // monotonic `initAttemptId` is preserved so finalize/cancel replay protection survives the clear.
        TxRecoveryState memory stateAfter = harness.getTxRecoveryState();
        assertEq(stateAfter.recoveryAddress, address(0), "recovery address should clear");
        assertFalse(stateAfter.isEnabled, "isEnabled should clear");
        assertEq(stateAfter.timelockDurationSeconds, 0, "timelock duration should clear");
        assertEq(stateAfter.pendingEnableTimestamp, 0, "pending enable timestamp should clear");
        assertEq(stateAfter.pendingInit.pendingRecoveryAddress, address(0), "pending init address should clear");
        assertEq(stateAfter.pendingInit.pendingTimelockDurationSeconds, 0, "pending init timelock should clear");
        assertEq(stateAfter.pendingInit.pendingTimestamp, 0, "pending init timestamp should clear");
        assertEq(stateAfter.initAttemptId, seededInitAttemptId, "initAttemptId should be preserved across clear");

        // Verify (AFTER clear): `_validateTxRecoveryNotConfiguredOrRevert` returns successfully, unblocking fresh
        // initialization. The before/after pair around this call is the single most direct proof that the clear
        // toggled the validator's gating predicate.
        harness.validateTxRecoveryNotConfiguredOrRevert();

        // Verify (AFTER clear): the deferred-init entry point now succeeds and stages a fresh pending-init tuple
        // bound to the new recovery address + timelock. Confirms the cleared state is genuinely re-initializable
        // via the user-facing flow, not just the internal `initialize` helper.
        harness.initiateInitializeTxRecovery(TX_RECOVERY_ADDRESS_B, TX_RECOVERY_TIMELOCK + 1 days);
        TxRecoveryState memory afterInitState = harness.getTxRecoveryState();
        assertEq(
            afterInitState.pendingInit.pendingRecoveryAddress,
            TX_RECOVERY_ADDRESS_B,
            "post-clear initiate-init should stage the new recovery address"
        );
        assertEq(
            afterInitState.pendingInit.pendingTimelockDurationSeconds,
            TX_RECOVERY_TIMELOCK + 1 days,
            "post-clear initiate-init should stage the new timelock"
        );
        assertEq(
            afterInitState.pendingInit.pendingTimestamp,
            block.timestamp + ADMIN_OPERATION_TIMELOCK,
            "post-clear initiate-init should stage the pending timestamp at the admin-op timelock horizon"
        );
    }

    /// @dev Verifies the monotonic `initAttemptId` is preserved across `clearTxRecovery`. The counter is intentionally
    /// NOT part of the reset surface because it provides cross-cycle replay protection for finalize/cancel signatures
    /// bound to a specific initiation attempt. A clear that reset it could let admins replay signatures from a prior
    /// cycle on a future cycle.
    function test_clearTxRecovery_preservesInitAttemptIdCounter() public {
        // Setup: seed full state with `initAttemptId = 7` so the preservation assertion is meaningful.
        uint256 expectedInitAttemptId = 7;
        harness.setTxRecoveryState(_buildFullyLoadedTxRecoveryState(expectedInitAttemptId));

        // Call: clear via the library.
        harness.clearTxRecovery();

        // Verify: every other field is reset, but `initAttemptId` retains its prior value.
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(state.recoveryAddress, address(0), "recovery address should clear");
        assertEq(state.timelockDurationSeconds, 0, "timelock duration should clear");
        assertEq(
            state.initAttemptId,
            expectedInitAttemptId,
            "initAttemptId must be preserved across clear so finalize/cancel replay protection survives"
        );

        // Verify: a subsequent clear over already-zeroed (but counter-bearing) state still preserves the counter.
        harness.clearTxRecovery();
        assertEq(
            harness.getTxRecoveryState().initAttemptId,
            expectedInitAttemptId,
            "initAttemptId must continue to be preserved across repeated clears"
        );
    }

    /// @dev Verifies the clear is idempotent against already-cleared state. Calling it on a zeroed track must succeed
    /// and still emit `TxRecoveryCleared(address(0))`, so admins can call it defensively without first inspecting
    /// storage. Idempotency also guarantees the consolidated `clearRecovery` entrypoint never fails because one of
    /// the two tracks happened to be empty already.
    function test_clearTxRecovery_idempotentAgainstAlreadyClearedState() public {
        // Setup: leave tx recovery storage at its baseline zero state (the harness is freshly deployed in setUp).
        TxRecoveryState memory preState = harness.getTxRecoveryState();
        assertEq(preState.recoveryAddress, address(0), "test sanity: recovery address should already be zero");
        assertEq(preState.timelockDurationSeconds, 0, "test sanity: timelock duration should already be zero");

        // Call: expect the cleared event with `address(0)`, then clear.
        vm.expectEmit(true, true, true, true);
        emit IOrganizationTxRecovery.TxRecoveryCleared(address(0));
        harness.clearTxRecovery();

        // Verify: state remains all-zero, no spurious mutation.
        TxRecoveryState memory postState = harness.getTxRecoveryState();
        assertEq(postState.recoveryAddress, address(0), "recovery address should remain zero");
        assertEq(postState.isEnabled, false, "isEnabled should remain false");
        assertEq(postState.timelockDurationSeconds, 0, "timelock duration should remain zero");
        assertEq(postState.pendingEnableTimestamp, 0, "pending enable timestamp should remain zero");

        // Call: a second back-to-back clear still succeeds, proving repeated invocations are safe.
        vm.expectEmit(true, true, true, true);
        emit IOrganizationTxRecovery.TxRecoveryCleared(address(0));
        harness.clearTxRecovery();
        assertEq(harness.getTxRecoveryState().recoveryAddress, address(0), "back-to-back clear should remain a no-op");
    }

    /// @dev Verifies the clear is strictly scoped to the tx-recovery sub-struct and does not mutate any field of the
    /// sibling guardian-recovery storage. Critical because both substructs share a single ERC-7201 namespaced slot
    /// root: a slot-offset bug in the library could silently wipe the wrong track's state.
    function test_clearTxRecovery_doesNotMutateGuardianRecoveryStorage() public {
        // Setup: seed both tracks. Tx recovery uses the full fixture; guardian recovery uses a non-trivial state with
        // pending update and pending init so any unintended write would be detectable.
        harness.setTxRecoveryState(_buildFullyLoadedTxRecoveryState(0));
        GuardianRecoveryState memory guardianBefore = GuardianRecoveryState({
            recoveryAddress: GUARDIAN_RECOVERY_ADDRESS,
            isUpdateReadyForAcceptance: true,
            pendingGuardian: PENDING_GUARDIAN,
            timelockDurationSeconds: GUARDIAN_RECOVERY_TIMELOCK,
            pendingGuardianTimestamp: block.timestamp + 3 hours,
            pendingInit: PendingRecoveryInitTimelock({
                pendingRecoveryAddress: address(0xAA12),
                pendingTimelockDurationSeconds: GUARDIAN_RECOVERY_TIMELOCK + 1 days,
                pendingTimestamp: block.timestamp + 4 hours
            }),
            initAttemptId: 9
        });
        harness.setGuardianRecoveryState(guardianBefore);

        // Call: clear only the tx recovery track via the library.
        harness.clearTxRecovery();

        // Verify: tx recovery is wiped, guardian recovery is byte-for-byte identical to its pre-call snapshot.
        assertEq(harness.getTxRecoveryState().recoveryAddress, address(0), "tx recovery address should clear");
        GuardianRecoveryState memory guardianAfter = harness.getGuardianRecoveryState();
        assertEq(
            guardianAfter.recoveryAddress, guardianBefore.recoveryAddress, "guardian recovery address must not change"
        );
        assertEq(
            guardianAfter.timelockDurationSeconds,
            guardianBefore.timelockDurationSeconds,
            "guardian recovery timelock must not change"
        );
        assertEq(
            guardianAfter.pendingGuardian,
            guardianBefore.pendingGuardian,
            "guardian recovery pending guardian must not change"
        );
        assertEq(
            guardianAfter.pendingGuardianTimestamp,
            guardianBefore.pendingGuardianTimestamp,
            "guardian recovery pending guardian timestamp must not change"
        );
        assertEq(
            guardianAfter.isUpdateReadyForAcceptance,
            guardianBefore.isUpdateReadyForAcceptance,
            "guardian recovery ready-for-acceptance flag must not change"
        );
        assertEq(
            guardianAfter.pendingInit.pendingRecoveryAddress,
            guardianBefore.pendingInit.pendingRecoveryAddress,
            "guardian recovery pending init address must not change"
        );
        assertEq(
            guardianAfter.pendingInit.pendingTimelockDurationSeconds,
            guardianBefore.pendingInit.pendingTimelockDurationSeconds,
            "guardian recovery pending init timelock must not change"
        );
        assertEq(
            guardianAfter.pendingInit.pendingTimestamp,
            guardianBefore.pendingInit.pendingTimestamp,
            "guardian recovery pending init timestamp must not change"
        );
        assertEq(
            guardianAfter.initAttemptId, guardianBefore.initAttemptId, "guardian recovery initAttemptId must not change"
        );
    }
}
