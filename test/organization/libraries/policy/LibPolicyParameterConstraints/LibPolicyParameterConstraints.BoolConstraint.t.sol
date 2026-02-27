// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibPolicyParameterConstraintsSuiteBase
} from "test/organization/libraries/policy/LibPolicyParameterConstraints/LibPolicyParameterConstraintsSuiteBase.sol";
import {ConstraintType, ParamType, ParameterConstraint} from "types/PolicyTypes.sol";

/**
 * @dev Section 8.4 tests for `_isBoolParameterAllowedByConstraint`.
 */
contract LibPolicyParameterConstraintsBoolConstraintTest is LibPolicyParameterConstraintsSuiteBase {
    /// @dev Verifies that canonical true word with exact true passes.
    function test_isBoolParameterAllowedByConstraint_exactTrueCanonicalWord_returnsTrue() public view {
        // Setup: configure a valid fixture for canonical true word with exact true passes.
        // Call: execute `isBoolParameterAllowedByConstraintViaPolicyLibrary` with the happy-path payload.
        bool allowed = harness.isBoolParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(true), bytes32(uint256(1))
        );

        // Verify: assert the expected success result and state updates.
        assertTrue(allowed, "canonical bool true should pass");
    }

    /// @dev Verifies that canonical false word with exact false passes.
    function test_isBoolParameterAllowedByConstraint_exactFalseCanonicalWord_returnsTrue() public view {
        // Setup: configure a valid fixture for canonical false word with exact false passes.
        // Call: execute `isBoolParameterAllowedByConstraintViaPolicyLibrary` with the happy-path payload.
        bool allowed = harness.isBoolParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(false), bytes32(uint256(0))
        );

        // Verify: assert the expected success result and state updates.
        assertTrue(allowed, "canonical bool false should pass");
    }

    /// @dev Verifies that exact mismatch returns false.
    function test_isBoolParameterAllowedByConstraint_exactMismatch_returnsFalse() public view {
        // Setup: build fixture inputs where exact mismatch returns false should be denied.
        // Call: execute `isBoolParameterAllowedByConstraintViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.isBoolParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(false), bytes32(uint256(1))
        );

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "bool exact mismatch should fail");
    }

    /// @dev Verifies that non-Exact constraint types return false.
    function test_isBoolParameterAllowedByConstraint_nonExactConstraint_returnsFalse() public view {
        // Setup: build fixture inputs where non-Exact constraint types return false should be denied.
        // Call: execute `isBoolParameterAllowedByConstraintViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.isBoolParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, abi.encode(false), bytes32(uint256(1))
        );

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "bool supports only Exact");
    }

    /// @dev Verifies that non-canonical non-zero words fail closed.
    function test_isBoolParameterAllowedByConstraint_nonCanonicalNonZeroWord_failClosedDesiredBehavior() public view {
        // Setup: build fixture inputs where non-canonical non-zero words fail closed should be denied.
        // Call: execute `isBoolParameterAllowedByConstraintViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.isBoolParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(true), bytes32(uint256(2))
        );

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "non-canonical non-zero bool words should fail closed");
    }

    /// @dev Verifies that malformed comparisonData fails closed with false.
    function test_isBoolParameterAllowedByConstraint_malformedComparisonData_failClosedDesiredBehavior() public {
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for malformed comparisonData fails
        // closed with false. Call: run `isBoolParameterAllowedByConstraintViaPolicyLibrary` across the prepared
        // variants.
        try harness.isBoolParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, hex"01", bytes32(uint256(1))
        ) returns (
            bool allowed
        ) {
            // Verify: assert each variant returns the expected branch outcome.
            assertFalse(allowed, "malformed bool comparisonData should fail closed with false");
        } catch {
            assertTrue(false, "malformed bool comparisonData should fail closed with false instead of reverting");
        }
    }
}
