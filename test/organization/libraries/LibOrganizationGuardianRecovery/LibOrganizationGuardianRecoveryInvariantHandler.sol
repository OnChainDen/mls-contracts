// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {TimelockUtils} from "libraries/TimelockUtils.sol";
import {
    LibOrganizationGuardianRecoveryHarness
} from "test/organization/libraries/LibOrganizationGuardianRecovery/LibOrganizationGuardianRecoveryHarness.sol";
import {GuardianRecoveryState, TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Stateful mutation handler for guardian-recovery invariants.
 *      Uses low-level calls so expected reverts do not abort invariant campaigns.
 */
contract LibOrganizationGuardianRecoveryInvariantHandler is Test {
    /// @dev Harness under invariant testing.
    LibOrganizationGuardianRecoveryHarness public immutable HARNESS;

    /// @dev Sticky violation flags consumed by invariant assertions.
    bool public recoveryTouchedNormalFlowViolation;
    bool public normalTouchedRecoveryFlowViolation;
    bool public timelockBypassViolation;
    bool public acceptDidNotClearRecoveryPendingViolation;
    bool public txRecoveryMutationViolation;
    bool public guardianChangedOutsideRecoveryAcceptViolation;
    bool public acceptMutatedRecoveryConfigViolation;
    bool public flowFieldIsolationViolation;
    bool public configMutatedAfterFirstInitializationViolation;

    /// @dev Tracks whether recovery config was ever initialized during campaigns.
    bool private hasSeenConfiguredState;
    address private configuredRecoveryAddress;
    uint256 private configuredTimelock;

    constructor(LibOrganizationGuardianRecoveryHarness harness_) {
        HARNESS = harness_;
        // Invariant target selection should treat this as a fuzz handler, not a test contract.
        IS_TEST = false;
    }

    /**
     * @dev Attempts recovery-update initiate with a fuzzed non-zero guardian.
     */
    function initiateRecovery(uint256 seed) external {
        address candidate = _candidate(seed);
        _runRecoveryUpdateMutation(abi.encodeCall(HARNESS.initiateRecoveryGuardianUpdateViaLibrary, (candidate)));
    }

    /**
     * @dev Attempts recovery-update finalize; optionally warps to pending timestamp first.
     */
    function finalizeRecovery(bool warpToPendingTimestamp) external {
        if (warpToPendingTimestamp) {
            uint256 pendingTimestamp = HARNESS.getGuardianRecoveryStateViaStorage().pendingGuardianTimestamp;
            if (pendingTimestamp != 0 && block.timestamp < pendingTimestamp) {
                vm.warp(pendingTimestamp);
            }
        }
        _runRecoveryUpdateMutation(abi.encodeCall(HARNESS.finalizeRecoveryGuardianUpdateViaLibrary, ()));
    }

    /**
     * @dev Attempts recovery-update cancel.
     */
    function cancelRecovery() external {
        _runRecoveryUpdateMutation(abi.encodeCall(HARNESS.cancelRecoveryGuardianUpdateViaLibrary, ()));
    }

    /**
     * @dev Attempts recovery-update accept.
     */
    function acceptRecovery() external {
        _runRecoveryAcceptMutation();
    }

    /**
     * @dev Attempts deferred-init initiate with fuzzed params.
     */
    function initiateDeferredInit(uint256 seedAddress, uint256 timelock) external {
        address recoveryAddress = _candidate(seedAddress);
        uint256 boundedTimelock =
            bound(timelock, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS);
        _runDeferredInitMutation(
            abi.encodeCall(HARNESS.initiateInitializeGuardianRecoveryViaLibrary, (recoveryAddress, boundedTimelock))
        );
    }

    /**
     * @dev Attempts deferred-init finalize; optionally warps to pending timestamp first.
     */
    function finalizeDeferredInit(bool warpToPendingTimestamp) external {
        if (warpToPendingTimestamp) {
            uint256 pendingTimestamp = HARNESS.getGuardianRecoveryStateViaStorage().pendingInit.pendingTimestamp;
            if (pendingTimestamp != 0 && block.timestamp < pendingTimestamp) {
                vm.warp(pendingTimestamp);
            }
        }
        _runDeferredInitMutation(abi.encodeCall(HARNESS.finalizeInitializeGuardianRecoveryViaLibrary, ()));
    }

    /**
     * @dev Attempts deferred-init cancel.
     */
    function cancelDeferredInit() external {
        _runDeferredInitMutation(abi.encodeCall(HARNESS.cancelInitializeGuardianRecoveryViaLibrary, ()));
    }

    /**
     * @dev Attempts normal guardian update initiate.
     */
    function initiateNormal(uint256 seed) external {
        address candidate = _candidate(seed);
        _runNormalFlowMutation(abi.encodeCall(HARNESS.initiateGuardianUpdateViaLibrary, (candidate)));
    }

    /**
     * @dev Attempts normal guardian update finalize; optionally warps to pending timestamp.
     */
    function finalizeNormal(bool warpToPendingTimestamp) external {
        if (warpToPendingTimestamp) {
            uint256 pendingTimestamp = HARNESS.getPendingGuardianUpdateTimestampViaLibrary();
            if (pendingTimestamp != 0 && block.timestamp < pendingTimestamp) {
                vm.warp(pendingTimestamp);
            }
        }
        _runNormalFlowMutation(abi.encodeCall(HARNESS.finalizeGuardianUpdateViaLibrary, ()));
    }

    /**
     * @dev Attempts normal guardian update cancel.
     */
    function cancelNormal() external {
        _runNormalFlowMutation(abi.encodeCall(HARNESS.cancelGuardianUpdateViaLibrary, ()));
    }

    /**
     * @dev Attempts normal guardian update accept.
     */
    function acceptNormal() external {
        _runNormalFlowMutation(abi.encodeCall(HARNESS.acceptGuardianViaLibrary, ()));
    }

    /**
     * @dev Advances block timestamp by bounded delta.
     */
    function warpForward(uint256 delta) external {
        vm.warp(block.timestamp + bound(delta, 0, 30 days));
    }

    function _runRecoveryUpdateMutation(bytes memory callData) internal {
        address guardianBefore = HARNESS.getGuardianViaLibrary();
        address normalPendingBefore = HARNESS.getPendingGuardianViaLibrary();
        uint256 normalPendingTsBefore = HARNESS.getPendingGuardianUpdateTimestampViaLibrary();
        bool normalReadyBefore = HARNESS.getIsGuardianUpdateReadyForAcceptanceViaLibrary();
        GuardianRecoveryState memory recoveryBefore = HARNESS.getGuardianRecoveryStateViaStorage();
        TxRecoveryState memory txBefore = HARNESS.getTxRecoveryStateViaStorage();

        (bool success,) = address(HARNESS).call(callData);

        GuardianRecoveryState memory recoveryAfter = HARNESS.getGuardianRecoveryStateViaStorage();
        TxRecoveryState memory txAfter = HARNESS.getTxRecoveryStateViaStorage();

        if (success && HARNESS.getGuardianViaLibrary() != guardianBefore) {
            guardianChangedOutsideRecoveryAcceptViolation = true;
        }

        if (
            success
                && (HARNESS.getPendingGuardianViaLibrary() != normalPendingBefore
                    || HARNESS.getPendingGuardianUpdateTimestampViaLibrary() != normalPendingTsBefore
                    || HARNESS.getIsGuardianUpdateReadyForAcceptanceViaLibrary() != normalReadyBefore)
        ) {
            recoveryTouchedNormalFlowViolation = true;
        }

        if (
            success
                && (recoveryAfter.pendingInit.pendingRecoveryAddress
                        != recoveryBefore.pendingInit.pendingRecoveryAddress
                    || recoveryAfter.pendingInit.pendingTimelockDurationSeconds
                        != recoveryBefore.pendingInit.pendingTimelockDurationSeconds
                    || recoveryAfter.pendingInit.pendingTimestamp != recoveryBefore.pendingInit.pendingTimestamp)
        ) {
            flowFieldIsolationViolation = true;
        }

        if (!_sameTxState(txBefore, txAfter)) {
            txRecoveryMutationViolation = true;
        }

        if (
            // forge-lint: disable-next-line(unsafe-typecast)
            success && bytes4(callData) == bytes4(abi.encodeCall(HARNESS.finalizeRecoveryGuardianUpdateViaLibrary, ()))
                && (recoveryBefore.pendingGuardian == address(0)
                    || block.timestamp < recoveryBefore.pendingGuardianTimestamp)
        ) {
            timelockBypassViolation = true;
        }

        _trackConfigImmutability();
    }

    function _runRecoveryAcceptMutation() internal {
        address guardianBefore = HARNESS.getGuardianViaLibrary();
        GuardianRecoveryState memory recoveryBefore = HARNESS.getGuardianRecoveryStateViaStorage();
        TxRecoveryState memory txBefore = HARNESS.getTxRecoveryStateViaStorage();

        (bool success,) = address(HARNESS).call(abi.encodeCall(HARNESS.acceptGuardianRecoveryViaLibrary, ()));

        GuardianRecoveryState memory recoveryAfter = HARNESS.getGuardianRecoveryStateViaStorage();
        TxRecoveryState memory txAfter = HARNESS.getTxRecoveryStateViaStorage();

        if (success) {
            if (
                recoveryBefore.pendingGuardian == address(0) || !recoveryBefore.isUpdateReadyForAcceptance
                    || block.timestamp < recoveryBefore.pendingGuardianTimestamp
            ) {
                timelockBypassViolation = true;
            }

            if (
                recoveryAfter.pendingGuardian != address(0) || recoveryAfter.pendingGuardianTimestamp != 0
                    || recoveryAfter.isUpdateReadyForAcceptance
            ) {
                acceptDidNotClearRecoveryPendingViolation = true;
            }

            if (
                recoveryAfter.recoveryAddress != recoveryBefore.recoveryAddress
                    || recoveryAfter.timelockDurationSeconds != recoveryBefore.timelockDurationSeconds
            ) {
                acceptMutatedRecoveryConfigViolation = true;
            }

            if (HARNESS.getGuardianViaLibrary() == guardianBefore) {
                // This is allowed when pendingGuardian == current guardian.
            }
        } else if (HARNESS.getGuardianViaLibrary() != guardianBefore) {
            guardianChangedOutsideRecoveryAcceptViolation = true;
        }

        if (!_sameTxState(txBefore, txAfter)) {
            txRecoveryMutationViolation = true;
        }

        _trackConfigImmutability();
    }

    function _runDeferredInitMutation(bytes memory callData) internal {
        address guardianBefore = HARNESS.getGuardianViaLibrary();
        GuardianRecoveryState memory recoveryBefore = HARNESS.getGuardianRecoveryStateViaStorage();
        TxRecoveryState memory txBefore = HARNESS.getTxRecoveryStateViaStorage();

        (bool success,) = address(HARNESS).call(callData);

        GuardianRecoveryState memory recoveryAfter = HARNESS.getGuardianRecoveryStateViaStorage();
        TxRecoveryState memory txAfter = HARNESS.getTxRecoveryStateViaStorage();

        if (success && HARNESS.getGuardianViaLibrary() != guardianBefore) {
            guardianChangedOutsideRecoveryAcceptViolation = true;
        }

        if (
            success
                && (recoveryAfter.pendingGuardian != recoveryBefore.pendingGuardian
                    || recoveryAfter.pendingGuardianTimestamp != recoveryBefore.pendingGuardianTimestamp
                    || recoveryAfter.isUpdateReadyForAcceptance != recoveryBefore.isUpdateReadyForAcceptance)
        ) {
            flowFieldIsolationViolation = true;
        }

        if (!_sameTxState(txBefore, txAfter)) {
            txRecoveryMutationViolation = true;
        }

        _trackConfigImmutability();
    }

    function _runNormalFlowMutation(bytes memory callData) internal {
        GuardianRecoveryState memory recoveryBefore = HARNESS.getGuardianRecoveryStateViaStorage();
        TxRecoveryState memory txBefore = HARNESS.getTxRecoveryStateViaStorage();

        (bool success,) = address(HARNESS).call(callData);

        GuardianRecoveryState memory recoveryAfter = HARNESS.getGuardianRecoveryStateViaStorage();
        TxRecoveryState memory txAfter = HARNESS.getTxRecoveryStateViaStorage();

        if (
            success
                && (recoveryAfter.pendingGuardian != recoveryBefore.pendingGuardian
                    || recoveryAfter.pendingGuardianTimestamp != recoveryBefore.pendingGuardianTimestamp
                    || recoveryAfter.isUpdateReadyForAcceptance != recoveryBefore.isUpdateReadyForAcceptance
                    || recoveryAfter.pendingInit.pendingRecoveryAddress
                        != recoveryBefore.pendingInit.pendingRecoveryAddress
                    || recoveryAfter.pendingInit.pendingTimelockDurationSeconds
                        != recoveryBefore.pendingInit.pendingTimelockDurationSeconds
                    || recoveryAfter.pendingInit.pendingTimestamp != recoveryBefore.pendingInit.pendingTimestamp
                    || recoveryAfter.recoveryAddress != recoveryBefore.recoveryAddress
                    || recoveryAfter.timelockDurationSeconds != recoveryBefore.timelockDurationSeconds)
        ) {
            normalTouchedRecoveryFlowViolation = true;
        }

        if (!_sameTxState(txBefore, txAfter)) {
            txRecoveryMutationViolation = true;
        }

        _trackConfigImmutability();
    }

    function _trackConfigImmutability() internal {
        GuardianRecoveryState memory state = HARNESS.getGuardianRecoveryStateViaStorage();
        if (state.recoveryAddress != address(0)) {
            if (!hasSeenConfiguredState) {
                hasSeenConfiguredState = true;
                configuredRecoveryAddress = state.recoveryAddress;
                configuredTimelock = state.timelockDurationSeconds;
            } else if (
                state.recoveryAddress != configuredRecoveryAddress
                    || state.timelockDurationSeconds != configuredTimelock
            ) {
                configMutatedAfterFirstInitializationViolation = true;
            }
        }
    }

    function _sameTxState(TxRecoveryState memory a, TxRecoveryState memory b) internal pure returns (bool) {
        return a.recoveryAddress == b.recoveryAddress && a.isEnabled == b.isEnabled
            && a.timelockDurationSeconds == b.timelockDurationSeconds
            && a.pendingEnableTimestamp == b.pendingEnableTimestamp
            && a.pendingInit.pendingRecoveryAddress == b.pendingInit.pendingRecoveryAddress
            && a.pendingInit.pendingTimelockDurationSeconds == b.pendingInit.pendingTimelockDurationSeconds
            && a.pendingInit.pendingTimestamp == b.pendingInit.pendingTimestamp;
    }

    function _candidate(uint256 seed) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encode(seed))) | 1));
    }
}
