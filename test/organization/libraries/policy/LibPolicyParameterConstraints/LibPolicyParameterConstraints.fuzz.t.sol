// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibPolicyParameterConstraintsSuiteBase
} from "test/organization/libraries/policy/LibPolicyParameterConstraints/LibPolicyParameterConstraintsSuiteBase.sol";
import {ConstraintType, ParamType, ParameterConstraint} from "types/PolicyTypes.sol";

/**
 * @dev Fuzz tests for `LibPolicyParameterConstraints`.
 */
contract LibPolicyParameterConstraintsFuzzTest is LibPolicyParameterConstraintsSuiteBase {
    /// @dev Verifies `LibPolicyParameterConstraints.areParametersAllowedByConstraints` accepts both empty bytes and
    /// ABI-encoded empty arrays.
    /// @param data Arbitrary calldata supplied to the empty-constraints helper.
    function testFuzz_FLPPC_PARAM_72_areParametersAllowed_emptyConstraintPayloadsAccept(bytes memory data)
        public
        view
    {
        vm.assume(data.length < 256);

        // Setup: prepare both canonical empty-constraints encodings against the same arbitrary calldata.
        ParameterConstraint[] memory emptyConstraints = new ParameterConstraint[](0);

        // Call: evaluate the raw-empty and ABI-empty payload forms.
        bool emptyBytesAllowed = harness.areParametersAllowedByConstraintsViaPolicyLibrary(bytes(""), data);
        bool emptyArrayAllowed =
            harness.areParametersAllowedByConstraintsViaPolicyLibrary(abi.encode(emptyConstraints), data);

        // Verify: both empty encodings should allow the calldata unconditionally.
        assertTrue(emptyBytesAllowed, "empty constraint bytes should allow");
        assertTrue(emptyArrayAllowed, "abi-encoded empty constraint array should allow");
    }

    /// @dev Verifies the supported validator matrix accepts matching values for every supported parameter-kind and
    /// constraint-kind pairing.
    /// @param uintValue The uint value used for exact and range checks.
    /// @param intValue The int value used for exact and range checks.
    /// @param allowedAddress The address used for exact and one-of address checks.
    /// @param boolValue The bool value used for the exact bool check.
    /// @param fixedBytesValue The bytes32 value used for the fixed-bytes exact check.
    /// @param dynamicBytesValue The dynamic bytes value used for the bytes exact check.
    /// @param dynamicStringValue The string value used for the string exact check.
    function testFuzz_FLPPC_VALID_73_supportedConstraintMatrix_acceptsMatchingValues(
        uint256 uintValue,
        int256 intValue,
        address allowedAddress,
        bool boolValue,
        bytes32 fixedBytesValue,
        bytes memory dynamicBytesValue,
        string memory dynamicStringValue
    ) public {
        vm.assume(dynamicBytesValue.length < 128);
        vm.assume(bytes(dynamicStringValue).length < 128);

        // Setup: build matching comparison data, proofs, and calldata fixtures for each supported validator pair.
        address[] memory allowedAddresses = buildArray(allowedAddress);
        (bytes32 root, bytes32[] memory proof) = _buildAddressRootAndProof(allowedAddresses, 0);
        bytes memory bytesData = _encodeSingleBytesArg(dynamicBytesValue);
        bytes memory stringData = _encodeSingleStringArg(dynamicStringValue);
        bytes32 boolHeadValue = boolValue ? bytes32(uint256(1)) : bytes32(0);
        bytes32 intHeadValue = bytes32(uint256(intValue));

        // Call: evaluate one matching example for every supported parameter-kind and constraint-kind combination.
        bool uintExact = harness.isUintParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(uintValue), bytes32(uint256(uintValue))
        );
        bool uintRange = harness.isUintParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, abi.encode(uintValue, uintValue), bytes32(uint256(uintValue))
        );
        bool intExact =
            harness.isIntParameterAllowedByConstraintViaPolicyLibrary(ConstraintType.Exact, abi.encode(intValue), intHeadValue);
        bool intRange = harness.isIntParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, abi.encode(intValue, intValue), intHeadValue
        );
        bool addressExact = harness.isAddressParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(allowedAddress), _encodeAddressHead(allowedAddress), _emptyProof()
        );
        bool addressOneOf = harness.isAddressParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.OneOf, abi.encode(root), _encodeAddressHead(allowedAddress), proof
        );
        bool boolExact =
            harness.isBoolParameterAllowedByConstraintViaPolicyLibrary(ConstraintType.Exact, abi.encode(boolValue), boolHeadValue);
        bool fixedBytesExact = harness.isFixedBytesParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(fixedBytesValue), fixedBytesValue
        );
        bool bytesExact = harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(keccak256(dynamicBytesValue)), bytes32(uint256(32)), bytesData
        );
        bool stringExact = harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(keccak256(bytes(dynamicStringValue))), bytes32(uint256(32)), stringData
        );

        // Verify: every supported validator pair should accept its matching value.
        assertTrue(uintExact, "uint exact should accept matching value");
        assertTrue(uintRange, "uint range should accept matching value");
        assertTrue(intExact, "int exact should accept matching value");
        assertTrue(intRange, "int range should accept matching value");
        assertTrue(addressExact, "address exact should accept matching value");
        assertTrue(addressOneOf, "address one-of should accept valid proof");
        assertTrue(boolExact, "bool exact should accept matching value");
        assertTrue(fixedBytesExact, "fixed-bytes exact should accept matching value");
        assertTrue(bytesExact, "bytes exact should accept matching value");
        assertTrue(stringExact, "string exact should accept matching value");
    }

    /// @dev Verifies unsupported parameter-kind and constraint-kind combinations always fail closed.
    /// @param uintValue The uint value supplied to the unsupported uint-oneOf branch.
    /// @param intValue The int value supplied to the unsupported int-oneOf branch.
    /// @param addressValue The address supplied to the unsupported address-range branch.
    /// @param fixedBytesValue The bytes32 value supplied to the unsupported fixed-bytes-range branch.
    /// @param payload The dynamic bytes payload supplied to the unsupported bytes-range and dispatch branches.
    function testFuzz_FLPPC_VALID_74_unsupportedConstraintMatrix_alwaysFails(
        uint256 uintValue,
        int256 intValue,
        address addressValue,
        bytes32 fixedBytesValue,
        bytes memory payload
    ) public view {
        vm.assume(payload.length < 128);

        // Setup: prepare representative unsupported combinations across direct validators and dispatcher paths.
        bytes memory bytesData = _encodeSingleBytesArg(payload);
        ParameterConstraint memory arrayConstraint = ParameterConstraint({
            paramType: ParamType.Array,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: bytes(""),
            paramValueInListProof: _emptyProof()
        });

        // Call: evaluate unsupported combinations that should all fail closed.
        bool uintOneOf = harness.isUintParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.OneOf, abi.encode(bytes32(uint256(1))), bytes32(uint256(uintValue))
        );
        bool intOneOf = harness.isIntParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.OneOf, abi.encode(bytes32(uint256(1))), bytes32(uint256(intValue))
        );
        bool addressRange = harness.isAddressParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, abi.encode(addressValue, addressValue), _encodeAddressHead(addressValue), _emptyProof()
        );
        bool boolRange =
            harness.isBoolParameterAllowedByConstraintViaPolicyLibrary(ConstraintType.Range, abi.encode(true), bytes32(uint256(1)));
        bool fixedBytesRange = harness.isFixedBytesParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, abi.encode(fixedBytesValue, fixedBytesValue), fixedBytesValue
        );
        bool bytesRange = harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Range, abi.encode(keccak256(payload)), bytes32(uint256(32)), bytesData
        );
        bool arrayExact =
            harness.isParameterAllowedByConstraintViaPolicyLibrary(arrayConstraint, bytes32(uint256(32)), bytesData);

        // Verify: every unsupported combination should return false instead of silently accepting.
        assertFalse(uintOneOf, "uint one-of should fail");
        assertFalse(intOneOf, "int one-of should fail");
        assertFalse(addressRange, "address range should fail");
        assertFalse(boolRange, "bool range should fail");
        assertFalse(fixedBytesRange, "fixed-bytes range should fail");
        assertFalse(bytesRange, "bytes range should fail");
        assertFalse(arrayExact, "array exact dispatch should fail");
    }

    /// @dev Verifies the address `OneOf` path accepts only the exact `(root, proof, value)` tuple.
    /// @param allowedAddress The address included in the merkle tree.
    /// @param siblingAddress The second address included to force a non-empty proof.
    /// @param otherAddress A different address used for mutation branches.
    function testFuzz_FLPPC_ONEOF_75_isAddressParameterAllowed_validProofPassesMutationsFail(
        address allowedAddress,
        address siblingAddress,
        address otherAddress
    ) public {
        vm.assume(allowedAddress != siblingAddress);
        vm.assume(otherAddress != allowedAddress);
        vm.assume(otherAddress != siblingAddress);

        // Setup: build a two-leaf merkle tree so the validator must consume a real proof.
        address[] memory addresses = buildArray(allowedAddress, siblingAddress);
        (bytes32 root, bytes32[] memory validProof) = _buildAddressRootAndProof(addresses, 0);
        (, bytes32[] memory wrongProof) = _buildAddressRootAndProof(addresses, 1);
        bytes32 wrongRoot = keccak256(abi.encodePacked(root, otherAddress));

        // Call: evaluate the valid proof plus mutated proof, value, and root branches.
        bool validAllowed = harness.isAddressParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.OneOf, abi.encode(root), _encodeAddressHead(allowedAddress), validProof
        );
        bool wrongProofAllowed = harness.isAddressParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.OneOf, abi.encode(root), _encodeAddressHead(allowedAddress), wrongProof
        );
        bool wrongValueAllowed = harness.isAddressParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.OneOf, abi.encode(root), _encodeAddressHead(otherAddress), validProof
        );
        bool wrongRootAllowed = harness.isAddressParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.OneOf, abi.encode(wrongRoot), _encodeAddressHead(allowedAddress), validProof
        );

        // Verify: only the exact merkle root, proof, and address should pass.
        assertTrue(validAllowed, "valid one-of proof should pass");
        assertFalse(wrongProofAllowed, "wrong proof should fail");
        assertFalse(wrongValueAllowed, "wrong value should fail");
        assertFalse(wrongRootAllowed, "wrong root should fail");
    }

    /// @dev Verifies the bytes/string validator returns false when the dynamic offset points beyond calldata.
    /// @param extraOffset The extra distance placed beyond the calldata length.
    /// @param payload The reference payload used to build the calldata fixture.
    function testFuzz_FLPPC_BYTES_76_isBytesOrStringParameterAllowed_offsetBeyondCalldataReturnsFalse(
        uint16 extraOffset,
        bytes memory payload
    ) public view {
        vm.assume(payload.length < 128);

        // Setup: encode a valid bytes argument and then point the offset beyond the end of calldata.
        bytes memory data = _encodeSingleBytesArg(payload);
        uint256 invalidOffset = data.length + bound(uint256(extraOffset), 1, type(uint16).max);

        // Call: evaluate the malformed dynamic offset.
        bool allowed = harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(keccak256(payload)), bytes32(invalidOffset), data
        );

        // Verify: offsets beyond calldata should fail closed with `false`.
        assertFalse(allowed, "offset beyond calldata should fail");
    }

    /// @dev Verifies the bytes/string validator returns false when a declared dynamic length exceeds available bytes.
    /// @param declaredLengthRaw The declared dynamic length.
    /// @param trailingBytesRaw The actual number of trailing bytes left in calldata.
    function testFuzz_FLPPC_BYTES_76_isBytesOrStringParameterAllowed_declaredLengthBeyondCalldataReturnsFalse(
        uint8 declaredLengthRaw,
        uint8 trailingBytesRaw
    ) public view {
        uint256 declaredLength = bound(uint256(declaredLengthRaw), 1, 255);
        uint256 trailingBytes = bound(uint256(trailingBytesRaw), 0, declaredLength - 1);

        // Setup: craft malformed dynamic calldata whose declared length exceeds the available bytes.
        bytes memory malformedData =
            bytes.concat(BASE_SELECTOR, abi.encode(uint256(32), declaredLength), new bytes(trailingBytes));

        // Call: evaluate the malformed dynamic length.
        bool allowed = harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(keccak256(bytes("unused"))), bytes32(uint256(32)), malformedData
        );

        // Verify: short dynamic tails should fail closed with `false`.
        assertFalse(allowed, "declared length beyond calldata should fail");
    }

    /// @dev Verifies the bytes/string validator fails closed instead of reverting when the dynamic offset arithmetic
    /// would overflow.
    /// @param nearMaxDelta The small delta subtracted from `type(uint256).max`.
    function testFuzz_FLPPC_BYTES_76_isBytesOrStringParameterAllowed_overflowingOffsetFailsClosedDesiredBehavior(
        uint8 nearMaxDelta
    ) public {
        uint256 overflowingOffset = type(uint256).max - bound(uint256(nearMaxDelta), 0, 3);

        // Setup: encode a valid bytes payload and replace its dynamic offset with an overflowing value.
        bytes memory data = _encodeSingleBytesArg(bytes("abc"));

        // Call: evaluate the overflowing offset and assert it fails closed instead of reverting.
        try harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(keccak256(bytes("abc"))), bytes32(overflowingOffset), data
        ) returns (bool allowed) {
            // Verify: the overflowing offset should be rejected with `false`.
            assertFalse(allowed, "overflowing offsets should fail closed");
        } catch {
            assertTrue(false, "overflowing offsets should not revert");
        }
    }

    /// @dev Verifies `_processConstraints` terminates without panic across random head-slot counts and calldata sizes.
    /// @param headSlots The declared number of 32-byte head slots for the fuzzed constraint.
    /// @param dataSlots The number of 32-byte words appended after the selector.
    function testFuzz_FLPPC_PROCESS_77_processConstraints_randomOffsetsAndHeadSizesTerminateWithoutPanic(
        uint8 headSlots,
        uint8 dataSlots
    ) public {
        // Setup: build an `Array + Any` constraint so the fuzzed head-slot count flows directly through
        // `_processConstraints`.
        ParameterConstraint memory constraint = ParameterConstraint({
            paramType: ParamType.Array,
            constraintType: ConstraintType.Any,
            paramCalldataHeadSlotCount: headSlots,
            comparisonData: bytes(""),
            paramValueInListProof: _emptyProof()
        });
        bytes memory data = bytes.concat(BASE_SELECTOR, new bytes(uint256(dataSlots) * 32));

        // Call: evaluate the fuzzed shape and capture whether the helper accepted or rejected it.
        try harness.processConstraintsViaPolicyLibrary(_constraints(constraint), data) returns (bool allowed) {
            uint256 requiredHeadBytes = 4 + (uint256(headSlots) * 32);

            // Verify: the helper should return a sensible boolean result without ever panicking.
            if (headSlots == 0 || data.length < requiredHeadBytes) {
                assertFalse(allowed, "misconfigured or truncated heads should fail");
            } else {
                assertTrue(allowed, "sufficient calldata should pass for Array+Any");
            }
        } catch {
            assertTrue(false, "processConstraints should not revert for fuzzed shapes");
        }
    }
}
