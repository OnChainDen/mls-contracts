// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibPolicyParameterConstraintsSuiteBase
} from "test/organization/libraries/policy/LibPolicyParameterConstraints/LibPolicyParameterConstraintsSuiteBase.sol";
import {ConstraintType, ParamType, ParameterConstraint} from "types/PolicyTypes.sol";

/**
 * @dev Section 8.1 tests for `areParametersAllowedByConstraints`.
 */
contract LibPolicyParameterConstraintsAreParametersAllowedByConstraintsTest is LibPolicyParameterConstraintsSuiteBase {
    /// @dev Verifies that empty `parameterConstraints` bytes returns true.
    function test_areParametersAllowedByConstraints_emptyConstraintsBytes_returnsTrue() public view {
        // Setup: configure a valid fixture for empty `parameterConstraints` bytes returns true.
        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(7));

        // Call: execute `areParametersAllowedByConstraintsViaPolicyLibrary` with the happy-path payload.
        bool allowed = harness.areParametersAllowedByConstraintsViaPolicyLibrary(bytes(""), data);

        // Verify: assert the expected success result and state updates.
        assertTrue(allowed, "empty constraints bytes should allow by default");
    }

    /// @dev Verifies that ABI-encoded empty constraints array returns true.
    function test_areParametersAllowedByConstraints_abiEncodedEmptyArray_returnsTrue() public view {
        // Setup: configure a valid fixture for ABI-encoded empty constraints array returns true.
        ParameterConstraint[] memory constraints = new ParameterConstraint[](0);
        bytes memory encodedConstraints = abi.encode(constraints);
        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(7));

        // Call: execute `areParametersAllowedByConstraintsViaPolicyLibrary` with the happy-path payload.
        bool allowed = harness.areParametersAllowedByConstraintsViaPolicyLibrary(encodedConstraints, data);

        // Verify: assert the expected success result and state updates.
        assertTrue(allowed, "empty decoded constraints array should allow by default");
    }

    /// @dev Verifies that a single valid constraint returns true.
    function test_areParametersAllowedByConstraints_singleValidConstraint_returnsTrue() public view {
        // Setup: configure a valid fixture for a single valid constraint returns true.
        ParameterConstraint memory constraint = ParameterConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(uint256(42)),
            paramValueInListProof: _emptyProof()
        });

        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(42));

        // Call: execute `areParametersAllowedByConstraintsViaPolicyLibrary` with the happy-path payload.
        bool allowed =
            harness.areParametersAllowedByConstraintsViaPolicyLibrary(_encodeSingleConstraint(constraint), data);

        // Verify: assert the expected success result and state updates.
        assertTrue(allowed, "matching uint exact constraint should pass");
    }

    /// @dev Verifies that multiple passing constraints return true.
    function test_areParametersAllowedByConstraints_multiplePassingConstraints_returnsTrue() public view {
        // Setup: configure a valid fixture for multiple passing constraints return true.
        ParameterConstraint memory uintConstraint = ParameterConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(uint256(11)),
            paramValueInListProof: _emptyProof()
        });
        ParameterConstraint memory addressConstraint = ParameterConstraint({
            paramType: ParamType.Address,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(reviewer1),
            paramValueInListProof: _emptyProof()
        });
        ParameterConstraint memory boolConstraint = ParameterConstraint({
            paramType: ParamType.Bool,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(true),
            paramValueInListProof: _emptyProof()
        });

        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(11), reviewer1, true);

        // Call: execute `areParametersAllowedByConstraintsViaPolicyLibrary` with the happy-path payload.
        bool allowed = harness.areParametersAllowedByConstraintsViaPolicyLibrary(
            abi.encode(_constraints(uintConstraint, addressConstraint, boolConstraint)), data
        );

        // Verify: assert the expected success result and state updates.
        assertTrue(allowed, "all constraints passing should return true");
    }

    /// @dev Verifies that any failing constraint causes false.
    function test_areParametersAllowedByConstraints_anyFailingConstraint_returnsFalse() public view {
        // Setup: build fixture inputs where any failing constraint causes false should be denied.
        ParameterConstraint memory passingConstraint = ParameterConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(uint256(11)),
            paramValueInListProof: _emptyProof()
        });
        ParameterConstraint memory failingConstraint = ParameterConstraint({
            paramType: ParamType.Address,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(reviewer2),
            paramValueInListProof: _emptyProof()
        });

        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(11), reviewer1);

        // Call: execute `areParametersAllowedByConstraintsViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.areParametersAllowedByConstraintsViaPolicyLibrary(
            abi.encode(_constraints(passingConstraint, failingConstraint)), data
        );

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "one failing constraint should cause false");
    }

    /// @dev Verifies that malformed encoded constraints fail closed with false.
    function test_areParametersAllowedByConstraints_malformedEncodedConstraints_failClosedDesiredBehavior() public {
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for malformed encoded constraints
        // fail closed with false.
        bytes memory malformedConstraints = hex"0001";
        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(1));

        // Call: run `areParametersAllowedByConstraintsViaPolicyLibrary` across the prepared variants.
        try harness.areParametersAllowedByConstraintsViaPolicyLibrary(malformedConstraints, data) returns (
            bool allowed
        ) {
            // Verify: assert each variant returns the expected branch outcome.
            assertFalse(allowed, "malformed constraints should fail closed with false");
        } catch {
            assertTrue(false, "malformed constraints should fail closed with false instead of reverting");
        }
    }

    /// @dev Verifies that malformed comparisonData in a constraint fails closed with false.
    function test_areParametersAllowedByConstraints_malformedComparisonData_failClosedDesiredBehavior() public {
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for malformed comparisonData in a
        // constraint fails closed with false.
        ParameterConstraint memory malformedConstraint = ParameterConstraint({
            paramType: ParamType.Bool,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: hex"01",
            paramValueInListProof: _emptyProof()
        });

        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, true);

        // Call: run `areParametersAllowedByConstraintsViaPolicyLibrary` across the prepared variants.
        try harness.areParametersAllowedByConstraintsViaPolicyLibrary(
            _encodeSingleConstraint(malformedConstraint), data
        ) returns (
            bool allowed
        ) {
            // Verify: assert each variant returns the expected branch outcome.
            assertFalse(allowed, "malformed comparisonData should fail closed with false");
        } catch {
            assertTrue(false, "malformed comparisonData should fail closed with false instead of reverting");
        }
    }

    /// @dev Verifies that identical inputs produce deterministic output.
    function test_areParametersAllowedByConstraints_deterministicForSameInputs() public view {
        // Setup: configure a valid fixture for identical inputs produce deterministic output.
        ParameterConstraint memory constraint = ParameterConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Range,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(uint256(10), uint256(20)),
            paramValueInListProof: _emptyProof()
        });

        bytes memory encodedConstraints = _encodeSingleConstraint(constraint);
        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(12));

        // Call: execute `areParametersAllowedByConstraintsViaPolicyLibrary` with the happy-path payload.
        bool first = harness.areParametersAllowedByConstraintsViaPolicyLibrary(encodedConstraints, data);
        bool second = harness.areParametersAllowedByConstraintsViaPolicyLibrary(encodedConstraints, data);

        // Verify: assert the expected success result and state updates.
        assertEq(first, second, "same inputs must produce same result");
    }
}
