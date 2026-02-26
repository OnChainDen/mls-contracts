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
contract LibPolicyParameterConstraintsSection81Test is LibPolicyParameterConstraintsSuiteBase {
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

/**
 * @dev Section 8.2 tests for `_processConstraints`.
 */
contract LibPolicyParameterConstraintsSection82Test is LibPolicyParameterConstraintsSuiteBase {
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

/**
 * @dev Section 8.3 tests for `_isParameterAllowedByConstraint` dispatcher.
 */
contract LibPolicyParameterConstraintsSection83Test is LibPolicyParameterConstraintsSuiteBase {
    /// @dev Verifies that `ConstraintType.Any` returns true across supported parameter types.
    function test_isParameterAllowedByConstraint_anyConstraint_returnsTrueForAllSupportedTypes() public view {
        // Setup: configure a valid fixture for `ConstraintType.Any` returns true across supported parameter types.
        ParamType[] memory supportedTypes = new ParamType[](9);
        supportedTypes[0] = ParamType.Uint;
        supportedTypes[1] = ParamType.Int;
        supportedTypes[2] = ParamType.Address;
        supportedTypes[3] = ParamType.Bool;
        supportedTypes[4] = ParamType.FixedBytes;
        supportedTypes[5] = ParamType.Bytes;
        supportedTypes[6] = ParamType.String;
        supportedTypes[7] = ParamType.Array;
        supportedTypes[8] = ParamType.Struct;

        for (uint256 i = 0; i < supportedTypes.length; ++i) {
            ParameterConstraint memory anyConstraint = ParameterConstraint({
                paramType: supportedTypes[i],
                constraintType: ConstraintType.Any,
                paramCalldataHeadSlotCount: 1,
                comparisonData: bytes(""),
                paramValueInListProof: _emptyProof()
            });

            // Call: execute `isParameterAllowedByConstraintViaPolicyLibrary` with the happy-path payload.
            bool allowed = harness.isParameterAllowedByConstraintViaPolicyLibrary(
                anyConstraint, bytes32(uint256(1)), abi.encodeWithSelector(BASE_SELECTOR, uint256(1))
            );

            // Verify: assert the expected success result and state updates.
            assertTrue(allowed, "Any constraint should allow every supported param type");
        }
    }

    /// @dev Verifies that unsupported constraint type for a parameter kind returns false.
    function test_isParameterAllowedByConstraint_unsupportedConstraintForType_returnsFalse() public view {
        // Setup: build fixture inputs where unsupported constraint type for a parameter kind returns false should be
        // denied.
        ParameterConstraint memory invalidConstraint = ParameterConstraint({
            paramType: ParamType.Bool,
            constraintType: ConstraintType.Range,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(uint256(0), uint256(1)),
            paramValueInListProof: _emptyProof()
        });

        // Call: execute `isParameterAllowedByConstraintViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.isParameterAllowedByConstraintViaPolicyLibrary(
            invalidConstraint, bytes32(uint256(1)), abi.encodeWithSelector(BASE_SELECTOR, true)
        );

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "unsupported bool-range combination should fail");
    }

    /// @dev Verifies that `ParamType.Array` with non-Any constraint returns false.
    function test_isParameterAllowedByConstraint_arrayWithNonAnyConstraint_returnsFalse() public view {
        // Setup: build fixture inputs where `ParamType.Array` with non-Any constraint returns false should be denied.
        ParameterConstraint memory constraint = ParameterConstraint({
            paramType: ParamType.Array,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 2,
            comparisonData: abi.encode(bytes32(uint256(1))),
            paramValueInListProof: _emptyProof()
        });

        // Call: execute `isParameterAllowedByConstraintViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.isParameterAllowedByConstraintViaPolicyLibrary(
            constraint, bytes32(uint256(1)), abi.encodeWithSelector(BASE_SELECTOR, uint256(1), uint256(2))
        );

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "array supports only Any");
    }

    /// @dev Verifies that `ParamType.Struct` with non-Any constraint returns false.
    function test_isParameterAllowedByConstraint_structWithNonAnyConstraint_returnsFalse() public view {
        // Setup: build fixture inputs where `ParamType.Struct` with non-Any constraint returns false should be denied.
        ParameterConstraint memory constraint = ParameterConstraint({
            paramType: ParamType.Struct,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 2,
            comparisonData: abi.encode(bytes32(uint256(1))),
            paramValueInListProof: _emptyProof()
        });

        // Call: execute `isParameterAllowedByConstraintViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.isParameterAllowedByConstraintViaPolicyLibrary(
            constraint, bytes32(uint256(1)), abi.encodeWithSelector(BASE_SELECTOR, uint256(1), uint256(2))
        );

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "struct supports only Any");
    }

    /// @dev Verifies that unknown `ParamType` values revert during parameter-constraint dispatch.
    function test_isParameterAllowedByConstraint_unknownParamType_reverts() public {
        // Setup: build fixture inputs where unknown `ParamType` values revert during parameter-constraint dispatch.
        ParameterConstraint memory constraint = ParameterConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(uint256(1)),
            paramValueInListProof: _emptyProof()
        });
        bytes memory callData = abi.encodeCall(
            harness.isParameterAllowedByConstraintViaPolicyLibrary,
            (constraint, bytes32(uint256(1)), abi.encodeWithSelector(BASE_SELECTOR, uint256(1)))
        );
        uint256 constraintOffset = _readWord(callData, 4);
        _setWord(callData, 4 + constraintOffset, type(uint8).max);

        // Call: execute low-level call with malformed enum calldata.
        (bool success,) = address(harness).call(callData);
        // Verify: assert malformed enum values fail with a revert/panic.
        assertFalse(success, "unknown param type should revert");
    }

    /// @dev Verifies that address OneOf path validates proof against decoded root.
    function test_isParameterAllowedByConstraint_addressOneOf_validProof_returnsTrue() public {
        // Setup: configure a valid fixture for address OneOf path validates proof against decoded root.
        address[] memory members = buildArray(reviewer1, reviewer2, initiator1);
        (bytes32 root, bytes32[] memory proof) = _buildAddressRootAndProof(members, 1);

        ParameterConstraint memory constraint = ParameterConstraint({
            paramType: ParamType.Address,
            constraintType: ConstraintType.OneOf,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(root),
            paramValueInListProof: proof
        });

        // Call: execute `isParameterAllowedByConstraintViaPolicyLibrary` with the happy-path payload.
        bool allowed = harness.isParameterAllowedByConstraintViaPolicyLibrary(
            constraint, _encodeAddressHead(reviewer2), abi.encodeWithSelector(BASE_SELECTOR, reviewer2)
        );

        // Verify: assert the expected success result and state updates.
        assertTrue(allowed, "valid address proof should pass");
    }

    /// @dev Verifies that bytes/string dispatch uses dynamic offset and content hash correctly.
    function test_isParameterAllowedByConstraint_bytesAndString_dispatchPath_usesOffsetAndHash() public view {
        // Setup: configure a valid fixture for bytes/string dispatch uses dynamic offset and content hash correctly.
        bytes memory expectedBytes = hex"AABBCCDD";
        bytes memory bytesData = _encodeSingleBytesArg(expectedBytes);

        ParameterConstraint memory bytesConstraint = ParameterConstraint({
            paramType: ParamType.Bytes,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(keccak256(expectedBytes)),
            paramValueInListProof: _emptyProof()
        });

        // Call: execute `isParameterAllowedByConstraintViaPolicyLibrary` with the happy-path payload.
        bool bytesAllowed =
            harness.isParameterAllowedByConstraintViaPolicyLibrary(bytesConstraint, bytes32(uint256(32)), bytesData);
        // Verify: assert the expected success result and state updates.
        assertTrue(bytesAllowed, "dynamic bytes hash match should pass");

        string memory expectedString = "policy-constraints";
        bytes memory stringData = _encodeSingleStringArg(expectedString);

        ParameterConstraint memory stringConstraint = ParameterConstraint({
            paramType: ParamType.String,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(keccak256(bytes(expectedString))),
            paramValueInListProof: _emptyProof()
        });

        bool stringAllowed =
            harness.isParameterAllowedByConstraintViaPolicyLibrary(stringConstraint, bytes32(uint256(32)), stringData);
        assertTrue(stringAllowed, "string hash match should pass");
    }

    /// @dev Verifies that invalid dynamic offset fails closed with false.
    function test_isParameterAllowedByConstraint_invalidDynamicOffset_failClosedDesiredBehavior() public view {
        // Setup: build fixture inputs where invalid dynamic offset fails closed with false should be denied.
        bytes memory data = _encodeSingleBytesArg(bytes("abc"));

        ParameterConstraint memory bytesConstraint = ParameterConstraint({
            paramType: ParamType.Bytes,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(keccak256(bytes("abc"))),
            paramValueInListProof: _emptyProof()
        });

        // Call: execute `isParameterAllowedByConstraintViaPolicyLibrary` and capture the authorization decision.
        bool allowed =
            harness.isParameterAllowedByConstraintViaPolicyLibrary(bytesConstraint, bytes32(uint256(4096)), data);

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "invalid dynamic offset should fail closed");
    }

    /// @dev Verifies that unknown `ConstraintType` values revert across supported dispatch paths.
    function test_isParameterAllowedByConstraint_unknownConstraintType_revertsAcrossSupportedDispatch()
        // Setup: build fixture inputs where unknown `ConstraintType` values revert across supported dispatch paths.
        public
    {
        ParamType[] memory supportedTypes = new ParamType[](9);
        supportedTypes[0] = ParamType.Uint;
        supportedTypes[1] = ParamType.Int;
        supportedTypes[2] = ParamType.Address;
        supportedTypes[3] = ParamType.Bool;
        supportedTypes[4] = ParamType.FixedBytes;
        supportedTypes[5] = ParamType.Bytes;
        supportedTypes[6] = ParamType.String;
        supportedTypes[7] = ParamType.Array;
        supportedTypes[8] = ParamType.Struct;

        for (uint256 i = 0; i < supportedTypes.length; ++i) {
            ParameterConstraint memory constraint = ParameterConstraint({
                paramType: supportedTypes[i],
                constraintType: ConstraintType.Exact,
                paramCalldataHeadSlotCount: 1,
                comparisonData: abi.encode(uint256(1)),
                paramValueInListProof: _emptyProof()
            });
            bytes memory callData = abi.encodeCall(
                harness.isParameterAllowedByConstraintViaPolicyLibrary,
                (constraint, bytes32(uint256(1)), abi.encodeWithSelector(BASE_SELECTOR, uint256(1)))
            );
            uint256 constraintOffset = _readWord(callData, 4);
            _setWord(callData, 4 + constraintOffset + 32, type(uint8).max);

            // Call: execute low-level call with malformed enum calldata.
            (bool success,) = address(harness).call(callData);
            // Verify: assert malformed enum values fail with a revert/panic.
            assertFalse(success, "unknown constraint type should revert");
        }
    }
}

/**
 * @dev Section 8.4 tests for `_isBoolParameterAllowedByConstraint`.
 */
contract LibPolicyParameterConstraintsSection84Test is LibPolicyParameterConstraintsSuiteBase {
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

/**
 * @dev Section 8.5 tests for `_isUintParameterAllowedByConstraint`.
 */
contract LibPolicyParameterConstraintsSection85Test is LibPolicyParameterConstraintsSuiteBase {
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

/**
 * @dev Section 8.6 tests for `_isIntParameterAllowedByConstraint`.
 */
contract LibPolicyParameterConstraintsSection86Test is LibPolicyParameterConstraintsSuiteBase {
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

/**
 * @dev Section 8.7 tests for `_isAddressParameterAllowedByConstraint`.
 */
contract LibPolicyParameterConstraintsSection87Test is LibPolicyParameterConstraintsSuiteBase {
    /// @dev Verifies that exact match passes and exact mismatch fails.
    function test_isAddressParameterAllowedByConstraint_exactMatchAndMismatch() public view {
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for exact match passes and exact
        // mismatch fails. Call: run `isAddressParameterAllowedByConstraintViaPolicyLibrary` across the prepared
        // variants.
        bool matchAllowed = harness.isAddressParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(reviewer1), _encodeAddressHead(reviewer1), _emptyProof()
        );
        bool mismatchAllowed = harness.isAddressParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(reviewer2), _encodeAddressHead(reviewer1), _emptyProof()
        );

        // Verify: assert each variant returns the expected branch outcome.
        assertTrue(matchAllowed, "address exact match should pass");
        assertFalse(mismatchAllowed, "address exact mismatch should fail");
    }

    /// @dev Verifies that OneOf with valid root/proof returns true.
    function test_isAddressParameterAllowedByConstraint_oneOfValidProof_returnsTrue() public {
        // Setup: configure a valid fixture for OneOf with valid root/proof returns true.
        address[] memory values = buildArray(reviewer1, reviewer2, initiator1);
        (bytes32 root, bytes32[] memory proof) = _buildAddressRootAndProof(values, 0);

        // Call: execute `isAddressParameterAllowedByConstraintViaPolicyLibrary` with the happy-path payload.
        bool allowed = harness.isAddressParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.OneOf, abi.encode(root), _encodeAddressHead(reviewer1), proof
        );

        // Verify: assert the expected success result and state updates.
        assertTrue(allowed, "valid OneOf proof should pass");
    }

    /// @dev Verifies that invalid OneOf proof/root mismatch returns false.
    function test_isAddressParameterAllowedByConstraint_oneOfInvalidProof_returnsFalse() public {
        // Setup: build fixture inputs where invalid OneOf proof/root mismatch returns false should be denied.
        address[] memory values = buildArray(reviewer1, reviewer2, initiator1);
        (bytes32 root, bytes32[] memory proofForReviewer1) = _buildAddressRootAndProof(values, 0);

        // Call: execute `isAddressParameterAllowedByConstraintViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.isAddressParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.OneOf, abi.encode(root), _encodeAddressHead(reviewer2), proofForReviewer1
        );

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "proof for another address should fail");
    }

    /// @dev Verifies that unsupported Range returns false.
    function test_isAddressParameterAllowedByConstraint_rangeUnsupported_returnsFalse() public view {
        // Setup: build fixture inputs where unsupported Range returns false should be denied.
        // Call: execute `isAddressParameterAllowedByConstraintViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.isAddressParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, abi.encode(reviewer1), _encodeAddressHead(reviewer1), _emptyProof()
        );

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "address does not support Range");
    }

    /// @dev Verifies that dirty upper 96 bits do not affect lower-160 extracted address.
    function test_isAddressParameterAllowedByConstraint_dirtyUpperBits_doNotChangeAddressExtraction() public view {
        // Setup: configure a valid fixture for dirty upper 96 bits do not affect lower-160 extracted address.
        uint256 dirtyPacked = uint256(uint160(reviewer1)) | (uint256(0xBEEFCAFE) << 200);

        // Call: execute `isAddressParameterAllowedByConstraintViaPolicyLibrary` with the happy-path payload.
        bool allowed = harness.isAddressParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(reviewer1), bytes32(dirtyPacked), _emptyProof()
        );

        // Verify: assert the expected success result and state updates.
        assertTrue(allowed, "address extraction should ignore dirty upper bits");
    }

    /// @dev Verifies that malformed comparisonData fails closed with false.
    function test_isAddressParameterAllowedByConstraint_malformedComparisonData_failClosedDesiredBehavior() public {
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for malformed comparisonData fails
        // closed with false. Call: run `isAddressParameterAllowedByConstraintViaPolicyLibrary` across the prepared
        // variants.
        try harness.isAddressParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, hex"01", _encodeAddressHead(reviewer1), _emptyProof()
        ) returns (
            bool allowed
        ) {
            // Verify: assert each variant returns the expected branch outcome.
            assertFalse(allowed, "malformed address comparisonData should fail closed with false");
        } catch {
            assertTrue(false, "malformed address comparisonData should fail closed with false instead of reverting");
        }
    }
}

/**
 * @dev Section 8.8 tests for `_isFixedBytesParameterAllowedByConstraint`.
 */
contract LibPolicyParameterConstraintsSection88Test is LibPolicyParameterConstraintsSuiteBase {
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

/**
 * @dev Section 8.9 tests for `_isBytesOrStringParameterAllowedByConstraint`.
 */
contract LibPolicyParameterConstraintsSection89Test is LibPolicyParameterConstraintsSuiteBase {
    /// @dev Verifies that dynamic bytes exact hash matching works.
    function test_isBytesOrStringParameterAllowedByConstraint_dynamicBytesHashMatchAndMismatch() public view {
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for dynamic bytes exact hash
        // matching works.
        bytes memory expectedBytes = hex"CAFEBABE";
        bytes memory data = _encodeSingleBytesArg(expectedBytes);

        // Call: run `isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary` across the prepared variants.
        bool matchAllowed = harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(keccak256(expectedBytes)), bytes32(uint256(32)), data
        );
        bool mismatchAllowed = harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(keccak256(bytes("different"))), bytes32(uint256(32)), data
        );

        // Verify: assert each variant returns the expected branch outcome.
        assertTrue(matchAllowed, "matching dynamic-bytes hash should pass");
        assertFalse(mismatchAllowed, "mismatching dynamic-bytes hash should fail");
    }

    /// @dev Verifies that string exact hash matching works.
    function test_isBytesOrStringParameterAllowedByConstraint_stringHashMatchAndMismatch() public view {
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for string exact hash matching
        // works.
        string memory expectedString = "den-policy";
        bytes memory data = _encodeSingleStringArg(expectedString);

        // Call: run `isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary` across the prepared variants.
        bool matchAllowed = harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(keccak256(bytes(expectedString))), bytes32(uint256(32)), data
        );
        bool mismatchAllowed = harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(keccak256(bytes("different"))), bytes32(uint256(32)), data
        );

        // Verify: assert each variant returns the expected branch outcome.
        assertTrue(matchAllowed, "matching string hash should pass");
        assertFalse(mismatchAllowed, "mismatching string hash should fail");
    }

    /// @dev Verifies that empty dynamic values are handled correctly.
    function test_isBytesOrStringParameterAllowedByConstraint_emptyDynamicValue_returnsTrueForMatchingEmptyHash()
        // Setup: configure a valid fixture for empty dynamic values are handled correctly.
        public
        view
    {
        bytes memory emptyBytes = bytes("");
        bytes memory data = _encodeSingleBytesArg(emptyBytes);

        // Call: execute `isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary` with the happy-path payload.
        bool allowed = harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(keccak256(emptyBytes)), bytes32(uint256(32)), data
        );

        // Verify: assert the expected success result and state updates.
        assertTrue(allowed, "empty dynamic value should hash/compare correctly");
    }

    /// @dev Verifies that large dynamic values are parsed and hashed correctly.
    function test_isBytesOrStringParameterAllowedByConstraint_largeDynamicValue_returnsTrue() public view {
        // Setup: configure a valid fixture for large dynamic values are parsed and hashed correctly.
        bytes memory largeValue = new bytes(1024);
        for (uint256 i = 0; i < largeValue.length; ++i) {
            largeValue[i] = bytes1(uint8(i));
        }

        bytes memory data = _encodeSingleBytesArg(largeValue);

        // Call: execute `isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary` with the happy-path payload.
        bool allowed = harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(keccak256(largeValue)), bytes32(uint256(32)), data
        );

        // Verify: assert the expected success result and state updates.
        assertTrue(allowed, "large dynamic values should hash/compare correctly");
    }

    /// @dev Verifies that offsets beyond calldata length return false.
    function test_isBytesOrStringParameterAllowedByConstraint_offsetBeyondCalldata_returnsFalse() public view {
        // Setup: build fixture inputs where offsets beyond calldata length return false should be denied.
        bytes memory data = _encodeSingleBytesArg(bytes("abc"));

        // Call: execute `isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary` and capture the authorization
        // decision.
        bool allowed = harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(keccak256(bytes("abc"))), bytes32(uint256(9999)), data
        );

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "offset beyond calldata should fail");
    }

    /// @dev Verifies that declared lengths extending beyond calldata return false.
    function test_isBytesOrStringParameterAllowedByConstraint_declaredLengthBeyondCalldata_returnsFalse() public view {
        // Selector + head(offset=32) + length(100), but no payload bytes for the declared length.
        // Setup: build fixture inputs where declared lengths extending beyond calldata return false should be denied.
        bytes memory malformedData = bytes.concat(BASE_SELECTOR, abi.encode(uint256(32), uint256(100)));

        // Call: execute `isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary` and capture the authorization
        // decision.
        bool allowed = harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(keccak256(bytes("unused"))), bytes32(uint256(32)), malformedData
        );

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "length extending beyond calldata should fail");
    }

    /// @dev Verifies that non-Exact constraint types return false.
    function test_isBytesOrStringParameterAllowedByConstraint_nonExactConstraint_returnsFalse() public view {
        // Setup: build fixture inputs where non-Exact constraint types return false should be denied.
        bytes memory data = _encodeSingleBytesArg(bytes("abc"));

        // Call: execute `isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary` and capture the authorization
        // decision.
        bool allowed = harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, abi.encode(keccak256(bytes("abc"))), bytes32(uint256(32)), data
        );

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "bytes/string supports only Exact");
    }

    /// @dev Verifies that offsets into ABI head region fail closed.
    function test_isBytesOrStringParameterAllowedByConstraint_offsetIntoHeadRegion_failClosedDesiredBehavior()
        // Setup: build fixture inputs where offsets into ABI head region fail closed should be denied.
        public
        view
    {
        bytes memory payload = bytes("abcdefg");
        bytes memory data = _encodeSingleBytesArg(payload);

        // If offset points to the head (offset=0), current implementation reads slot-0 as "length" (=32).
        // Desired behavior is to reject this as invalid instead of accepting head-region reads.
        bytes32 forgedExpectedHash = keccak256(abi.encode(uint256(payload.length)));

        // Call: execute `isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary` and capture the authorization
        // decision.
        bool allowed = harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(forgedExpectedHash), bytes32(uint256(0)), data
        );

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "offset into ABI head region should fail closed");
    }

    /// @dev Verifies that offset/length arithmetic overflow fails closed.
    function test_isBytesOrStringParameterAllowedByConstraint_overflowingOffset_failClosedDesiredBehavior() public {
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for offset/length arithmetic
        // overflow fails closed.
        bytes memory data = _encodeSingleBytesArg(bytes("abc"));

        // Call: run `isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary` across the prepared variants.
        try harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(keccak256(bytes("abc"))), bytes32(type(uint256).max), data
        ) returns (
            bool allowed
        ) {
            // Verify: assert each variant returns the expected branch outcome.
            assertFalse(allowed, "overflowing offset should fail closed with false");
        } catch {
            assertTrue(false, "overflowing offset should fail closed with false instead of reverting");
        }
    }

    /// @dev Verifies that malformed comparisonData fails closed with false.
    function test_isBytesOrStringParameterAllowedByConstraint_malformedComparisonData_failClosedDesiredBehavior()
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for malformed comparisonData fails
        // closed with false.
        public
    {
        bytes memory data = _encodeSingleBytesArg(bytes("abc"));

        // Call: run `isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary` across the prepared variants.
        try harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, hex"01", bytes32(uint256(32)), data
        ) returns (
            bool allowed
        ) {
            // Verify: assert each variant returns the expected branch outcome.
            assertFalse(allowed, "malformed bytes/string comparisonData should fail closed with false");
        } catch {
            assertTrue(
                false, "malformed bytes/string comparisonData should fail closed with false instead of reverting"
            );
        }
    }
}
