// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibPolicyParameterConstraintsSuiteBase
} from "test/organization/libraries/policy/LibPolicyParameterConstraints/LibPolicyParameterConstraintsSuiteBase.sol";
import {ConstraintType, ParamType, ParameterConstraint} from "types/PolicyTypes.sol";

/**
 * @dev Section 8.8 tests for `_isFixedBytesParameterAllowedByConstraint`.
 */
contract LibPolicyParameterConstraintsFixedBytesConstraintTest is LibPolicyParameterConstraintsSuiteBase {
    /// @dev Verifies that exact bytes32 match passes and mismatch fails.
    function test_isFixedBytesParameterAllowedByConstraint_exactMatchAndMismatch() public view {
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for exact bytes32 match passes and
        // mismatch fails.
        bytes32 expected = keccak256("fixed-bytes");

        // Call: run `isFixedBytesParameterAllowedByConstraintViaPolicyLibrary` across the prepared variants.
        bool matchAllowed = harness.isFixedBytesParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(expected), expected
        );
        bool mismatchAllowed = harness.isFixedBytesParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(expected), bytes32(uint256(expected) + 1)
        );

        // Verify: assert each variant returns the expected branch outcome.
        assertTrue(matchAllowed, "matching bytes32 should pass");
        assertFalse(mismatchAllowed, "mismatching bytes32 should fail");
    }

    /// @dev Verifies that bytes1..bytes31 comparisons use ABI left-aligned semantics.
    function test_isFixedBytesParameterAllowedByConstraint_leftAlignedSemanticsForShorterFixedBytes() public view {
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for bytes1..bytes31 comparisons use
        // ABI left-aligned semantics.
        bytes4 value = 0x11223344;
        bytes32 leftAligned = bytes32(value);
        bytes32 rightAligned = bytes32(uint256(uint32(value)));

        // Call: run `isFixedBytesParameterAllowedByConstraintViaPolicyLibrary` across the prepared variants.
        bool leftAlignedAllowed = harness.isFixedBytesParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(leftAligned), leftAligned
        );
        bool rightAlignedAllowed = harness.isFixedBytesParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(leftAligned), rightAligned
        );

        // Verify: assert each variant returns the expected branch outcome.
        assertTrue(leftAlignedAllowed, "left-aligned ABI representation should match");
        assertFalse(rightAlignedAllowed, "right-aligned representation should not match");
    }

    /// @dev Verifies that non-Exact constraints return false.
    function test_isFixedBytesParameterAllowedByConstraint_nonExactConstraint_returnsFalse() public view {
        // Setup: build fixture inputs where non-Exact constraints return false should be denied.
        // Call: execute `isFixedBytesParameterAllowedByConstraintViaPolicyLibrary` and capture the authorization
        // decision.
        bool allowed = harness.isFixedBytesParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, abi.encode(bytes32(uint256(1))), bytes32(uint256(1))
        );

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "fixed bytes supports only Exact");
    }

    /// @dev Verifies that malformed comparisonData fails closed with false.
    function test_isFixedBytesParameterAllowedByConstraint_malformedComparisonData_failClosedDesiredBehavior() public {
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for malformed comparisonData fails
        // closed with false. Call: run `isFixedBytesParameterAllowedByConstraintViaPolicyLibrary` across the prepared
        // variants.
        try harness.isFixedBytesParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, hex"01", bytes32(uint256(1))
        ) returns (
            bool allowed
        ) {
            // Verify: assert each variant returns the expected branch outcome.
            assertFalse(allowed, "malformed fixed-bytes comparisonData should fail closed with false");
        } catch {
            assertTrue(false, "malformed fixed-bytes comparisonData should fail closed with false instead of reverting");
        }
    }
}
