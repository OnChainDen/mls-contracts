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
