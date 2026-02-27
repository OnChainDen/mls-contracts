// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibPolicyParameterConstraintsSuiteBase
} from "test/organization/libraries/policy/LibPolicyParameterConstraints/LibPolicyParameterConstraintsSuiteBase.sol";
import {ConstraintType, ParamType, ParameterConstraint} from "types/PolicyTypes.sol";

/**
 * @dev Section 8.7 tests for `_isAddressParameterAllowedByConstraint`.
 */
contract LibPolicyParameterConstraintsAddressConstraintTest is LibPolicyParameterConstraintsSuiteBase {
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
