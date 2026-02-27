// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibPolicyParameterConstraintsSuiteBase
} from "test/organization/libraries/policy/LibPolicyParameterConstraints/LibPolicyParameterConstraintsSuiteBase.sol";
import {ConstraintType, ParamType, ParameterConstraint} from "types/PolicyTypes.sol";

/**
 * @dev Section 8.9 tests for `_isBytesOrStringParameterAllowedByConstraint`.
 */
contract LibPolicyParameterConstraintsBytesStringConstraintTest is LibPolicyParameterConstraintsSuiteBase {
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
            // casting to `uint8` is safe because the fixture intentionally repeats a 0..255 byte pattern.
            // forge-lint: disable-next-line(unsafe-typecast)
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
