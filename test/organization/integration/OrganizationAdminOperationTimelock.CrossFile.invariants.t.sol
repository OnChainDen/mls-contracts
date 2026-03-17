// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {TimelockUtils} from "libraries/TimelockUtils.sol";
import {
    OrganizationAdminOperationTimelockCrossFileHarness
} from "test/organization/integration/OrganizationAdminOperationTimelockCrossFileHarness.sol";
import {GuardianRecoveryState, TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Stateful mutation handler for cross-file admin-operation timelock invariants.
 */
contract OrganizationAdminOperationTimelockCrossFileInvariantHandler is Test {
    uint256 internal constant CONFIGURED_ADMIN_TIMELOCK = 3 days;
    uint256 internal constant DEFAULT_RECOVERY_TIMELOCK = 2 days;

    OrganizationAdminOperationTimelockCrossFileHarness public immutable HARNESS;

    bool public sameBlockGuardianFinalizeViolation;
    bool public sameBlockGuardianRecoveryFinalizeViolation;
    bool public sameBlockTxRecoveryFinalizeViolation;

    /**
     * @dev Deploys the handler against the shared cross-file harness.
     * @param harness_ Cross-file harness under invariant testing.
     */
    constructor(OrganizationAdminOperationTimelockCrossFileHarness harness_) {
        HARNESS = harness_;
        IS_TEST = false;
    }

    /**
     * @dev Attempts a fresh guardian-update initiation after clearing any prior pending state.
     * @param seed Seed used to derive a non-zero pending guardian.
     */
    function initiateGuardianUpdate(uint256 seed) external {
        if (HARNESS.getPendingGuardianViaLibrary() != address(0)) {
            address(HARNESS).call(abi.encodeCall(HARNESS.cancelGuardianUpdateViaLibrary, ()));
        }

        address(HARNESS).call(abi.encodeCall(HARNESS.initiateGuardianUpdateViaLibrary, (_candidate(seed))));
    }

    /**
     * @dev Attempts guardian-update finalization and optionally warps to the pending timestamp first.
     * @param warpToPendingTimestamp Whether to warp forward to the pending finalize timestamp before calling finalize.
     */
    function finalizeGuardianUpdate(bool warpToPendingTimestamp) external {
        uint256 pendingTimestamp = HARNESS.getPendingGuardianUpdateTimestampViaLibrary();
        if (warpToPendingTimestamp && pendingTimestamp != 0 && block.timestamp < pendingTimestamp) {
            vm.warp(pendingTimestamp);
        }

        address(HARNESS).call(abi.encodeCall(HARNESS.finalizeGuardianUpdateViaLibrary, ()));
    }

    /**
     * @dev Attempts guardian-update cancellation.
     */
    function cancelGuardianUpdate() external {
        address(HARNESS).call(abi.encodeCall(HARNESS.cancelGuardianUpdateViaLibrary, ()));
    }

    /**
     * @dev Attempts deferred guardian-recovery initialization after clearing any prior pending tuple.
     * @param seed Seed used to derive a non-zero recovery address.
     * @param timelockDurationSeconds Candidate guardian-recovery timelock duration to bind to the pending tuple.
     */
    function initiateGuardianRecoveryDeferredInit(uint256 seed, uint256 timelockDurationSeconds) external {
        GuardianRecoveryState memory state = HARNESS.getGuardianRecoveryStateViaStorage();
        if (state.pendingInit.pendingTimestamp != 0) {
            address(HARNESS).call(abi.encodeCall(HARNESS.cancelInitializeGuardianRecoveryViaLibrary, ()));
        }

        uint256 boundedTimelock = bound(
            timelockDurationSeconds,
            TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
            TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        );
        address(HARNESS)
            .call(
                abi.encodeCall(
                    HARNESS.initiateInitializeGuardianRecoveryViaLibrary, (_candidate(seed), boundedTimelock)
                )
            );
    }

    /**
     * @dev Attempts deferred guardian-recovery finalization and optionally warps to the pending timestamp first.
     * @param warpToPendingTimestamp Whether to warp forward to the pending finalize timestamp before calling finalize.
     */
    function finalizeGuardianRecoveryDeferredInit(bool warpToPendingTimestamp) external {
        uint256 pendingTimestamp = HARNESS.getGuardianRecoveryStateViaStorage().pendingInit.pendingTimestamp;
        if (warpToPendingTimestamp && pendingTimestamp != 0 && block.timestamp < pendingTimestamp) {
            vm.warp(pendingTimestamp);
        }

        address(HARNESS).call(abi.encodeCall(HARNESS.finalizeInitializeGuardianRecoveryViaLibrary, ()));
    }

    /**
     * @dev Attempts deferred guardian-recovery cancellation.
     */
    function cancelGuardianRecoveryDeferredInit() external {
        address(HARNESS).call(abi.encodeCall(HARNESS.cancelInitializeGuardianRecoveryViaLibrary, ()));
    }

    /**
     * @dev Attempts deferred tx-recovery initialization after clearing any prior pending tuple.
     * @param seed Seed used to derive a non-zero recovery address.
     * @param timelockDurationSeconds Candidate tx-recovery timelock duration to bind to the pending tuple.
     */
    function initiateTxRecoveryDeferredInit(uint256 seed, uint256 timelockDurationSeconds) external {
        TxRecoveryState memory state = HARNESS.getTxRecoveryStateViaStorage();
        if (state.pendingInit.pendingTimestamp != 0) {
            address(HARNESS).call(abi.encodeCall(HARNESS.cancelInitializeTxRecoveryViaLibrary, ()));
        }

        uint256 boundedTimelock = bound(
            timelockDurationSeconds,
            TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
            TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        );
        address(HARNESS)
            .call(abi.encodeCall(HARNESS.initiateInitializeTxRecoveryViaLibrary, (_candidate(seed), boundedTimelock)));
    }

    /**
     * @dev Attempts deferred tx-recovery finalization and optionally warps to the pending timestamp first.
     * @param warpToPendingTimestamp Whether to warp forward to the pending finalize timestamp before calling finalize.
     */
    function finalizeTxRecoveryDeferredInit(bool warpToPendingTimestamp) external {
        uint256 pendingTimestamp = HARNESS.getTxRecoveryStateViaStorage().pendingInit.pendingTimestamp;
        if (warpToPendingTimestamp && pendingTimestamp != 0 && block.timestamp < pendingTimestamp) {
            vm.warp(pendingTimestamp);
        }

        address(HARNESS).call(abi.encodeCall(HARNESS.finalizeInitializeTxRecoveryViaLibrary, ()));
    }

    /**
     * @dev Attempts deferred tx-recovery cancellation.
     */
    function cancelTxRecoveryDeferredInit() external {
        address(HARNESS).call(abi.encodeCall(HARNESS.cancelInitializeTxRecoveryViaLibrary, ()));
    }

    /**
     * @dev Attempts to finalize a guardian update in the same block it was initiated.
     * @param seed Seed used to derive a non-zero pending guardian.
     */
    function attemptSameBlockGuardianFinalize(uint256 seed) external {
        if (HARNESS.getPendingGuardianViaLibrary() != address(0)) {
            address(HARNESS).call(abi.encodeCall(HARNESS.cancelGuardianUpdateViaLibrary, ()));
        }

        (bool initiated,) =
            address(HARNESS).call(abi.encodeCall(HARNESS.initiateGuardianUpdateViaLibrary, (_candidate(seed))));
        if (!initiated) {
            return;
        }

        (bool finalized,) = address(HARNESS).call(abi.encodeCall(HARNESS.finalizeGuardianUpdateViaLibrary, ()));
        if (finalized) {
            sameBlockGuardianFinalizeViolation = true;
        }
    }

    /**
     * @dev Attempts to finalize a deferred guardian-recovery initialization in the same block it was initiated.
     * @param seed Seed used to derive a non-zero recovery address.
     */
    function attemptSameBlockGuardianRecoveryFinalize(uint256 seed) external {
        GuardianRecoveryState memory state = HARNESS.getGuardianRecoveryStateViaStorage();
        if (state.pendingInit.pendingTimestamp != 0) {
            address(HARNESS).call(abi.encodeCall(HARNESS.cancelInitializeGuardianRecoveryViaLibrary, ()));
        }

        (bool initiated,) = address(HARNESS)
            .call(
                abi.encodeCall(
                    HARNESS.initiateInitializeGuardianRecoveryViaLibrary, (_candidate(seed), DEFAULT_RECOVERY_TIMELOCK)
                )
            );
        if (!initiated) {
            return;
        }

        (bool finalized,) =
            address(HARNESS).call(abi.encodeCall(HARNESS.finalizeInitializeGuardianRecoveryViaLibrary, ()));
        if (finalized) {
            sameBlockGuardianRecoveryFinalizeViolation = true;
        }
    }

    /**
     * @dev Attempts to finalize a deferred tx-recovery initialization in the same block it was initiated.
     * @param seed Seed used to derive a non-zero recovery address.
     */
    function attemptSameBlockTxRecoveryFinalize(uint256 seed) external {
        TxRecoveryState memory state = HARNESS.getTxRecoveryStateViaStorage();
        if (state.pendingInit.pendingTimestamp != 0) {
            address(HARNESS).call(abi.encodeCall(HARNESS.cancelInitializeTxRecoveryViaLibrary, ()));
        }

        (bool initiated,) = address(HARNESS)
            .call(
                abi.encodeCall(
                    HARNESS.initiateInitializeTxRecoveryViaLibrary, (_candidate(seed), DEFAULT_RECOVERY_TIMELOCK)
                )
            );
        if (!initiated) {
            return;
        }

        (bool finalized,) = address(HARNESS).call(abi.encodeCall(HARNESS.finalizeInitializeTxRecoveryViaLibrary, ()));
        if (finalized) {
            sameBlockTxRecoveryFinalizeViolation = true;
        }
    }

    /**
     * @dev Advances block time by a bounded delta to exercise post-expiry states during invariant campaigns.
     * @param delta Candidate seconds to advance.
     */
    function warpForward(uint256 delta) external {
        vm.warp(block.timestamp + bound(delta, 0, 30 days));
    }

    /**
     * @dev Returns the configured admin-operation timelock used as the immutability baseline.
     * @return durationSeconds Canonical admin-operation timelock duration.
     */
    function configuredAdminTimelock() external pure returns (uint256 durationSeconds) {
        return CONFIGURED_ADMIN_TIMELOCK;
    }

    /**
     * @dev Derives a deterministic non-zero address from an arbitrary seed.
     * @param seed Seed used to derive the candidate address.
     * @return candidate Derived non-zero address.
     */
    function _candidate(uint256 seed) internal pure returns (address candidate) {
        candidate = address(uint160(uint256(keccak256(abi.encode(seed))) | uint256(1)));
    }
}

/**
 * @dev Cross-file invariant coverage for admin-operation timelock range, immutability, same-block finalization, and
 * deferred-init tuple coherence.
 */
contract OrganizationAdminOperationTimelockCrossFileInvariants is Test {
    uint256 internal constant CONFIGURED_ADMIN_TIMELOCK = 3 days;

    OrganizationAdminOperationTimelockCrossFileHarness internal harness;
    OrganizationAdminOperationTimelockCrossFileInvariantHandler internal handler;

    /**
     * @dev Deploys the shared harness, seeds canonical admin-operation timelock + guardian state, and registers the
     * stateful mutation handler.
     */
    function setUp() public {
        harness = new OrganizationAdminOperationTimelockCrossFileHarness();
        harness.initializeAdminOperationTimelockViaLibrary(CONFIGURED_ADMIN_TIMELOCK);
        harness.initializeGuardianViaLibrary(address(0xC101));

        handler = new OrganizationAdminOperationTimelockCrossFileInvariantHandler(harness);
        targetContract(address(handler));
    }

    /**
     * @dev Verifies initialized admin-operation timelocks remain within the documented `[2 days, 30 days]` range.
     */
    function invariant_AOT_INV_1_initializedAdminOperationTimelockAlwaysRemainsInRange() public view {
        // Setup: use the shared cross-file harness and its current admin-operation timelock snapshot.
        uint256 durationSeconds = harness.getAdminOperationTimelockDurationSeconds();

        // Call: evaluate the persisted admin-operation timelock.

        // Verify: the configured duration never leaves the supported range.
        assertGe(
            durationSeconds,
            TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
            "admin-operation timelock must stay above the minimum bound"
        );
        assertLe(
            durationSeconds,
            TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS,
            "admin-operation timelock must stay below the maximum bound"
        );
    }

    /**
     * @dev Verifies guardian and recovery operations never mutate the configured admin-operation timelock.
     */
    function invariant_AOT_INV_2_guardianAndRecoveryFlowsCannotMutateAdminOperationTimelock() public view {
        // Setup: use the shared cross-file harness and its current admin-operation timelock snapshot.
        uint256 durationSeconds = harness.getAdminOperationTimelockDurationSeconds();

        // Call: evaluate the persisted admin-operation timelock after arbitrary handler-driven operation sequences.

        // Verify: every sequence preserves the original configured admin-operation timelock exactly.
        assertEq(
            durationSeconds,
            CONFIGURED_ADMIN_TIMELOCK,
            "guardian or recovery operations must not mutate the admin-operation timelock"
        );
    }

    /**
     * @dev Verifies no admin-operation-timelocked flow can be finalized in the same block it is initiated.
     */
    function invariant_AOT_INV_3_sameBlockFinalizationNeverSucceedsForAdminTimelockedFlows() public view {
        // Setup: use the handler's sticky violation flags recorded across same-block finalize attempts.

        // Call: read the accumulated violation flags.

        // Verify: none of the same-block finalize probes ever succeeded unexpectedly.
        assertFalse(
            handler.sameBlockGuardianFinalizeViolation(),
            "guardian updates must not finalize in the same block they are initiated"
        );
        assertFalse(
            handler.sameBlockGuardianRecoveryFinalizeViolation(),
            "guardian recovery deferred-init must not finalize in the same block it is initiated"
        );
        assertFalse(
            handler.sameBlockTxRecoveryFinalizeViolation(),
            "tx recovery deferred-init must not finalize in the same block it is initiated"
        );
    }

    /**
     * @dev Verifies zero deferred-init timestamps imply zero pending addresses and pending timelocks for both
     * guardian recovery and tx recovery.
     */
    function invariant_AOT_INV_4_zeroPendingTimestampImpliesZeroDeferredInitTupleForBothRecoveryModules() public view {
        // Setup: read the current guardian-recovery and tx-recovery deferred-init snapshots.
        GuardianRecoveryState memory guardianRecoveryState = harness.getGuardianRecoveryStateViaStorage();
        TxRecoveryState memory txRecoveryState = harness.getTxRecoveryStateViaStorage();

        // Call: evaluate each deferred-init tuple against its timestamp.

        // Verify: clearing the pending timestamp always clears the rest of the deferred-init tuple as well.
        if (guardianRecoveryState.pendingInit.pendingTimestamp == 0) {
            assertEq(
                guardianRecoveryState.pendingInit.pendingRecoveryAddress,
                address(0),
                "guardian recovery zero pending timestamp must imply zero pending address"
            );
            assertEq(
                guardianRecoveryState.pendingInit.pendingTimelockDurationSeconds,
                0,
                "guardian recovery zero pending timestamp must imply zero pending timelock"
            );
        }

        if (txRecoveryState.pendingInit.pendingTimestamp == 0) {
            assertEq(
                txRecoveryState.pendingInit.pendingRecoveryAddress,
                address(0),
                "tx recovery zero pending timestamp must imply zero pending address"
            );
            assertEq(
                txRecoveryState.pendingInit.pendingTimelockDurationSeconds,
                0,
                "tx recovery zero pending timestamp must imply zero pending timelock"
            );
        }
    }

    /**
     * @dev Verifies non-zero deferred-init timestamps imply non-zero pending addresses and in-range pending
     * timelocks for both guardian recovery and tx recovery.
     */
    function invariant_AOT_INV_5_nonZeroPendingTimestampImpliesWellFormedDeferredInitTupleForBothRecoveryModules()
        public
        view
    {
        // Setup: read the current guardian-recovery and tx-recovery deferred-init snapshots.
        GuardianRecoveryState memory guardianRecoveryState = harness.getGuardianRecoveryStateViaStorage();
        TxRecoveryState memory txRecoveryState = harness.getTxRecoveryStateViaStorage();

        // Call: evaluate each deferred-init tuple against its timestamp.

        // Verify: non-zero pending timestamps always imply non-zero addresses and in-range pending timelocks.
        if (guardianRecoveryState.pendingInit.pendingTimestamp != 0) {
            assertTrue(
                guardianRecoveryState.pendingInit.pendingRecoveryAddress != address(0),
                "guardian recovery non-zero pending timestamp must imply a pending address"
            );
            assertGe(
                guardianRecoveryState.pendingInit.pendingTimelockDurationSeconds,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                "guardian recovery pending timelock must be >= min"
            );
            assertLe(
                guardianRecoveryState.pendingInit.pendingTimelockDurationSeconds,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS,
                "guardian recovery pending timelock must be <= max"
            );
        }

        if (txRecoveryState.pendingInit.pendingTimestamp != 0) {
            assertTrue(
                txRecoveryState.pendingInit.pendingRecoveryAddress != address(0),
                "tx recovery non-zero pending timestamp must imply a pending address"
            );
            assertGe(
                txRecoveryState.pendingInit.pendingTimelockDurationSeconds,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                "tx recovery pending timelock must be >= min"
            );
            assertLe(
                txRecoveryState.pendingInit.pendingTimelockDurationSeconds,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS,
                "tx recovery pending timelock must be <= max"
            );
        }
    }
}
