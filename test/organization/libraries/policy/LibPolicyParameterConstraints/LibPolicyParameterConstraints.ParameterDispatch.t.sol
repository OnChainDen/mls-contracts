// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibPolicyParameterConstraintsSuiteBase
} from "test/organization/libraries/policy/LibPolicyParameterConstraints/LibPolicyParameterConstraintsSuiteBase.sol";
import {ConstraintType, ParamType, ParameterConstraint} from "types/PolicyTypes.sol";

/**
 * @dev Section 8.3 tests for `_isParameterAllowedByConstraint` dispatcher.
 */
contract LibPolicyParameterConstraintsParameterDispatchTest is LibPolicyParameterConstraintsSuiteBase {
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

    /// @dev Verifies that Any short-circuits and does not decode malformed comparison payloads.
    function test_isParameterAllowedByConstraint_anyShortCircuitsMalformedInputs_returnsTrue() public view {
        // Setup: craft malformed fields that would fail decoding in type-specific paths,
        // then pair them with Any to validate dispatcher short-circuit behavior.
        bytes32[] memory malformedProof = new bytes32[](1);
        malformedProof[0] = keccak256("not-used");
        ParameterConstraint memory anyConstraint = ParameterConstraint({
            paramType: ParamType.Address,
            constraintType: ConstraintType.Any,
            paramCalldataHeadSlotCount: 1,
            comparisonData: hex"01020304",
            paramValueInListProof: malformedProof
        });

        // Call: dispatch with Any using malformed comparison/proof fields.
        bool allowed = harness.isParameterAllowedByConstraintViaPolicyLibrary(
            anyConstraint, bytes32(uint256(1234)), abi.encodeWithSelector(BASE_SELECTOR, reviewer1)
        );

        // Verify: Any should return true before entering type-specific decoding.
        assertTrue(allowed, "Any should ignore malformed type-specific fields");
    }

    /// @dev Verifies that Array and Struct with Any are explicitly accepted by dispatcher.
    function test_isParameterAllowedByConstraint_arrayAndStructWithAny_returnTrue() public view {
        // Setup: build one Array[Any] and one Struct[Any] constraint with placeholder calldata.
        ParameterConstraint memory arrayAny = ParameterConstraint({
            paramType: ParamType.Array,
            constraintType: ConstraintType.Any,
            paramCalldataHeadSlotCount: 1,
            comparisonData: bytes(""),
            paramValueInListProof: _emptyProof()
        });
        ParameterConstraint memory structAny = ParameterConstraint({
            paramType: ParamType.Struct,
            constraintType: ConstraintType.Any,
            paramCalldataHeadSlotCount: 2,
            comparisonData: bytes(""),
            paramValueInListProof: _emptyProof()
        });

        // Call: dispatch both constraints through the generic parameter validator.
        bool arrayAllowed = harness.isParameterAllowedByConstraintViaPolicyLibrary(
            arrayAny, bytes32(uint256(32)), abi.encodeWithSelector(BASE_SELECTOR, uint256(1))
        );
        bool structAllowed = harness.isParameterAllowedByConstraintViaPolicyLibrary(
            structAny, bytes32(uint256(1)), abi.encodeWithSelector(BASE_SELECTOR, uint256(1), uint256(2))
        );

        // Verify: Any should authorize both complex parameter categories.
        assertTrue(arrayAllowed, "Array[Any] should pass");
        assertTrue(structAllowed, "Struct[Any] should pass");
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

    /// @dev Verifies that Address OneOf with malformed root bytes fails closed.
    function test_isParameterAllowedByConstraint_addressOneOfMalformedRoot_returnsFalse() public view {
        // Setup: provide malformed root bytes so Address[OneOf] cannot decode the expected merkle root.
        ParameterConstraint memory malformedRootConstraint = ParameterConstraint({
            paramType: ParamType.Address,
            constraintType: ConstraintType.OneOf,
            paramCalldataHeadSlotCount: 1,
            comparisonData: hex"ABCD",
            paramValueInListProof: _emptyProof()
        });

        // Call: dispatch through Address[OneOf] with malformed root bytes.
        bool allowed = harness.isParameterAllowedByConstraintViaPolicyLibrary(
            malformedRootConstraint, _encodeAddressHead(reviewer1), abi.encodeWithSelector(BASE_SELECTOR, reviewer1)
        );

        // Verify: malformed OneOf root bytes must fail closed.
        assertFalse(allowed, "malformed Address OneOf root should fail");
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
