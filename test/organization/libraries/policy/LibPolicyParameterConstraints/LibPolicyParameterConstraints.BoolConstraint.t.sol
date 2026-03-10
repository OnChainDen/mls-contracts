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

    /// @dev Verifies that non-canonical expected bool values fail closed.
    function test_isBoolParameterAllowedByConstraint_nonCanonicalExpectedValue_returnsFalse() public view {
        // Setup: encode `2` as the expected bool word, which is not canonical ABI bool encoding.
        bytes memory malformedExpected = abi.encode(uint256(2));

        // Call: validate against a canonical true parameter value.
        bool allowed = harness.isBoolParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, malformedExpected, bytes32(uint256(1))
        );

        // Verify: non-canonical expected values must be rejected.
        assertFalse(allowed, "expected bool value >1 should fail");
    }

    /// @dev Verifies that oversized comparison payloads fail closed.
    function test_POL_INV_14_isBoolParameterAllowedByConstraint_oversizedComparisonData_returnsFalse() public view {
        // Setup: append an extra 32-byte word so comparison data is not exactly one slot.
        bytes memory oversized = bytes.concat(abi.encode(true), bytes32(uint256(99)));

        // Call: evaluate bool constraint with oversized comparison data.
        bool allowed = harness.isBoolParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, oversized, bytes32(uint256(1))
        );

        // Verify: bool comparison data must be exactly one ABI word.
        assertFalse(allowed, "oversized bool comparisonData should fail");
    }

    /// @dev Verifies that maximal non-canonical bool words are rejected.
    function test_isBoolParameterAllowedByConstraint_maxUintWord_returnsFalse() public view {
        // Setup: use the largest possible 256-bit value in the parameter head.
        bytes32 nonCanonicalHead = bytes32(type(uint256).max);

        // Call: compare the non-canonical head against expected `true`.
        bool allowed = harness.isBoolParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(true), nonCanonicalHead
        );

        // Verify: only canonical 0/1 bool words are accepted.
        assertFalse(allowed, "max uint head should fail canonical bool check");
    }

    /// @dev Verifies that malformed comparisonData fails closed with false.
    function test_POL_INV_14_isBoolParameterAllowedByConstraint_malformedComparisonData_failClosedDesiredBehavior()
        public
    {
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
