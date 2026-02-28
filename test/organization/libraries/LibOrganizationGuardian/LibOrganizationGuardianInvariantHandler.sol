// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {
    LibOrganizationGuardianHarness
} from "test/organization/libraries/LibOrganizationGuardian/LibOrganizationGuardianHarness.sol";

/**
 * @dev Stateful mutation handler for `LibOrganizationGuardian` invariants.
 *      Uses low-level calls so expected reverts do not abort invariant campaigns.
 */
contract LibOrganizationGuardianInvariantHandler is Test {
    /// @dev Harness under invariant testing.
    LibOrganizationGuardianHarness public immutable harness;

    /// @dev Sticky flag: guardian changed in a non-accept normal-flow operation.
    bool public guardianChangedOutsideAcceptViolation;

    /// @dev Sticky flag: successful accept did not clear all pending-state fields.
    bool public acceptDidNotClearPendingStateViolation;

    /// @dev Sticky flag: accept succeeded without prior finalize/timelock-ready preconditions.
    bool public acceptWithoutFinalizeOrTimelockViolation;

    /// @dev Candidate guardians used by stateful mutation calls.
    address internal constant CANDIDATE_A = address(0xD101);
    address internal constant CANDIDATE_B = address(0xD102);
    address internal constant CANDIDATE_C = address(0xD103);

    constructor(LibOrganizationGuardianHarness harness_) {
        harness = harness_;
    }

    /**
     * @dev Attempts to initiate a guardian update with a fuzzed candidate address.
     */
    function initiate(uint256 seed) external {
        address newGuardian = _candidateGuardian(seed);
        _executeNonAcceptMutation(abi.encodeCall(harness.initiateGuardianUpdateViaLibrary, (newGuardian)));
    }

    /**
     * @dev Attempts to finalize the current pending update.
     *      Optionally warps to the current pending timestamp first.
     */
    function finalize(bool warpToPendingTimestamp) external {
        if (warpToPendingTimestamp) {
            uint256 pendingTimestamp = harness.getPendingGuardianUpdateTimestampViaLibrary();
            if (pendingTimestamp != 0 && block.timestamp < pendingTimestamp) {
                vm.warp(pendingTimestamp);
            }
        }

        _executeNonAcceptMutation(abi.encodeCall(harness.finalizeGuardianUpdateViaLibrary, ()));
    }

    /**
     * @dev Attempts to cancel the current pending update.
     */
    function cancel() external {
        _executeNonAcceptMutation(abi.encodeCall(harness.cancelGuardianUpdateViaLibrary, ()));
    }

    /**
     * @dev Attempts to accept the current pending update.
     */
    function accept() external {
        address pendingGuardianBefore = harness.getPendingGuardianViaLibrary();
        uint256 pendingTimestampBefore = harness.getPendingGuardianUpdateTimestampViaLibrary();
        bool isReadyBefore = harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary();
        address guardianBefore = harness.getGuardianViaLibrary();
        (bool success,) = address(harness).call(abi.encodeCall(harness.acceptGuardianViaLibrary, ()));
        address guardianAfter = harness.getGuardianViaLibrary();

        if (success) {
            if (
                pendingGuardianBefore == address(0) || !isReadyBefore || pendingTimestampBefore == 0
                    || block.timestamp < pendingTimestampBefore
            ) {
                acceptWithoutFinalizeOrTimelockViolation = true;
            }

            if (
                harness.getPendingGuardianViaLibrary() != address(0)
                    || harness.getPendingGuardianUpdateTimestampViaLibrary() != 0
                    || harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary()
            ) {
                acceptDidNotClearPendingStateViolation = true;
            }

            if (guardianAfter == address(0) || guardianBefore == address(0)) {
                guardianChangedOutsideAcceptViolation = true;
            }
        }
    }

    /**
     * @dev Advances block timestamp by a fuzzed delta to exercise timelock boundaries.
     */
    function warpForward(uint256 delta) external {
        uint256 advanceBy = bound(delta, 0, 30 days);
        vm.warp(block.timestamp + advanceBy);
    }

    /**
     * @dev Executes a non-accept normal-flow mutation and tracks unexpected guardian changes.
     */
    function _executeNonAcceptMutation(bytes memory callData) internal {
        address guardianBefore = harness.getGuardianViaLibrary();
        (bool success,) = address(harness).call(callData);
        address guardianAfter = harness.getGuardianViaLibrary();

        if (success && guardianAfter != guardianBefore) {
            guardianChangedOutsideAcceptViolation = true;
        }
    }

    /**
     * @dev Picks one of three deterministic non-zero candidate guardians.
     */
    function _candidateGuardian(uint256 seed) internal pure returns (address) {
        uint256 idx = seed % 3;
        if (idx == 0) return CANDIDATE_A;
        if (idx == 1) return CANDIDATE_B;
        return CANDIDATE_C;
    }
}
