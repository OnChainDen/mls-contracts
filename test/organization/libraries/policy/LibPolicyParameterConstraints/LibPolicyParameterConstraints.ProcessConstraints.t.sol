// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibPolicyParameterConstraintsSuiteBase
} from "test/organization/libraries/policy/LibPolicyParameterConstraints/LibPolicyParameterConstraintsSuiteBase.sol";
import {ConstraintType, ParamType, ParameterConstraint} from "types/PolicyTypes.sol";

/**
 * @dev Section 8.2 tests for `_processConstraints`.
 */
contract LibPolicyParameterConstraintsProcessConstraintsTest is LibPolicyParameterConstraintsSuiteBase {
    /// @dev Verifies that processing an empty constraints array returns true.
    function test_processConstraints_emptyConstraintsArray_returnsTrue() public view {
        // Setup: provide calldata with a selector only and no constraints to evaluate.
        ParameterConstraint[] memory constraints = new ParameterConstraint[](0);
        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR);

        // Call: run the processing loop over an empty constraints list.
        bool allowed = harness.processConstraintsViaPolicyLibrary(constraints, data);

        // Verify: with no constraints, processing should trivially succeed.
        assertTrue(allowed, "empty constraints array should pass");
    }

    /// @dev Verifies that mixed head slot counts advance offsets correctly.
    function test_processConstraints_mixedHeadSlots_advancesOffsetsCorrectly() public view {
        // Setup: configure a valid fixture for mixed head slot counts advance offsets correctly.
        bytes32[2] memory staticArray = [bytes32(uint256(11)), bytes32(uint256(22))];

        ParameterConstraint memory uintConstraint = ParameterConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(uint256(77)),
            paramValueInListProof: _emptyProof()
        });
        ParameterConstraint memory arrayAnyConstraint = ParameterConstraint({
            paramType: ParamType.Array,
            constraintType: ConstraintType.Any,
            paramCalldataHeadSlotCount: 2,
            comparisonData: bytes(""),
            paramValueInListProof: _emptyProof()
        });
        ParameterConstraint memory addressConstraint = ParameterConstraint({
            paramType: ParamType.Address,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(reviewer1),
            paramValueInListProof: _emptyProof()
        });

        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(77), staticArray, reviewer1);

        // Call: execute `processConstraintsViaPolicyLibrary` with the happy-path payload.
        bool allowed = harness.processConstraintsViaPolicyLibrary(
            _constraints(uintConstraint, arrayAnyConstraint, addressConstraint), data
        );

        // Verify: assert the expected success result and state updates.
        assertTrue(allowed, "offset advancement across 1/2/1 head-slot params should validate correctly");
    }

    /// @dev Verifies that zero `paramCalldataHeadSlotCount` fails with false.
    function test_processConstraints_zeroHeadSlotCount_returnsFalse() public view {
        // Setup: build fixture inputs where zero `paramCalldataHeadSlotCount` fails with false should be denied.
        ParameterConstraint memory invalidConstraint = ParameterConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 0,
            comparisonData: abi.encode(uint256(1)),
            paramValueInListProof: _emptyProof()
        });

        // Call: execute `processConstraintsViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.processConstraintsViaPolicyLibrary(
            _constraints(invalidConstraint), abi.encodeWithSelector(BASE_SELECTOR, uint256(1))
        );

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "headSlotCount=0 should fail");
    }

    /// @dev Verifies that insufficient head bytes in calldata returns false.
    function test_processConstraints_dataShorterThanRequiredHead_returnsFalse() public view {
        // Setup: build fixture inputs where insufficient head bytes in calldata returns false should be denied.
        ParameterConstraint memory constraint = ParameterConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(uint256(1)),
            paramValueInListProof: _emptyProof()
        });

        bytes memory truncatedData = bytes.concat(BASE_SELECTOR, bytes16(uint128(1)));

        // Call: execute `processConstraintsViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.processConstraintsViaPolicyLibrary(_constraints(constraint), truncatedData);

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "truncated calldata head should fail");
    }

    /// @dev Verifies that exact-head-size calldata is accepted when all constraints fit exactly.
    function test_processConstraints_dataLengthExactlyRequiredHeadBytes_returnsTrue() public view {
        // Setup: encode exactly one 32-byte head slot after the selector.
        ParameterConstraint memory constraint = ParameterConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(uint256(1)),
            paramValueInListProof: _emptyProof()
        });
        bytes memory data = bytes.concat(BASE_SELECTOR, abi.encode(uint256(1)));

        // Call: evaluate a constraints list whose required head bytes match calldata length exactly.
        bool allowed = harness.processConstraintsViaPolicyLibrary(_constraints(constraint), data);

        // Verify: exact-sized calldata heads should pass without requiring extra trailing bytes.
        assertTrue(allowed, "exact head bytes should be sufficient");
    }

    /// @dev Verifies that processing stops at first failing constraint.
    function test_processConstraints_stopsAtFirstFailingConstraint_returnsFalseWithoutReverting() public view {
        // Setup: build fixture inputs where processing stops at first failing constraint should be denied.
        ParameterConstraint memory firstFailingConstraint = ParameterConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(uint256(2)),
            paramValueInListProof: _emptyProof()
        });
        ParameterConstraint memory secondWouldRevertIfEvaluated = ParameterConstraint({
            paramType: ParamType.Bool,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: hex"01",
            paramValueInListProof: _emptyProof()
        });

        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(1), true);

        // Call: execute `processConstraintsViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.processConstraintsViaPolicyLibrary(
            _constraints(firstFailingConstraint, secondWouldRevertIfEvaluated), data
        );

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "first failure should short-circuit later malformed constraints");
    }

    /// @dev Verifies that struct/tuple with Any can span multiple head slots.
    function test_processConstraints_structAnyMultipleHeadSlots_returnsTrue() public view {
        // Setup: configure a valid fixture for struct/tuple with Any can span multiple head slots.
        ParameterConstraint memory structAnyConstraint = ParameterConstraint({
            paramType: ParamType.Struct,
            constraintType: ConstraintType.Any,
            paramCalldataHeadSlotCount: 2,
            comparisonData: bytes(""),
            paramValueInListProof: _emptyProof()
        });

        // Tuple(uint256,address) encoded in-head occupies 2 slots.
        bytes memory data = bytes.concat(BASE_SELECTOR, abi.encode(uint256(1234), reviewer2));

        // Call: execute `processConstraintsViaPolicyLibrary` with the happy-path payload.
        bool allowed = harness.processConstraintsViaPolicyLibrary(_constraints(structAnyConstraint), data);

        // Verify: assert the expected success result and state updates.
        assertTrue(allowed, "multi-slot struct Any constraint should process without decode errors");
    }

    /// @dev Verifies that later constraints fail when offset advancement exhausts available head bytes.
    function test_processConstraints_secondConstraintHeadOutOfBoundsAfterOffsetAdvance_returnsFalse() public view {
        // Setup: first constraint consumes two head slots; second needs one more slot that is absent.
        ParameterConstraint memory firstArrayAny = ParameterConstraint({
            paramType: ParamType.Array,
            constraintType: ConstraintType.Any,
            paramCalldataHeadSlotCount: 2,
            comparisonData: bytes(""),
            paramValueInListProof: _emptyProof()
        });
        ParameterConstraint memory secondUint = ParameterConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(uint256(9)),
            paramValueInListProof: _emptyProof()
        });
        bytes memory data = bytes.concat(BASE_SELECTOR, abi.encode(uint256(1), uint256(2)));

        // Call: run processing where the second constraint starts beyond available head bytes.
        bool allowed = harness.processConstraintsViaPolicyLibrary(_constraints(firstArrayAny, secondUint), data);

        // Verify: the out-of-bounds second head read should fail closed.
        assertFalse(allowed, "offset advancement beyond calldata should fail");
    }

    /// @dev Verifies that primitive Any constraints still reject multi-slot head declarations.
    function test_processConstraints_primitiveAnyWithHeadSlotsGreaterThanOne_returnsFalse() public view {
        // Setup: primitive bool parameter incorrectly declares two head slots under Any.
        ParameterConstraint memory primitiveAny = ParameterConstraint({
            paramType: ParamType.Bool,
            constraintType: ConstraintType.Any,
            paramCalldataHeadSlotCount: 2,
            comparisonData: bytes(""),
            paramValueInListProof: _emptyProof()
        });
        bytes memory data = bytes.concat(BASE_SELECTOR, abi.encode(true, uint256(3)));

        // Call: process a malformed primitive constraint shape.
        bool allowed = harness.processConstraintsViaPolicyLibrary(_constraints(primitiveAny), data);

        // Verify: primitive types with headSlots>1 must fail closed regardless of constraint type.
        assertFalse(allowed, "primitive Any with headSlots>1 should fail");
    }

    /// @dev Verifies that primitive types with headSlots>1 fail closed.
    function test_processConstraints_primitiveTypeWithHeadSlotsGreaterThanOne_failClosedDesiredBehavior() public view {
        // Setup: build fixture inputs where primitive types with headSlots>1 fail closed should be denied.
        ParameterConstraint memory primitiveConstraint = ParameterConstraint({
            paramType: ParamType.Bool,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 2,
            comparisonData: abi.encode(true),
            paramValueInListProof: _emptyProof()
        });

        // First head slot is canonical true; second slot is unrelated payload.
        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, true, uint256(999));

        // Call: execute `processConstraintsViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.processConstraintsViaPolicyLibrary(_constraints(primitiveConstraint), data);

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "primitive constraints should fail closed when headSlots>1");
    }
}
