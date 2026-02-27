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
    function test_isUintParameterAllowedByConstraint_rangeInclusiveAtBounds() public view {
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

    /// @dev Verifies that malformed comparisonData fails closed with false.
    function test_isUintParameterAllowedByConstraint_malformedComparisonData_failClosedDesiredBehavior() public {
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
