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

    /// @dev Verifies that malformed encoded constraints revert.
    function test_areParametersAllowedByConstraints_malformedEncodedConstraints_reverts() public {
        // Setup: craft malformed constraints that bypass the short-length guard but contain invalid ABI offsets.
        bytes memory malformedConstraints = abi.encode(uint256(32), uint256(2));
        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(1));

        // Verify: malformed ABI should revert in the current implementation.
        vm.expectRevert();
        // Call: execute `areParametersAllowedByConstraintsViaPolicyLibrary` with malformed constraints.
        harness.areParametersAllowedByConstraintsViaPolicyLibrary(malformedConstraints, data);
    }

    /// @dev Verifies that malformed constraints payloads never produce an allow decision.
    function test_areParametersAllowedByConstraints_malformedButLengthGte64_neverReturnsTrue() public {
        // Setup: craft a payload that bypasses the `< 64` pre-check but declares
        // `length=2` without providing any element data.
        bytes memory malformedConstraints = abi.encode(uint256(32), uint256(2));
        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(5));
        bytes memory callData =
            abi.encodeCall(harness.areParametersAllowedByConstraintsViaPolicyLibrary, (malformedConstraints, data));

        // Call: invoke via low-level call so the test accepts either fail-closed `false`
        // or a decode revert for malformed ABI payloads.
        (bool success, bytes memory returnData) = address(harness).call(callData);

        // Verify: malformed payloads must not resolve to `true`.
        if (success) {
            bool allowed = abi.decode(returnData, (bool));
            assertFalse(allowed, "malformed constraints should not allow");
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

    /// @dev Verifies that Any constraints ignore malformed comparison bytes and still pass.
    function test_areParametersAllowedByConstraints_anyConstraint_ignoresMalformedComparisonData() public view {
        // Setup: use an Any constraint with intentionally malformed comparisonData to
        // verify the dispatcher short-circuits before type-specific decoding.
        ParameterConstraint memory anyConstraint = ParameterConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Any,
            paramCalldataHeadSlotCount: 1,
            comparisonData: hex"0102",
            paramValueInListProof: _emptyProof()
        });
        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(123));

        // Call: evaluate the malformed Any constraint payload.
        bool allowed =
            harness.areParametersAllowedByConstraintsViaPolicyLibrary(_encodeSingleConstraint(anyConstraint), data);

        // Verify: Any constraints should allow regardless of comparisonData contents.
        assertTrue(allowed, "Any constraint should not decode comparisonData");
    }

    /// @dev Verifies that valid constraints remain valid even with extra trailing bytes in the payload.
    function test_areParametersAllowedByConstraints_validConstraintsWithTrailingBytes_returnsTrue() public view {
        // Setup: build a valid encoded constraints blob and append trailing bytes to ensure
        // decoder behavior stays deterministic for canonical prefix-encoded data.
        ParameterConstraint memory constraint = ParameterConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(uint256(77)),
            paramValueInListProof: _emptyProof()
        });
        bytes memory encodedConstraints = bytes.concat(_encodeSingleConstraint(constraint), hex"DEADBEEF");
        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(77));

        // Call: evaluate with trailing bytes after the canonical ABI payload.
        bool allowed = harness.areParametersAllowedByConstraintsViaPolicyLibrary(encodedConstraints, data);

        // Verify: the valid canonical constraints payload should still authorize.
        assertTrue(allowed, "trailing bytes should not change canonical decode result");
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
