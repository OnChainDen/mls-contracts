// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibOrganizationGuardianRecoveryHarness
} from "test/organization/libraries/LibOrganizationGuardianRecovery/LibOrganizationGuardianRecoveryHarness.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";
import {OrganizationAdminTestBase} from "test/organization/shared/OrganizationAdminTestBase.sol";
import {
    OrganizationGuardianRecoveryStateHarness
} from "test/organization/shared/OrganizationGuardianRecoveryStateHarness.sol";
import {GuardianRecoveryState, PendingRecoveryInitTimelock, TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Shared deployment/setup helpers for `LibOrganizationGuardianRecovery` suites.
 */
abstract contract LibOrganizationGuardianRecoverySuiteBase is OrganizationAdminTestBase {
    /// @dev Timelock used by deferred-init admin operations.
    uint256 internal constant ADMIN_OPERATION_TIMELOCK = 3 days;

    /// @dev Timelock used by guardian-recovery update flow.
    uint256 internal constant GUARDIAN_RECOVERY_TIMELOCK = 2 days;

    /// @dev Deterministic guardian-recovery admin fixtures.
    address internal constant GUARDIAN_RECOVERY_ADDRESS = address(0xC021);
    address internal constant GUARDIAN_RECOVERY_ADDRESS_B = address(0xC022);

    /// @dev Deterministic candidate guardians for recovery updates.
    address internal constant NEW_GUARDIAN_A = address(0xC101);
    address internal constant NEW_GUARDIAN_B = address(0xC102);
    address internal constant NEW_GUARDIAN_C = address(0xC103);

    /// @dev Concrete harness used by all library-focused section suites.
    LibOrganizationGuardianRecoveryHarness internal harness;

    /// @dev Typed shared-state surface for guardian/recovery storage helpers.
    OrganizationGuardianRecoveryStateHarness internal recoveryStateHarness;

    /**
     * @dev Deploys the library-focused harness for section suites.
     */
    function _deployHarness() internal override returns (OrganizationAdminStateHarness) {
        harness = new LibOrganizationGuardianRecoveryHarness();
        return OrganizationAdminStateHarness(address(harness));
    }

    /**
     * @dev Seeds baseline admin timelock and configured guardian-recovery setup.
     */
    function setUp() public virtual override {
        super.setUp();
        recoveryStateHarness = OrganizationGuardianRecoveryStateHarness(address(harness));
        recoveryStateHarness.setAdminOperationTimelockDurationSeconds(ADMIN_OPERATION_TIMELOCK);
        harness.initializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);
    }

    /**
     * @dev Resets and reconfigures guardian-recovery state to configured baseline.
     */
    function _resetAndConfigureRecovery() internal {
        harness.resetGuardianRecoveryStorageViaHarness();
        harness.initializeGuardianRecoveryViaLibrary(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);
    }

    /**
     * @dev Seeds tx-recovery storage with non-zero values for isolation checks.
     */
    function _seedNonZeroTxRecoveryState() internal {
        TxRecoveryState memory txState = TxRecoveryState({
            recoveryAddress: address(0xD301),
            isEnabled: true,
            timelockDurationSeconds: 4 days,
            pendingEnableTimestamp: block.timestamp + 9 days,
            pendingInit: PendingRecoveryInitTimelock({
                pendingRecoveryAddress: address(0xD302),
                pendingTimelockDurationSeconds: 5 days,
                pendingTimestamp: block.timestamp + 10 days
            }),
            initAttemptId: 0
        });
        recoveryStateHarness.setTxRecoveryState(txState);
    }

    /**
     * @dev Reads guardian-recovery state and tx-recovery state snapshot.
     */
    function _snapshotStates() internal view returns (GuardianRecoveryState memory gr, TxRecoveryState memory txState) {
        gr = harness.getGuardianRecoveryStateViaStorage();
        txState = harness.getTxRecoveryStateViaStorage();
    }
}
