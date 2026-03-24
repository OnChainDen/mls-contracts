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
    /// @dev Verifies `OrganizationGuardianRecoveryBase` recovery entry points always enforce the recovery-address
    /// caller gate.
    function testFuzz_nonRecoveryCallers_failRecoveryEntryPoints(address caller) public {
        // Setup: reuse suite baseline where guardian-recovery is configured.
        vm.assume(caller != GUARDIAN_RECOVERY_ADDRESS);

        // Call: initiate recovery guardian update, finalize recovery guardian update, then cancel recovery guardian
        // update as `caller`, expecting revert from the recovery-address gate.
        _expectOnlyGuardianRecoveryAddressRevert(caller, GUARDIAN_RECOVERY_ADDRESS);
        vm.prank(caller);
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN_A);

        _expectOnlyGuardianRecoveryAddressRevert(caller, GUARDIAN_RECOVERY_ADDRESS);
        vm.prank(caller);
        harness.finalizeRecoveryGuardianUpdate();

        _expectOnlyGuardianRecoveryAddressRevert(caller, GUARDIAN_RECOVERY_ADDRESS);
        vm.prank(caller);
        harness.cancelRecoveryGuardianUpdate();

        // Verify: pending guardian remains unchanged; pending guardian timestamp remains unchanged.
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
