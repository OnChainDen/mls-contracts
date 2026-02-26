// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibPolicyParameterConstraintsSuiteBase
} from "test/organization/libraries/policy/LibPolicyParameterConstraints/LibPolicyParameterConstraintsSuiteBase.sol";
import {ConstraintType, ParamType, ParameterConstraint} from "types/PolicyTypes.sol";

/**
 * @dev Fuzz tests for section-8 out-of-bounds and robustness behaviors.
 */
contract LibPolicyParameterConstraintsFuzzTest is LibPolicyParameterConstraintsSuiteBase {
    /// @dev Verifies LPPC-PROC-6: fuzzed head-size/data-size combinations never cause OOB reverts.
    function testFuzz_processConstraints_anyConstraint_noOOBReverts(uint8 headSlots, uint8 dataSlots) public {
        ParameterConstraint memory constraint = _buildConstraint({
            paramType: ParamType.Array,
            constraintType: ConstraintType.Any,
            headSlots: headSlots,
            comparisonData: bytes(""),
            paramValueInListProof: _emptyProof()
        });

        bytes memory payload = new bytes(uint256(dataSlots) * 32);
        bytes memory data = bytes.concat(BASE_SELECTOR, payload);

        try harness.processConstraintsViaPolicyLibrary(_constraints(constraint), data) returns (bool allowed) {
            if (headSlots == 0) {
                assertFalse(allowed, "headSlots=0 should fail");
                return;
            }

            uint256 requiredHeadBytes = 4 + (uint256(headSlots) * 32);
            if (data.length < requiredHeadBytes) {
                assertFalse(allowed, "insufficient calldata should fail");
            } else {
                assertTrue(allowed, "sufficient calldata with Any constraint should pass");
            }
        } catch {
            assertTrue(false, "processConstraints should not revert for fuzzed head-size/data-size combinations");
        }
    }

    /// @dev Verifies LPPC-BYSTR-5 via fuzzing: offsets beyond calldata fail with false.
    function testFuzz_isBytesOrStringParameterAllowedByConstraint_offsetBeyondCalldata_returnsFalse(
        uint16 extraOffset,
        bytes memory payload
    ) public view {
        bytes memory data = _encodeSingleBytesArg(payload);
        uint256 boundedExtra = bound(uint256(extraOffset), 1, type(uint16).max);
        uint256 invalidOffset = data.length + boundedExtra;

        bool allowed = harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(keccak256(payload)), bytes32(invalidOffset), data
        );

        assertFalse(allowed, "offset beyond calldata should fail");
    }

    /// @dev Verifies LPPC-BYSTR-6 via fuzzing: declared length beyond available bytes fails with false.
    function testFuzz_isBytesOrStringParameterAllowedByConstraint_declaredLengthBeyondCalldata_returnsFalse(
        uint8 declaredLengthRaw,
        uint8 trailingBytesRaw
    ) public view {
        uint256 declaredLength = bound(uint256(declaredLengthRaw), 1, 255);
        uint256 trailingBytes = bound(uint256(trailingBytesRaw), 0, declaredLength - 1);

        bytes memory truncatedPayload = new bytes(trailingBytes);
        bytes memory malformedData =
            bytes.concat(BASE_SELECTOR, abi.encode(uint256(32), declaredLength), truncatedPayload);

        bool allowed = harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(keccak256(bytes("unused"))), bytes32(uint256(32)), malformedData
        );

        assertFalse(allowed, "declared length beyond available calldata should fail");
    }

    /// @dev Verifies LPPC-BYSTR-9 desired behavior via fuzzing: overflowing offsets fail closed with false.
    function testFuzz_isBytesOrStringParameterAllowedByConstraint_overflowingOffset_failClosedDesiredBehavior(uint8 nearMaxDelta)
        public
    {
        uint256 boundedDelta = bound(uint256(nearMaxDelta), 0, 3);
        uint256 overflowingOffset = type(uint256).max - boundedDelta;
        bytes memory data = _encodeSingleBytesArg(bytes("abc"));

        try harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(keccak256(bytes("abc"))), bytes32(overflowingOffset), data
        ) returns (
            bool allowed
        ) {
            assertFalse(allowed, "overflowing offsets should fail closed with false");
        } catch {
            assertTrue(false, "overflowing offsets should fail closed with false instead of reverting");
        }
    }
}
