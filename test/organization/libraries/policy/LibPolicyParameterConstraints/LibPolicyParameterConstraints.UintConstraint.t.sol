// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibPolicyParameterConstraintsSuiteBase
} from "test/organization/libraries/policy/LibPolicyParameterConstraints/LibPolicyParameterConstraintsSuiteBase.sol";
import {ConstraintType, ParamType, ParameterConstraint} from "types/PolicyTypes.sol";

/**
 * @dev Section 8.5 tests for `_isUintParameterAllowedByConstraint`.
 */
contract LibPolicyParameterConstraintsUintConstraintTest is LibPolicyParameterConstraintsSuiteBase {
    /// @dev Verifies that exact match passes and exact mismatch fails.
    function test_isUintParameterAllowedByConstraint_exactMatchAndMismatch() public view {
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for exact match passes and exact
        // mismatch fails. Call: run `isUintParameterAllowedByConstraintViaPolicyLibrary` across the prepared variants.
        bool matchAllowed = harness.isUintParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(uint256(50)), bytes32(uint256(50))
        );
        bool mismatchAllowed = harness.isUintParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(uint256(49)), bytes32(uint256(50))
        );

        // Verify: assert each variant returns the expected branch outcome.
        assertTrue(matchAllowed, "matching uint exact should pass");
        assertFalse(mismatchAllowed, "mismatched uint exact should fail");
    }

    /// @dev Verifies that range bounds are inclusive.
    function test_LPPC_ATYPE_9_isUintParameterAllowedByConstraint_rangeInclusiveAtBounds() public view {
        // Setup: configure a valid fixture for range bounds are inclusive.
        bytes memory rangeData = abi.encode(uint256(10), uint256(20));

        // Call: execute `isUintParameterAllowedByConstraintViaPolicyLibrary` with the happy-path payload.
        bool minAllowed = harness.isUintParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, rangeData, bytes32(uint256(10))
        );
        bool maxAllowed = harness.isUintParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, rangeData, bytes32(uint256(20))
        );

        // Verify: assert the expected success result and state updates.
        assertTrue(minAllowed, "range min bound should be inclusive");
        assertTrue(maxAllowed, "range max bound should be inclusive");
    }

    /// @dev Verifies that out-of-range values fail.
    function test_isUintParameterAllowedByConstraint_outOfRange_returnsFalse() public view {
        // Setup: build fixture inputs where out-of-range values fail should be denied.
        bytes memory rangeData = abi.encode(uint256(10), uint256(20));

        // Call: execute `isUintParameterAllowedByConstraintViaPolicyLibrary` and capture the authorization decision.
        bool belowAllowed = harness.isUintParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, rangeData, bytes32(uint256(9))
        );
        bool aboveAllowed = harness.isUintParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, rangeData, bytes32(uint256(21))
        );

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(belowAllowed, "below-range value should fail");
        assertFalse(aboveAllowed, "above-range value should fail");
    }

    /// @dev Verifies that min>max range fails closed with false.
    function test_isUintParameterAllowedByConstraint_rangeMinGreaterThanMax_returnsFalse() public view {
        // Setup: build fixture inputs where min>max range fails closed with false should be denied.
        // Call: execute `isUintParameterAllowedByConstraintViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.isUintParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, abi.encode(uint256(20), uint256(10)), bytes32(uint256(15))
        );

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "range min>max should fail closed");
    }

    /// @dev Verifies that unsupported OneOf returns false.
    function test_isUintParameterAllowedByConstraint_oneOfUnsupported_returnsFalse() public view {
        // Setup: build fixture inputs where unsupported OneOf returns false should be denied.
        // Call: execute `isUintParameterAllowedByConstraintViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.isUintParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.OneOf, abi.encode(bytes32(uint256(1))), bytes32(uint256(1))
        );

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "uint does not support OneOf");
    }

    /// @dev Verifies that Any is unsupported for uint-specific validator and returns false.
    function test_isUintParameterAllowedByConstraint_anyUnsupported_returnsFalse() public view {
        // Setup: use Any against uint-specific validator, which supports only Exact and Range.

        // Call: evaluate uint validator with Any constraint type.
        bool allowed = harness.isUintParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Any, bytes(""), bytes32(uint256(12))
        );

        // Verify: uint validator must reject unsupported Any constraint type.
        assertFalse(allowed, "uint Any should fail");
    }

    /// @dev Verifies that malformed range payload lengths fail closed.
    function test_POL_INV_14_isUintParameterAllowedByConstraint_malformedRangeComparisonData_returnsFalse()
        public
        view
    {
        // Setup: provide short and oversized payloads for Range decoding.
        bytes memory shortRangeData = abi.encode(uint256(10));
        bytes memory oversizedRangeData = bytes.concat(abi.encode(uint256(10), uint256(20)), bytes32(uint256(30)));

        // Call: evaluate Range constraints with malformed payload lengths.
        bool shortAllowed = harness.isUintParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, shortRangeData, bytes32(uint256(15))
        );
        bool oversizedAllowed = harness.isUintParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, oversizedRangeData, bytes32(uint256(15))
        );

        // Verify: range payloads must be exactly two ABI words.
        assertFalse(shortAllowed, "short uint range payload should fail");
        assertFalse(oversizedAllowed, "oversized uint range payload should fail");
    }

    /// @dev Verifies that a single-point range (min==max) behaves as an equality constraint.
    function test_isUintParameterAllowedByConstraint_rangeMinEqualsMax_boundaryBehavior() public view {
        // Setup: create a range where both bounds are the same value.
        bytes memory pointRange = abi.encode(uint256(7), uint256(7));

        // Call: evaluate matching and non-matching inputs against the single-point range.
        bool exactPointAllowed = harness.isUintParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, pointRange, bytes32(uint256(7))
        );
        bool offPointAllowed = harness.isUintParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, pointRange, bytes32(uint256(6))
        );

        // Verify: only the exact boundary value should pass.
        assertTrue(exactPointAllowed, "min==max range should allow exact boundary");
        assertFalse(offPointAllowed, "min==max range should reject other values");
    }

    /// @dev Verifies that uint max-value boundaries are handled correctly.
    function test_isUintParameterAllowedByConstraint_uintMax_boundaryBehavior() public view {
        // Setup: use the maximum uint256 as both expected exact value and range boundary.
        uint256 maxValue = type(uint256).max;
        bytes memory maxRange = abi.encode(maxValue, maxValue);

        // Call: evaluate exact and range checks at the maximum uint value.
        bool exactAllowed = harness.isUintParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(maxValue), bytes32(maxValue)
        );
        bool rangeAllowed = harness.isUintParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, maxRange, bytes32(maxValue)
        );

        // Verify: max value should pass both exact and point-range checks.
        assertTrue(exactAllowed, "uint max exact should pass");
        assertTrue(rangeAllowed, "uint max point range should pass");
    }

    /// @dev Verifies that malformed comparisonData fails closed with false.
    function test_POL_INV_14_isUintParameterAllowedByConstraint_malformedComparisonData_failClosedDesiredBehavior()
        public
    {
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for malformed comparisonData fails
        // closed with false. Call: run `isUintParameterAllowedByConstraintViaPolicyLibrary` across the prepared
        // variants.
        try harness.isUintParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, hex"01", bytes32(uint256(1))
        ) returns (
            bool allowed
        ) {
            // Verify: assert each variant returns the expected branch outcome.
            assertFalse(allowed, "malformed uint comparisonData should fail closed with false");
        } catch {
            assertTrue(false, "malformed uint comparisonData should fail closed with false instead of reverting");
        }
    }
}
