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
    /// @dev Verifies LPPC-1: empty `parameterConstraints` bytes returns true.
    function test_areParametersAllowedByConstraints_emptyConstraintsBytes_returnsTrue() public view {
        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(7));

        bool allowed = harness.areParametersAllowedByConstraintsViaPolicyLibrary(bytes(""), data);

        assertTrue(allowed, "empty constraints bytes should allow by default");
    }

    /// @dev Verifies LPPC-2: ABI-encoded empty constraints array returns true.
    function test_areParametersAllowedByConstraints_abiEncodedEmptyArray_returnsTrue() public view {
        ParameterConstraint[] memory constraints = new ParameterConstraint[](0);
        bytes memory encodedConstraints = abi.encode(constraints);
        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(7));

        bool allowed = harness.areParametersAllowedByConstraintsViaPolicyLibrary(encodedConstraints, data);

        assertTrue(allowed, "empty decoded constraints array should allow by default");
    }

    /// @dev Verifies LPPC-3: a single valid constraint returns true.
    function test_areParametersAllowedByConstraints_singleValidConstraint_returnsTrue() public view {
        ParameterConstraint memory constraint = _buildConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Exact,
            headSlots: 1,
            comparisonData: abi.encode(uint256(42)),
            paramValueInListProof: _emptyProof()
        });

        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(42));

        bool allowed =
            harness.areParametersAllowedByConstraintsViaPolicyLibrary(_encodeSingleConstraint(constraint), data);

        assertTrue(allowed, "matching uint exact constraint should pass");
    }

    /// @dev Verifies LPPC-4: multiple passing constraints return true.
    function test_areParametersAllowedByConstraints_multiplePassingConstraints_returnsTrue() public view {
        ParameterConstraint memory uintConstraint = _buildConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Exact,
            headSlots: 1,
            comparisonData: abi.encode(uint256(11)),
            paramValueInListProof: _emptyProof()
        });
        ParameterConstraint memory addressConstraint = _buildConstraint({
            paramType: ParamType.Address,
            constraintType: ConstraintType.Exact,
            headSlots: 1,
            comparisonData: abi.encode(reviewer1),
            paramValueInListProof: _emptyProof()
        });
        ParameterConstraint memory boolConstraint = _buildConstraint({
            paramType: ParamType.Bool,
            constraintType: ConstraintType.Exact,
            headSlots: 1,
            comparisonData: abi.encode(true),
            paramValueInListProof: _emptyProof()
        });

        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(11), reviewer1, true);

        bool allowed = harness.areParametersAllowedByConstraintsViaPolicyLibrary(
            abi.encode(_constraints(uintConstraint, addressConstraint, boolConstraint)), data
        );

        assertTrue(allowed, "all constraints passing should return true");
    }

    /// @dev Verifies LPPC-5: any failing constraint causes false.
    function test_areParametersAllowedByConstraints_anyFailingConstraint_returnsFalse() public view {
        ParameterConstraint memory passingConstraint = _buildConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Exact,
            headSlots: 1,
            comparisonData: abi.encode(uint256(11)),
            paramValueInListProof: _emptyProof()
        });
        ParameterConstraint memory failingConstraint = _buildConstraint({
            paramType: ParamType.Address,
            constraintType: ConstraintType.Exact,
            headSlots: 1,
            comparisonData: abi.encode(reviewer2),
            paramValueInListProof: _emptyProof()
        });

        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(11), reviewer1);

        bool allowed = harness.areParametersAllowedByConstraintsViaPolicyLibrary(
            abi.encode(_constraints(passingConstraint, failingConstraint)), data
        );

        assertFalse(allowed, "one failing constraint should cause false");
    }

    /// @dev Verifies LPPC-6 desired behavior: malformed encoded constraints fail closed with false.
    function test_areParametersAllowedByConstraints_malformedEncodedConstraints_failClosedDesiredBehavior() public {
        bytes memory malformedConstraints = hex"0001";
        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(1));

        try harness.areParametersAllowedByConstraintsViaPolicyLibrary(malformedConstraints, data) returns (
            bool allowed
        ) {
            assertFalse(allowed, "malformed constraints should fail closed with false");
        } catch {
            assertTrue(false, "malformed constraints should fail closed with false instead of reverting");
        }
    }

    /// @dev Verifies LPPC-7 desired behavior: malformed comparisonData in a constraint fails closed with false.
    function test_areParametersAllowedByConstraints_malformedComparisonData_failClosedDesiredBehavior() public {
        ParameterConstraint memory malformedConstraint = _buildConstraint({
            paramType: ParamType.Bool,
            constraintType: ConstraintType.Exact,
            headSlots: 1,
            comparisonData: hex"01",
            paramValueInListProof: _emptyProof()
        });

        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, true);

        try harness.areParametersAllowedByConstraintsViaPolicyLibrary(
            _encodeSingleConstraint(malformedConstraint), data
        ) returns (
            bool allowed
        ) {
            assertFalse(allowed, "malformed comparisonData should fail closed with false");
        } catch {
            assertTrue(false, "malformed comparisonData should fail closed with false instead of reverting");
        }
    }

    /// @dev Verifies LPPC-8: identical inputs produce deterministic output.
    function test_areParametersAllowedByConstraints_deterministicForSameInputs() public view {
        ParameterConstraint memory constraint = _buildConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Range,
            headSlots: 1,
            comparisonData: abi.encode(uint256(10), uint256(20)),
            paramValueInListProof: _emptyProof()
        });

        bytes memory encodedConstraints = _encodeSingleConstraint(constraint);
        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(12));

        bool first = harness.areParametersAllowedByConstraintsViaPolicyLibrary(encodedConstraints, data);
        bool second = harness.areParametersAllowedByConstraintsViaPolicyLibrary(encodedConstraints, data);

        assertEq(first, second, "same inputs must produce same result");
    }
}

/**
 * @dev Section 8.2 tests for `_processConstraints`.
 */
contract LibPolicyParameterConstraintsSection82Test is LibPolicyParameterConstraintsSuiteBase {
    /// @dev Verifies LPPC-PROC-1: mixed head slot counts advance offsets correctly.
    function test_processConstraints_mixedHeadSlots_advancesOffsetsCorrectly() public view {
        bytes32[2] memory staticArray = [bytes32(uint256(11)), bytes32(uint256(22))];

        ParameterConstraint memory uintConstraint = _buildConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Exact,
            headSlots: 1,
            comparisonData: abi.encode(uint256(77)),
            paramValueInListProof: _emptyProof()
        });
        ParameterConstraint memory arrayAnyConstraint = _buildConstraint({
            paramType: ParamType.Array,
            constraintType: ConstraintType.Any,
            headSlots: 2,
            comparisonData: bytes(""),
            paramValueInListProof: _emptyProof()
        });
        ParameterConstraint memory addressConstraint = _buildConstraint({
            paramType: ParamType.Address,
            constraintType: ConstraintType.Exact,
            headSlots: 1,
            comparisonData: abi.encode(reviewer1),
            paramValueInListProof: _emptyProof()
        });

        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(77), staticArray, reviewer1);

        bool allowed = harness.processConstraintsViaPolicyLibrary(
            _constraints(uintConstraint, arrayAnyConstraint, addressConstraint), data
        );

        assertTrue(allowed, "offset advancement across 1/2/1 head-slot params should validate correctly");
    }

    /// @dev Verifies LPPC-PROC-2: zero `paramCalldataHeadSlotCount` fails with false.
    function test_processConstraints_zeroHeadSlotCount_returnsFalse() public view {
        ParameterConstraint memory invalidConstraint = _buildConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Exact,
            headSlots: 0,
            comparisonData: abi.encode(uint256(1)),
            paramValueInListProof: _emptyProof()
        });

        bool allowed = harness.processConstraintsViaPolicyLibrary(
            _constraints(invalidConstraint), abi.encodeWithSelector(BASE_SELECTOR, uint256(1))
        );

        assertFalse(allowed, "headSlotCount=0 should fail");
    }

    /// @dev Verifies LPPC-PROC-3: insufficient head bytes in calldata returns false.
    function test_processConstraints_dataShorterThanRequiredHead_returnsFalse() public view {
        ParameterConstraint memory constraint = _buildConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Exact,
            headSlots: 1,
            comparisonData: abi.encode(uint256(1)),
            paramValueInListProof: _emptyProof()
        });

        bytes memory truncatedData = bytes.concat(BASE_SELECTOR, bytes16(uint128(1)));

        bool allowed = harness.processConstraintsViaPolicyLibrary(_constraints(constraint), truncatedData);

        assertFalse(allowed, "truncated calldata head should fail");
    }

    /// @dev Verifies LPPC-PROC-4: processing stops at first failing constraint.
    function test_processConstraints_stopsAtFirstFailingConstraint_returnsFalseWithoutReverting() public view {
        ParameterConstraint memory firstFailingConstraint = _buildConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Exact,
            headSlots: 1,
            comparisonData: abi.encode(uint256(2)),
            paramValueInListProof: _emptyProof()
        });
        ParameterConstraint memory secondWouldRevertIfEvaluated = _buildConstraint({
            paramType: ParamType.Bool,
            constraintType: ConstraintType.Exact,
            headSlots: 1,
            comparisonData: hex"01",
            paramValueInListProof: _emptyProof()
        });

        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(1), true);

        bool allowed = harness.processConstraintsViaPolicyLibrary(
            _constraints(firstFailingConstraint, secondWouldRevertIfEvaluated), data
        );

        assertFalse(allowed, "first failure should short-circuit later malformed constraints");
    }

    /// @dev Verifies LPPC-PROC-5: struct/tuple with Any can span multiple head slots.
    function test_processConstraints_structAnyMultipleHeadSlots_returnsTrue() public view {
        ParameterConstraint memory structAnyConstraint = _buildConstraint({
            paramType: ParamType.Struct,
            constraintType: ConstraintType.Any,
            headSlots: 2,
            comparisonData: bytes(""),
            paramValueInListProof: _emptyProof()
        });

        // Tuple(uint256,address) encoded in-head occupies 2 slots.
        bytes memory data = bytes.concat(BASE_SELECTOR, abi.encode(uint256(1234), reviewer2));

        bool allowed = harness.processConstraintsViaPolicyLibrary(_constraints(structAnyConstraint), data);

        assertTrue(allowed, "multi-slot struct Any constraint should process without decode errors");
    }

    /// @dev Verifies LPPC-PROC-8 desired behavior: primitive types with headSlots>1 fail closed.
    function test_processConstraints_primitiveTypeWithHeadSlotsGreaterThanOne_failClosedDesiredBehavior() public view {
        ParameterConstraint memory primitiveConstraint = _buildConstraint({
            paramType: ParamType.Bool,
            constraintType: ConstraintType.Exact,
            headSlots: 2,
            comparisonData: abi.encode(true),
            paramValueInListProof: _emptyProof()
        });

        // First head slot is canonical true; second slot is unrelated payload.
        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, true, uint256(999));

        bool allowed = harness.processConstraintsViaPolicyLibrary(_constraints(primitiveConstraint), data);

        assertFalse(allowed, "primitive constraints should fail closed when headSlots>1");
    }
}

/**
 * @dev Section 8.3 tests for `_isParameterAllowedByConstraint` dispatcher.
 */
contract LibPolicyParameterConstraintsSection83Test is LibPolicyParameterConstraintsSuiteBase {
    /// @dev Verifies LPPC-DISP-1: `ConstraintType.Any` returns true across supported parameter types.
    function test_isParameterAllowedByConstraint_anyConstraint_returnsTrueForAllSupportedTypes() public view {
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
            ParameterConstraint memory anyConstraint = _buildConstraint({
                paramType: supportedTypes[i],
                constraintType: ConstraintType.Any,
                headSlots: 1,
                comparisonData: bytes(""),
                paramValueInListProof: _emptyProof()
            });

            bool allowed = harness.isParameterAllowedByConstraintViaPolicyLibrary(
                anyConstraint, bytes32(uint256(1)), abi.encodeWithSelector(BASE_SELECTOR, uint256(1))
            );

            assertTrue(allowed, "Any constraint should allow every supported param type");
        }
    }

    /// @dev Verifies LPPC-DISP-2: unsupported constraint type for a parameter kind returns false.
    function test_isParameterAllowedByConstraint_unsupportedConstraintForType_returnsFalse() public view {
        ParameterConstraint memory invalidConstraint = _buildConstraint({
            paramType: ParamType.Bool,
            constraintType: ConstraintType.Range,
            headSlots: 1,
            comparisonData: abi.encode(uint256(0), uint256(1)),
            paramValueInListProof: _emptyProof()
        });

        bool allowed = harness.isParameterAllowedByConstraintViaPolicyLibrary(
            invalidConstraint, bytes32(uint256(1)), abi.encodeWithSelector(BASE_SELECTOR, true)
        );

        assertFalse(allowed, "unsupported bool-range combination should fail");
    }

    /// @dev Verifies LPPC-DISP-3: `ParamType.Array` with non-Any constraint returns false.
    function test_isParameterAllowedByConstraint_arrayWithNonAnyConstraint_returnsFalse() public view {
        ParameterConstraint memory constraint = _buildConstraint({
            paramType: ParamType.Array,
            constraintType: ConstraintType.Exact,
            headSlots: 2,
            comparisonData: abi.encode(bytes32(uint256(1))),
            paramValueInListProof: _emptyProof()
        });

        bool allowed = harness.isParameterAllowedByConstraintViaPolicyLibrary(
            constraint, bytes32(uint256(1)), abi.encodeWithSelector(BASE_SELECTOR, uint256(1), uint256(2))
        );

        assertFalse(allowed, "array supports only Any");
    }

    /// @dev Verifies LPPC-DISP-4: `ParamType.Struct` with non-Any constraint returns false.
    function test_isParameterAllowedByConstraint_structWithNonAnyConstraint_returnsFalse() public view {
        ParameterConstraint memory constraint = _buildConstraint({
            paramType: ParamType.Struct,
            constraintType: ConstraintType.Exact,
            headSlots: 2,
            comparisonData: abi.encode(bytes32(uint256(1))),
            paramValueInListProof: _emptyProof()
        });

        bool allowed = harness.isParameterAllowedByConstraintViaPolicyLibrary(
            constraint, bytes32(uint256(1)), abi.encodeWithSelector(BASE_SELECTOR, uint256(1), uint256(2))
        );

        assertFalse(allowed, "struct supports only Any");
    }

    /// @dev Verifies LPPC-DISP-5: unknown `ParamType` fails closed with false.
    function test_isParameterAllowedByConstraint_unknownParamType_returnsFalse() public view {
        ParameterConstraint memory constraint = _buildConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Exact,
            headSlots: 1,
            comparisonData: abi.encode(uint256(1)),
            paramValueInListProof: _emptyProof()
        });
        constraint = _unsafeSetParamType(constraint, type(uint8).max);

        bool allowed = harness.isParameterAllowedByConstraintViaPolicyLibrary(
            constraint, bytes32(uint256(1)), abi.encodeWithSelector(BASE_SELECTOR, uint256(1))
        );

        assertFalse(allowed, "unknown param type should fail closed");
    }

    /// @dev Verifies LPPC-DISP-6: address OneOf path validates proof against decoded root.
    function test_isParameterAllowedByConstraint_addressOneOf_validProof_returnsTrue() public {
        address[] memory members = buildArray(reviewer1, reviewer2, initiator1);
        (bytes32 root, bytes32[] memory proof) = _buildAddressRootAndProof(members, 1);

        ParameterConstraint memory constraint = _buildConstraint({
            paramType: ParamType.Address,
            constraintType: ConstraintType.OneOf,
            headSlots: 1,
            comparisonData: abi.encode(root),
            paramValueInListProof: proof
        });

        bool allowed = harness.isParameterAllowedByConstraintViaPolicyLibrary(
            constraint, _encodeAddressHead(reviewer2), abi.encodeWithSelector(BASE_SELECTOR, reviewer2)
        );

        assertTrue(allowed, "valid address proof should pass");
    }

    /// @dev Verifies LPPC-DISP-7: bytes/string dispatch uses dynamic offset and content hash correctly.
    function test_isParameterAllowedByConstraint_bytesAndString_dispatchPath_usesOffsetAndHash() public view {
        bytes memory expectedBytes = hex"AABBCCDD";
        bytes memory bytesData = _encodeSingleBytesArg(expectedBytes);

        ParameterConstraint memory bytesConstraint = _buildConstraint({
            paramType: ParamType.Bytes,
            constraintType: ConstraintType.Exact,
            headSlots: 1,
            comparisonData: abi.encode(keccak256(expectedBytes)),
            paramValueInListProof: _emptyProof()
        });

        bool bytesAllowed =
            harness.isParameterAllowedByConstraintViaPolicyLibrary(bytesConstraint, bytes32(uint256(32)), bytesData);
        assertTrue(bytesAllowed, "dynamic bytes hash match should pass");

        string memory expectedString = "policy-constraints";
        bytes memory stringData = _encodeSingleStringArg(expectedString);

        ParameterConstraint memory stringConstraint = _buildConstraint({
            paramType: ParamType.String,
            constraintType: ConstraintType.Exact,
            headSlots: 1,
            comparisonData: abi.encode(keccak256(bytes(expectedString))),
            paramValueInListProof: _emptyProof()
        });

        bool stringAllowed =
            harness.isParameterAllowedByConstraintViaPolicyLibrary(stringConstraint, bytes32(uint256(32)), stringData);
        assertTrue(stringAllowed, "string hash match should pass");
    }

    /// @dev Verifies LPPC-DISP-8 desired behavior: invalid dynamic offset fails closed with false.
    function test_isParameterAllowedByConstraint_invalidDynamicOffset_failClosedDesiredBehavior() public view {
        bytes memory data = _encodeSingleBytesArg(bytes("abc"));

        ParameterConstraint memory bytesConstraint = _buildConstraint({
            paramType: ParamType.Bytes,
            constraintType: ConstraintType.Exact,
            headSlots: 1,
            comparisonData: abi.encode(keccak256(bytes("abc"))),
            paramValueInListProof: _emptyProof()
        });

        bool allowed =
            harness.isParameterAllowedByConstraintViaPolicyLibrary(bytesConstraint, bytes32(uint256(4096)), data);

        assertFalse(allowed, "invalid dynamic offset should fail closed");
    }

    /// @dev Verifies LPPC-DISP-9: unknown `ConstraintType` fails closed for supported dispatch paths.
    function test_isParameterAllowedByConstraint_unknownConstraintType_returnsFalseAcrossSupportedDispatch()
        public
        view
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
            ParameterConstraint memory constraint = _buildConstraint({
                paramType: supportedTypes[i],
                constraintType: ConstraintType.Exact,
                headSlots: 1,
                comparisonData: abi.encode(uint256(1)),
                paramValueInListProof: _emptyProof()
            });
            constraint = _unsafeSetConstraintType(constraint, type(uint8).max);

            bool allowed = harness.isParameterAllowedByConstraintViaPolicyLibrary(
                constraint, bytes32(uint256(1)), abi.encodeWithSelector(BASE_SELECTOR, uint256(1))
            );

            assertFalse(allowed, "unknown constraint type should fail closed");
        }
    }
}

/**
 * @dev Section 8.4 tests for `_isBoolParameterAllowedByConstraint`.
 */
contract LibPolicyParameterConstraintsSection84Test is LibPolicyParameterConstraintsSuiteBase {
    /// @dev Verifies LPPC-BOOL-1: canonical true word with exact true passes.
    function test_isBoolParameterAllowedByConstraint_exactTrueCanonicalWord_returnsTrue() public view {
        bool allowed = harness.isBoolParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(true), bytes32(uint256(1))
        );

        assertTrue(allowed, "canonical bool true should pass");
    }

    /// @dev Verifies LPPC-BOOL-2: canonical false word with exact false passes.
    function test_isBoolParameterAllowedByConstraint_exactFalseCanonicalWord_returnsTrue() public view {
        bool allowed = harness.isBoolParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(false), bytes32(uint256(0))
        );

        assertTrue(allowed, "canonical bool false should pass");
    }

    /// @dev Verifies LPPC-BOOL-3: exact mismatch returns false.
    function test_isBoolParameterAllowedByConstraint_exactMismatch_returnsFalse() public view {
        bool allowed = harness.isBoolParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(false), bytes32(uint256(1))
        );

        assertFalse(allowed, "bool exact mismatch should fail");
    }

    /// @dev Verifies LPPC-BOOL-4: non-Exact constraint types return false.
    function test_isBoolParameterAllowedByConstraint_nonExactConstraint_returnsFalse() public view {
        bool allowed = harness.isBoolParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, abi.encode(false), bytes32(uint256(1))
        );

        assertFalse(allowed, "bool supports only Exact");
    }

    /// @dev Verifies LPPC-BOOL-5 desired behavior: non-canonical non-zero words fail closed.
    function test_isBoolParameterAllowedByConstraint_nonCanonicalNonZeroWord_failClosedDesiredBehavior() public view {
        bool allowed = harness.isBoolParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(true), bytes32(uint256(2))
        );

        assertFalse(allowed, "non-canonical non-zero bool words should fail closed");
    }

    /// @dev Verifies LPPC-BOOL-6 desired behavior: malformed comparisonData fails closed with false.
    function test_isBoolParameterAllowedByConstraint_malformedComparisonData_failClosedDesiredBehavior() public {
        try harness.isBoolParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, hex"01", bytes32(uint256(1))
        ) returns (
            bool allowed
        ) {
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
    /// @dev Verifies LPPC-UINT-1: exact match passes and exact mismatch fails.
    function test_isUintParameterAllowedByConstraint_exactMatchAndMismatch() public view {
        bool matchAllowed = harness.isUintParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(uint256(50)), bytes32(uint256(50))
        );
        bool mismatchAllowed = harness.isUintParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(uint256(49)), bytes32(uint256(50))
        );

        assertTrue(matchAllowed, "matching uint exact should pass");
        assertFalse(mismatchAllowed, "mismatched uint exact should fail");
    }

    /// @dev Verifies LPPC-UINT-2: range bounds are inclusive.
    function test_isUintParameterAllowedByConstraint_rangeInclusiveAtBounds() public view {
        bytes memory rangeData = abi.encode(uint256(10), uint256(20));

        bool minAllowed = harness.isUintParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, rangeData, bytes32(uint256(10))
        );
        bool maxAllowed = harness.isUintParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, rangeData, bytes32(uint256(20))
        );

        assertTrue(minAllowed, "range min bound should be inclusive");
        assertTrue(maxAllowed, "range max bound should be inclusive");
    }

    /// @dev Verifies LPPC-UINT-3: out-of-range values fail.
    function test_isUintParameterAllowedByConstraint_outOfRange_returnsFalse() public view {
        bytes memory rangeData = abi.encode(uint256(10), uint256(20));

        bool belowAllowed = harness.isUintParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, rangeData, bytes32(uint256(9))
        );
        bool aboveAllowed = harness.isUintParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, rangeData, bytes32(uint256(21))
        );

        assertFalse(belowAllowed, "below-range value should fail");
        assertFalse(aboveAllowed, "above-range value should fail");
    }

    /// @dev Verifies LPPC-UINT-4: min>max range fails closed with false.
    function test_isUintParameterAllowedByConstraint_rangeMinGreaterThanMax_returnsFalse() public view {
        bool allowed = harness.isUintParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, abi.encode(uint256(20), uint256(10)), bytes32(uint256(15))
        );

        assertFalse(allowed, "range min>max should fail closed");
    }

    /// @dev Verifies LPPC-UINT-5: unsupported OneOf returns false.
    function test_isUintParameterAllowedByConstraint_oneOfUnsupported_returnsFalse() public view {
        bool allowed = harness.isUintParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.OneOf, abi.encode(bytes32(uint256(1))), bytes32(uint256(1))
        );

        assertFalse(allowed, "uint does not support OneOf");
    }

    /// @dev Verifies LPPC-UINT-6 desired behavior: malformed comparisonData fails closed with false.
    function test_isUintParameterAllowedByConstraint_malformedComparisonData_failClosedDesiredBehavior() public {
        try harness.isUintParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, hex"01", bytes32(uint256(1))
        ) returns (
            bool allowed
        ) {
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
    /// @dev Verifies LPPC-INT-1: exact matches for positive and negative values pass.
    function test_isIntParameterAllowedByConstraint_exactPositiveAndNegativeMatch_returnsTrue() public view {
        bool positiveAllowed = harness.isIntParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(int256(7)), bytes32(uint256(7))
        );
        bool negativeAllowed = harness.isIntParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(int256(-7)), bytes32(uint256(int256(-7)))
        );

        assertTrue(positiveAllowed, "positive exact match should pass");
        assertTrue(negativeAllowed, "negative exact match should pass");
    }

    /// @dev Verifies LPPC-INT-2: exact mismatch fails.
    function test_isIntParameterAllowedByConstraint_exactMismatch_returnsFalse() public view {
        bool allowed = harness.isIntParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(int256(-3)), bytes32(uint256(int256(-2)))
        );

        assertFalse(allowed, "signed exact mismatch should fail");
    }

    /// @dev Verifies LPPC-INT-3: signed ranges are inclusive across negative/positive windows.
    function test_isIntParameterAllowedByConstraint_rangeInclusiveAcrossSignedWindow() public view {
        bytes memory rangeData = abi.encode(int256(-5), int256(5));

        bool minAllowed = harness.isIntParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, rangeData, bytes32(uint256(int256(-5)))
        );
        bool maxAllowed = harness.isIntParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, rangeData, bytes32(uint256(int256(5)))
        );

        assertTrue(minAllowed, "signed min bound should be inclusive");
        assertTrue(maxAllowed, "signed max bound should be inclusive");
    }

    /// @dev Verifies LPPC-INT-4: out-of-range signed values fail.
    function test_isIntParameterAllowedByConstraint_outOfRange_returnsFalse() public view {
        bytes memory rangeData = abi.encode(int256(-5), int256(5));

        bool belowAllowed = harness.isIntParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, rangeData, bytes32(uint256(int256(-6)))
        );
        bool aboveAllowed = harness.isIntParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, rangeData, bytes32(uint256(int256(6)))
        );

        assertFalse(belowAllowed, "signed value below min should fail");
        assertFalse(aboveAllowed, "signed value above max should fail");
    }

    /// @dev Verifies LPPC-INT-5: min>max signed range fails closed.
    function test_isIntParameterAllowedByConstraint_rangeMinGreaterThanMax_returnsFalse() public view {
        bool allowed = harness.isIntParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, abi.encode(int256(5), int256(-5)), bytes32(uint256(int256(0)))
        );

        assertFalse(allowed, "signed range min>max should fail closed");
    }

    /// @dev Verifies LPPC-INT-6: unsupported OneOf for int returns false.
    function test_isIntParameterAllowedByConstraint_oneOfUnsupported_returnsFalse() public view {
        bool allowed = harness.isIntParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.OneOf, abi.encode(bytes32(uint256(1))), bytes32(uint256(int256(1)))
        );

        assertFalse(allowed, "int does not support OneOf");
    }

    /// @dev Verifies LPPC-INT-7 desired behavior: malformed comparisonData fails closed with false.
    function test_isIntParameterAllowedByConstraint_malformedComparisonData_failClosedDesiredBehavior() public {
        try harness.isIntParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, hex"01", bytes32(uint256(int256(1)))
        ) returns (
            bool allowed
        ) {
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
    /// @dev Verifies LPPC-ADDR-1: exact match passes and exact mismatch fails.
    function test_isAddressParameterAllowedByConstraint_exactMatchAndMismatch() public view {
        bool matchAllowed = harness.isAddressParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(reviewer1), _encodeAddressHead(reviewer1), _emptyProof()
        );
        bool mismatchAllowed = harness.isAddressParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(reviewer2), _encodeAddressHead(reviewer1), _emptyProof()
        );

        assertTrue(matchAllowed, "address exact match should pass");
        assertFalse(mismatchAllowed, "address exact mismatch should fail");
    }

    /// @dev Verifies LPPC-ADDR-2: OneOf with valid root/proof returns true.
    function test_isAddressParameterAllowedByConstraint_oneOfValidProof_returnsTrue() public {
        address[] memory values = buildArray(reviewer1, reviewer2, initiator1);
        (bytes32 root, bytes32[] memory proof) = _buildAddressRootAndProof(values, 0);

        bool allowed = harness.isAddressParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.OneOf, abi.encode(root), _encodeAddressHead(reviewer1), proof
        );

        assertTrue(allowed, "valid OneOf proof should pass");
    }

    /// @dev Verifies LPPC-ADDR-3: invalid OneOf proof/root mismatch returns false.
    function test_isAddressParameterAllowedByConstraint_oneOfInvalidProof_returnsFalse() public {
        address[] memory values = buildArray(reviewer1, reviewer2, initiator1);
        (bytes32 root, bytes32[] memory proofForReviewer1) = _buildAddressRootAndProof(values, 0);

        bool allowed = harness.isAddressParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.OneOf, abi.encode(root), _encodeAddressHead(reviewer2), proofForReviewer1
        );

        assertFalse(allowed, "proof for another address should fail");
    }

    /// @dev Verifies LPPC-ADDR-4: unsupported Range returns false.
    function test_isAddressParameterAllowedByConstraint_rangeUnsupported_returnsFalse() public view {
        bool allowed = harness.isAddressParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, abi.encode(reviewer1), _encodeAddressHead(reviewer1), _emptyProof()
        );

        assertFalse(allowed, "address does not support Range");
    }

    /// @dev Verifies LPPC-ADDR-5: dirty upper 96 bits do not affect lower-160 extracted address.
    function test_isAddressParameterAllowedByConstraint_dirtyUpperBits_doNotChangeAddressExtraction() public view {
        uint256 dirtyPacked = uint256(uint160(reviewer1)) | (uint256(0xBEEFCAFE) << 200);

        bool allowed = harness.isAddressParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(reviewer1), bytes32(dirtyPacked), _emptyProof()
        );

        assertTrue(allowed, "address extraction should ignore dirty upper bits");
    }

    /// @dev Verifies LPPC-ADDR-6 desired behavior: malformed comparisonData fails closed with false.
    function test_isAddressParameterAllowedByConstraint_malformedComparisonData_failClosedDesiredBehavior() public {
        try harness.isAddressParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, hex"01", _encodeAddressHead(reviewer1), _emptyProof()
        ) returns (
            bool allowed
        ) {
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
    /// @dev Verifies LPPC-FBYTES-1: exact bytes32 match passes and mismatch fails.
    function test_isFixedBytesParameterAllowedByConstraint_exactMatchAndMismatch() public view {
        bytes32 expected = keccak256("fixed-bytes");

        bool matchAllowed = harness.isFixedBytesParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(expected), expected
        );
        bool mismatchAllowed = harness.isFixedBytesParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(expected), bytes32(uint256(expected) + 1)
        );

        assertTrue(matchAllowed, "matching bytes32 should pass");
        assertFalse(mismatchAllowed, "mismatching bytes32 should fail");
    }

    /// @dev Verifies LPPC-FBYTES-2: bytes1..bytes31 comparisons use ABI left-aligned semantics.
    function test_isFixedBytesParameterAllowedByConstraint_leftAlignedSemanticsForShorterFixedBytes() public view {
        bytes4 value = 0x11223344;
        bytes32 leftAligned = bytes32(value);
        bytes32 rightAligned = bytes32(uint256(uint32(value)));

        bool leftAlignedAllowed = harness.isFixedBytesParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(leftAligned), leftAligned
        );
        bool rightAlignedAllowed = harness.isFixedBytesParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(leftAligned), rightAligned
        );

        assertTrue(leftAlignedAllowed, "left-aligned ABI representation should match");
        assertFalse(rightAlignedAllowed, "right-aligned representation should not match");
    }

    /// @dev Verifies LPPC-FBYTES-3: non-Exact constraints return false.
    function test_isFixedBytesParameterAllowedByConstraint_nonExactConstraint_returnsFalse() public view {
        bool allowed = harness.isFixedBytesParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, abi.encode(bytes32(uint256(1))), bytes32(uint256(1))
        );

        assertFalse(allowed, "fixed bytes supports only Exact");
    }

    /// @dev Verifies LPPC-FBYTES-4 desired behavior: malformed comparisonData fails closed with false.
    function test_isFixedBytesParameterAllowedByConstraint_malformedComparisonData_failClosedDesiredBehavior() public {
        try harness.isFixedBytesParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, hex"01", bytes32(uint256(1))
        ) returns (
            bool allowed
        ) {
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
    /// @dev Verifies LPPC-BYSTR-1: dynamic bytes exact hash matching works.
    function test_isBytesOrStringParameterAllowedByConstraint_dynamicBytesHashMatchAndMismatch() public view {
        bytes memory expectedBytes = hex"CAFEBABE";
        bytes memory data = _encodeSingleBytesArg(expectedBytes);

        bool matchAllowed = harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(keccak256(expectedBytes)), bytes32(uint256(32)), data
        );
        bool mismatchAllowed = harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(keccak256(bytes("different"))), bytes32(uint256(32)), data
        );

        assertTrue(matchAllowed, "matching dynamic-bytes hash should pass");
        assertFalse(mismatchAllowed, "mismatching dynamic-bytes hash should fail");
    }

    /// @dev Verifies LPPC-BYSTR-2: string exact hash matching works.
    function test_isBytesOrStringParameterAllowedByConstraint_stringHashMatchAndMismatch() public view {
        string memory expectedString = "den-policy";
        bytes memory data = _encodeSingleStringArg(expectedString);

        bool matchAllowed = harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(keccak256(bytes(expectedString))), bytes32(uint256(32)), data
        );
        bool mismatchAllowed = harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(keccak256(bytes("different"))), bytes32(uint256(32)), data
        );

        assertTrue(matchAllowed, "matching string hash should pass");
        assertFalse(mismatchAllowed, "mismatching string hash should fail");
    }

    /// @dev Verifies LPPC-BYSTR-3: empty dynamic values are handled correctly.
    function test_isBytesOrStringParameterAllowedByConstraint_emptyDynamicValue_returnsTrueForMatchingEmptyHash()
        public
        view
    {
        bytes memory emptyBytes = bytes("");
        bytes memory data = _encodeSingleBytesArg(emptyBytes);

        bool allowed = harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(keccak256(emptyBytes)), bytes32(uint256(32)), data
        );

        assertTrue(allowed, "empty dynamic value should hash/compare correctly");
    }

    /// @dev Verifies LPPC-BYSTR-4: large dynamic values are parsed and hashed correctly.
    function test_isBytesOrStringParameterAllowedByConstraint_largeDynamicValue_returnsTrue() public view {
        bytes memory largeValue = new bytes(1024);
        for (uint256 i = 0; i < largeValue.length; ++i) {
            largeValue[i] = bytes1(uint8(i));
        }

        bytes memory data = _encodeSingleBytesArg(largeValue);

        bool allowed = harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(keccak256(largeValue)), bytes32(uint256(32)), data
        );

        assertTrue(allowed, "large dynamic values should hash/compare correctly");
    }

    /// @dev Verifies LPPC-BYSTR-5: offsets beyond calldata length return false.
    function test_isBytesOrStringParameterAllowedByConstraint_offsetBeyondCalldata_returnsFalse() public view {
        bytes memory data = _encodeSingleBytesArg(bytes("abc"));

        bool allowed = harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(keccak256(bytes("abc"))), bytes32(uint256(9999)), data
        );

        assertFalse(allowed, "offset beyond calldata should fail");
    }

    /// @dev Verifies LPPC-BYSTR-6: declared lengths extending beyond calldata return false.
    function test_isBytesOrStringParameterAllowedByConstraint_declaredLengthBeyondCalldata_returnsFalse() public view {
        // Selector + head(offset=32) + length(100), but no payload bytes for the declared length.
        bytes memory malformedData = bytes.concat(BASE_SELECTOR, abi.encode(uint256(32), uint256(100)));

        bool allowed = harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(keccak256(bytes("unused"))), bytes32(uint256(32)), malformedData
        );

        assertFalse(allowed, "length extending beyond calldata should fail");
    }

    /// @dev Verifies LPPC-BYSTR-7: non-Exact constraint types return false.
    function test_isBytesOrStringParameterAllowedByConstraint_nonExactConstraint_returnsFalse() public view {
        bytes memory data = _encodeSingleBytesArg(bytes("abc"));

        bool allowed = harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, abi.encode(keccak256(bytes("abc"))), bytes32(uint256(32)), data
        );

        assertFalse(allowed, "bytes/string supports only Exact");
    }

    /// @dev Verifies LPPC-BYSTR-8 desired behavior: offsets into ABI head region fail closed.
    function test_isBytesOrStringParameterAllowedByConstraint_offsetIntoHeadRegion_failClosedDesiredBehavior()
        public
        view
    {
        bytes memory payload = bytes("abcdefg");
        bytes memory data = _encodeSingleBytesArg(payload);

        // If offset points to the head (offset=0), current implementation reads slot-0 as "length" (=32).
        // Desired behavior is to reject this as invalid instead of accepting head-region reads.
        bytes32 forgedExpectedHash = keccak256(abi.encode(uint256(payload.length)));

        bool allowed = harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(forgedExpectedHash), bytes32(uint256(0)), data
        );

        assertFalse(allowed, "offset into ABI head region should fail closed");
    }

    /// @dev Verifies LPPC-BYSTR-9 desired behavior: offset/length arithmetic overflow fails closed.
    function test_isBytesOrStringParameterAllowedByConstraint_overflowingOffset_failClosedDesiredBehavior() public {
        bytes memory data = _encodeSingleBytesArg(bytes("abc"));

        try harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(keccak256(bytes("abc"))), bytes32(type(uint256).max), data
        ) returns (
            bool allowed
        ) {
            assertFalse(allowed, "overflowing offset should fail closed with false");
        } catch {
            assertTrue(false, "overflowing offset should fail closed with false instead of reverting");
        }
    }

    /// @dev Verifies LPPC-BYSTR-10 desired behavior: malformed comparisonData fails closed with false.
    function test_isBytesOrStringParameterAllowedByConstraint_malformedComparisonData_failClosedDesiredBehavior()
        public
    {
        bytes memory data = _encodeSingleBytesArg(bytes("abc"));

        try harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, hex"01", bytes32(uint256(32)), data
        ) returns (
            bool allowed
        ) {
            assertFalse(allowed, "malformed bytes/string comparisonData should fail closed with false");
        } catch {
            assertTrue(
                false, "malformed bytes/string comparisonData should fail closed with false instead of reverting"
            );
        }
    }
}
