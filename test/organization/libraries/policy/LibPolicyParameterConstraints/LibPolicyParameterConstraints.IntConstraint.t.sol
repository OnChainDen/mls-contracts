// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibPolicyParameterConstraintsSuiteBase
} from "test/organization/libraries/policy/LibPolicyParameterConstraints/LibPolicyParameterConstraintsSuiteBase.sol";
import {ConstraintType, ParamType, ParameterConstraint} from "types/PolicyTypes.sol";

/**
 * @dev Section 8.6 tests for `_isIntParameterAllowedByConstraint`.
 */
contract LibPolicyParameterConstraintsIntConstraintTest is LibPolicyParameterConstraintsSuiteBase {
    /// @dev Verifies that exact matches for positive and negative values pass.
    function test_isIntParameterAllowedByConstraint_exactPositiveAndNegativeMatch_returnsTrue() public view {
        // Setup: configure a valid fixture for exact matches for positive and negative values pass.
        // Call: execute `isIntParameterAllowedByConstraintViaPolicyLibrary` with the happy-path payload.
        bool positiveAllowed = harness.isIntParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(int256(7)), bytes32(uint256(7))
        );
        bool negativeAllowed = harness.isIntParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(int256(-7)), bytes32(uint256(int256(-7)))
        );

        // Verify: assert the expected success result and state updates.
        assertTrue(positiveAllowed, "positive exact match should pass");
        assertTrue(negativeAllowed, "negative exact match should pass");
    }

    /// @dev Verifies that exact mismatch fails.
    function test_isIntParameterAllowedByConstraint_exactMismatch_returnsFalse() public view {
        // Setup: build fixture inputs where exact mismatch fails should be denied.
        // Call: execute `isIntParameterAllowedByConstraintViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.isIntParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(int256(-3)), bytes32(uint256(int256(-2)))
        );

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "signed exact mismatch should fail");
    }

    /// @dev Verifies that signed ranges are inclusive across negative/positive windows.
    function test_isIntParameterAllowedByConstraint_rangeInclusiveAcrossSignedWindow() public view {
        // Setup: configure a valid fixture for signed ranges are inclusive across negative/positive windows.
        bytes memory rangeData = abi.encode(int256(-5), int256(5));

        // Call: execute `isIntParameterAllowedByConstraintViaPolicyLibrary` with the happy-path payload.
        bool minAllowed = harness.isIntParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, rangeData, bytes32(uint256(int256(-5)))
        );
        bool maxAllowed = harness.isIntParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, rangeData, bytes32(uint256(int256(5)))
        );

        // Verify: assert the expected success result and state updates.
        assertTrue(minAllowed, "signed min bound should be inclusive");
        assertTrue(maxAllowed, "signed max bound should be inclusive");
    }

    /// @dev Verifies that out-of-range signed values fail.
    function test_isIntParameterAllowedByConstraint_outOfRange_returnsFalse() public view {
        // Setup: build fixture inputs where out-of-range signed values fail should be denied.
        bytes memory rangeData = abi.encode(int256(-5), int256(5));

        // Call: execute `isIntParameterAllowedByConstraintViaPolicyLibrary` and capture the authorization decision.
        bool belowAllowed = harness.isIntParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, rangeData, bytes32(uint256(int256(-6)))
        );
        bool aboveAllowed = harness.isIntParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, rangeData, bytes32(uint256(int256(6)))
        );

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(belowAllowed, "signed value below min should fail");
        assertFalse(aboveAllowed, "signed value above max should fail");
    }

    /// @dev Verifies that min>max signed range fails closed.
    function test_isIntParameterAllowedByConstraint_rangeMinGreaterThanMax_returnsFalse() public view {
        // Setup: build fixture inputs where min>max signed range fails closed should be denied.
        // Call: execute `isIntParameterAllowedByConstraintViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.isIntParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, abi.encode(int256(5), int256(-5)), bytes32(uint256(int256(0)))
        );

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "signed range min>max should fail closed");
    }

    /// @dev Verifies that unsupported OneOf for int returns false.
    function test_isIntParameterAllowedByConstraint_oneOfUnsupported_returnsFalse() public view {
        // Setup: build fixture inputs where unsupported OneOf for int returns false should be denied.
        // Call: execute `isIntParameterAllowedByConstraintViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.isIntParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.OneOf, abi.encode(bytes32(uint256(1))), bytes32(uint256(int256(1)))
        );

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "int does not support OneOf");
    }

    /// @dev Verifies that malformed comparisonData fails closed with false.
    function test_isIntParameterAllowedByConstraint_malformedComparisonData_failClosedDesiredBehavior() public {
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for malformed comparisonData fails
        // closed with false. Call: run `isIntParameterAllowedByConstraintViaPolicyLibrary` across the prepared
        // variants.
        try harness.isIntParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, hex"01", bytes32(uint256(int256(1)))
        ) returns (
            bool allowed
        ) {
            // Verify: assert each variant returns the expected branch outcome.
            assertFalse(allowed, "malformed int comparisonData should fail closed with false");
        } catch {
            assertTrue(false, "malformed int comparisonData should fail closed with false instead of reverting");
        }
    }
}
