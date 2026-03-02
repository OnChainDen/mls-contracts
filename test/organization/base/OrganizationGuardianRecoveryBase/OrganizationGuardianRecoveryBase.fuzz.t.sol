// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    OrganizationGuardianRecoveryBaseSuiteBase
} from "test/organization/base/OrganizationGuardianRecoveryBase/OrganizationGuardianRecoveryBaseSuiteBase.sol";

/**
 * @dev Fuzz tests for `OrganizationGuardianRecoveryBase`.
 */
contract OrganizationGuardianRecoveryBaseFuzzTest is OrganizationGuardianRecoveryBaseSuiteBase {
    /// @dev Verifies that non-recovery callers always fail initiate/finalize/cancel recovery entry points.
    function testFuzz_OGR_FZ_13_nonRecoveryCallers_failRecoveryEntryPoints(address caller) public {
        // Setup: use default fixture state.
        vm.assume(caller != GUARDIAN_RECOVERY_ADDRESS);

        // Call: run the multi-step flow (`OrganizationGuardianRecoveryBase.initiateRecoveryGuardianUpdate`,
        // `OrganizationGuardianRecoveryBase.finalizeRecoveryGuardianUpdate`,
        // `OrganizationGuardianRecoveryBase.cancelRecoveryGuardianUpdate`).
        _expectOnlyGuardianRecoveryAddressRevert(caller, GUARDIAN_RECOVERY_ADDRESS);
        vm.prank(caller);
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN_A);

        _expectOnlyGuardianRecoveryAddressRevert(caller, GUARDIAN_RECOVERY_ADDRESS);
        vm.prank(caller);
        harness.finalizeRecoveryGuardianUpdate();

        _expectOnlyGuardianRecoveryAddressRevert(caller, GUARDIAN_RECOVERY_ADDRESS);
        vm.prank(caller);
        harness.cancelRecoveryGuardianUpdate();

        // Verify: confirm pending recovery-update state remains unchanged.
        assertEq(
            harness.getGuardianRecoveryState().pendingGuardian, address(0), "pending guardian should remain unchanged"
        );
        assertEq(
            harness.getGuardianRecoveryState().pendingGuardianTimestamp,
            0,
            "pending guardian timestamp should remain unchanged"
        );
    }
}
