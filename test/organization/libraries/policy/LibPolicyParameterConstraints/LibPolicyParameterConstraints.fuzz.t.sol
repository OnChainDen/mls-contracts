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
    /// @dev Verifies that fuzzed head-size/data-size combinations never cause OOB reverts.
    function testFuzz_processConstraints_anyConstraint_noOOBReverts(uint8 headSlots, uint8 dataSlots) public {
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for fuzzed head-size/data-size combinations never cause OOB reverts.
        ParameterConstraint memory constraint = _buildConstraint({
            paramType: ParamType.Array,
            constraintType: ConstraintType.Any,
            headSlots: headSlots,
            comparisonData: bytes(""),
            paramValueInListProof: _emptyProof()
        });

        bytes memory payload = new bytes(uint256(dataSlots) * 32);
        bytes memory data = bytes.concat(BASE_SELECTOR, payload);

        // Call: run `processConstraintsViaPolicyLibrary` across the prepared variants.
        try harness.processConstraintsViaPolicyLibrary(_constraints(constraint), data) returns (bool allowed) {
            if (headSlots == 0) {
        // Verify: assert each variant returns the expected branch outcome.
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

    /// @dev Verifies that offsets beyond calldata fail with false.
    function testFuzz_isBytesOrStringParameterAllowedByConstraint_offsetBeyondCalldata_returnsFalse(
        // Setup: build fixture inputs where offsets beyond calldata fail with false should be denied.
        uint16 extraOffset,
        bytes memory payload
    ) public view {
        bytes memory data = _encodeSingleBytesArg(payload);
        uint256 boundedExtra = bound(uint256(extraOffset), 1, type(uint16).max);
        uint256 invalidOffset = data.length + boundedExtra;

        // Call: execute `isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(keccak256(payload)), bytes32(invalidOffset), data
        );

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "offset beyond calldata should fail");
    }

    /// @dev Verifies that declared length beyond available bytes fails with false.
    function testFuzz_isBytesOrStringParameterAllowedByConstraint_declaredLengthBeyondCalldata_returnsFalse(
        // Setup: build fixture inputs where declared length beyond available bytes fails with false should be denied.
        uint8 declaredLengthRaw,
        uint8 trailingBytesRaw
    ) public view {
        uint256 declaredLength = bound(uint256(declaredLengthRaw), 1, 255);
        uint256 trailingBytes = bound(uint256(trailingBytesRaw), 0, declaredLength - 1);

        bytes memory truncatedPayload = new bytes(trailingBytes);
        bytes memory malformedData =
            bytes.concat(BASE_SELECTOR, abi.encode(uint256(32), declaredLength), truncatedPayload);

        // Call: execute `isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(keccak256(bytes("unused"))), bytes32(uint256(32)), malformedData
        );

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "declared length beyond available calldata should fail");
    }

    /// @dev Verifies that overflowing offsets fail closed with false.
    function testFuzz_isBytesOrStringParameterAllowedByConstraint_overflowingOffset_failClosedDesiredBehavior(uint8 nearMaxDelta)
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for overflowing offsets fail closed with false.
        public
    {
        uint256 boundedDelta = bound(uint256(nearMaxDelta), 0, 3);
        uint256 overflowingOffset = type(uint256).max - boundedDelta;
        bytes memory data = _encodeSingleBytesArg(bytes("abc"));

        // Call: run `isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary` across the prepared variants.
        try harness.isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
            ConstraintType.Exact, abi.encode(keccak256(bytes("abc"))), bytes32(overflowingOffset), data
        ) returns (
            bool allowed
        ) {
        // Verify: assert each variant returns the expected branch outcome.
            assertFalse(allowed, "overflowing offsets should fail closed with false");
        } catch {
            assertTrue(false, "overflowing offsets should fail closed with false instead of reverting");
        }
    }
}
