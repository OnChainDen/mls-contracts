// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibOrganizationGuardianHarness
} from "test/organization/libraries/LibOrganizationGuardian/LibOrganizationGuardianHarness.sol";
import {
    LibOrganizationGuardianInvariantHandler
} from "test/organization/libraries/LibOrganizationGuardian/LibOrganizationGuardianInvariantHandler.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";
import {OrganizationAdminTestBase} from "test/organization/shared/OrganizationAdminTestBase.sol";
import {OrganizationGuardianStateHarness} from "test/organization/shared/OrganizationGuardianStateHarness.sol";

/**
 * @dev Stateful invariant tests for `LibOrganizationGuardian`.
 */
contract LibOrganizationGuardianInvariants is OrganizationAdminTestBase {
    /// @dev Timelock used for normal guardian update flow in invariants.
    uint256 internal constant ADMIN_OPERATION_TIMELOCK = 2 days;

    /// @dev Harness under invariant testing.
    LibOrganizationGuardianHarness internal harness;

    /// @dev Stateful mutation handler.
    LibOrganizationGuardianInvariantHandler internal handler;

    /// @dev Typed shared-state surface used for fixture seeding.
    OrganizationGuardianStateHarness internal guardianStateHarness;

    /**
     * @dev Deploys the library-focused harness for this suite.
     */
    function _deployHarness() internal override returns (OrganizationAdminStateHarness) {
        harness = new LibOrganizationGuardianHarness();
        return OrganizationAdminStateHarness(address(harness));
    }

    /**
     * @dev Seeds timelock config, deploys handler, and registers it as fuzz target.
     */
    function setUp() public override {
        super.setUp();
        guardianStateHarness = OrganizationGuardianStateHarness(address(harness));
        guardianStateHarness.setAdminOperationTimelockDurationSeconds(ADMIN_OPERATION_TIMELOCK);
        handler = new LibOrganizationGuardianInvariantHandler(harness);
        targetContract(address(handler));
    }

    /// @dev Verifies the configured guardian is never the zero address after initialization.
    function invariant_guardianAlwaysSet_afterInitialization() public view {
        // Setup
        // Call
        address currentGuardian = harness.getGuardianViaLibrary();

        // Verify
        assertTrue(currentGuardian != address(0), "guardian must never become zero");
    }

    /// @dev Verifies normal guardian flow never stages more than one pending update at a time.
    function invariant_pendingExclusivity_atMostOnePendingUpdate() public {
        // Setup
        address pendingGuardian = harness.getPendingGuardianViaLibrary();

        // Call
        if (pendingGuardian != address(0)) {
            (bool success,) =
                address(harness).call(abi.encodeCall(harness.initiateGuardianUpdateViaLibrary, (address(0xF001))));

            // Verify
            assertFalse(success, "second initiate should fail while one update is already pending");
            assertEq(harness.getPendingGuardianViaLibrary(), pendingGuardian, "existing pending guardian should remain");
        }
    }

    /// @dev Verifies accept cannot succeed before finalize and timelock-ready preconditions are met.
    function invariant_timelockEnforcement_guardianCannotChangeOutsideAccept() public view {
        // Setup
        // Call
        bool outsideAcceptViolation = handler.guardianChangedOutsideAcceptViolation();
        bool invalidAcceptPreconditionViolation = handler.acceptWithoutFinalizeOrTimelockViolation();

        // Verify
        assertFalse(outsideAcceptViolation, "guardian changed in non-accept normal-flow operation");
        assertFalse(
            invalidAcceptPreconditionViolation, "accept succeeded without finalize/timelock-ready preconditions"
        );
    }

    /// @dev Verifies clearing the pending guardian also clears its timestamp and readiness flag.
    function invariant_stateConsistency_noPendingImpliesClearedTimestampAndReadyFlag() public view {
        // Setup
        address pendingGuardian = harness.getPendingGuardianViaLibrary();
        uint256 pendingTimestamp = harness.getPendingGuardianUpdateTimestampViaLibrary();
        bool isReady = harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary();

        // Call
        if (pendingGuardian == address(0)) {
            // Verify
            assertEq(pendingTimestamp, 0, "timestamp must be zero when pending guardian is zero");
            assertFalse(isReady, "ready flag must be false when pending guardian is zero");
        }
    }

    /// @dev Verifies successful acceptance clears every staged normal-flow guardian update field.
    function invariant_acceptClearsAll_pendingStateResetAfterAccept() public view {
        // Setup
        // Call
        bool violation = handler.acceptDidNotClearPendingStateViolation();

        // Verify
        assertFalse(violation, "successful accept did not clear pending guardian state");
    }

    /// @dev Verifies guardian mutation only occurs through the normal-flow accept path.
    function invariant_guardianMutationPoint_onlyAcceptMutatesGuardian() public view {
        // Setup
        // Call
        bool violation = handler.guardianChangedOutsideAcceptViolation();

        // Verify
        assertFalse(violation, "guardian mutated outside normal-flow accept path");
    }

    /// @dev Verifies ready state implies pending guardian and pending timestamp are both set.
    function invariant_readyStateCoherence_readyImpliesPendingGuardianAndTimestamp() public view {
        // Setup
        bool isReady = harness.getIsGuardianUpdateReadyForAcceptanceViaLibrary();
        address pendingGuardian = harness.getPendingGuardianViaLibrary();
        uint256 pendingTimestamp = harness.getPendingGuardianUpdateTimestampViaLibrary();

        // Call
        if (isReady) {
            // Verify
            assertTrue(pendingGuardian != address(0), "ready=true requires pending guardian");
            assertTrue(pendingTimestamp != 0, "ready=true requires pending timestamp");
        }
    }

    /// @dev Verifies a pending guardian implies a non-zero pending timestamp.
    function invariant_pendingTimestampCoherence_pendingGuardianImpliesTimestamp() public view {
        // Setup
        address pendingGuardian = harness.getPendingGuardianViaLibrary();
        uint256 pendingTimestamp = harness.getPendingGuardianUpdateTimestampViaLibrary();

        // Call
        if (pendingGuardian != address(0)) {
            // Verify
            assertTrue(pendingTimestamp != 0, "pending guardian requires non-zero pending timestamp");
        }
    }
}
