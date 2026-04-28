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
contract LibPolicyParameterConstraintsAreParametersAllowedByConstraintsTest is LibPolicyParameterConstraintsSuiteBase {
    /// @dev Verifies that empty `parameterConstraints` bytes returns true.
    function test_areParametersAllowedByConstraints_emptyConstraintsBytes_returnsTrue() public view {
        // Setup: configure a valid fixture for empty `parameterConstraints` bytes returns true.
        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(7));

        // Call: execute `areParametersAllowedByConstraintsViaPolicyLibrary` with the happy-path payload.
        bool allowed = harness.areParametersAllowedByConstraintsViaPolicyLibrary(bytes(""), bytes(""), data);

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
        bool allowed = harness.areParametersAllowedByConstraintsViaPolicyLibrary(encodedConstraints, bytes(""), data);

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
            comparisonData: abi.encode(uint256(42))
        });

        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(42));

        // Call: execute `areParametersAllowedByConstraintsViaPolicyLibrary` with the happy-path payload.
        bool allowed = harness.areParametersAllowedByConstraintsViaPolicyLibrary(
            _encodeSingleConstraint(constraint), bytes(""), data
        );

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
            comparisonData: abi.encode(uint256(11))
        });
        ParameterConstraint memory addressConstraint = ParameterConstraint({
            paramType: ParamType.Address,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(reviewer1)
        });
        ParameterConstraint memory boolConstraint = ParameterConstraint({
            paramType: ParamType.Bool,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(true)
        });

        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(11), reviewer1, true);

        // Call: execute `areParametersAllowedByConstraintsViaPolicyLibrary` with the happy-path payload.
        bool allowed = harness.areParametersAllowedByConstraintsViaPolicyLibrary(
            abi.encode(_constraints(uintConstraint, addressConstraint, boolConstraint)), bytes(""), data
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
            comparisonData: abi.encode(uint256(11))
        });
        ParameterConstraint memory failingConstraint = ParameterConstraint({
            paramType: ParamType.Address,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(reviewer2)
        });

        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(11), reviewer1);

        // Call: execute `areParametersAllowedByConstraintsViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.areParametersAllowedByConstraintsViaPolicyLibrary(
            abi.encode(_constraints(passingConstraint, failingConstraint)), bytes(""), data
        );

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "one failing constraint should cause false");
    }

    /// @dev Verifies malformed encoded constraints revert in the current implementation.
    function test_areParametersAllowedByConstraints_malformedEncodedConstraints_reverts() public {
        // Setup: craft malformed constraints that bypass the short-length guard but contain invalid ABI offsets.
        bytes memory malformedConstraints = abi.encode(uint256(32), uint256(2));
        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(1));

        // Verify: malformed ABI should revert in the current implementation.
        // Note: compiler-generated ABI decoder emits revert(0,0) on bounds-check failure — no error selector.
        vm.expectRevert();
        // Call: execute `areParametersAllowedByConstraintsViaPolicyLibrary` with malformed constraints.
        harness.areParametersAllowedByConstraintsViaPolicyLibrary(malformedConstraints, bytes(""), data);
    }

    /// @dev Verifies that malformed constraints payloads never produce an allow decision.
    function test_areParametersAllowedByConstraints_malformedButLengthGte64_neverReturnsTrue() public {
        // Setup: craft a payload that bypasses the `< 64` pre-check but declares
        // `length=2` without providing any element data.
        bytes memory malformedConstraints = abi.encode(uint256(32), uint256(2));
        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(5));
        bytes memory callData = abi.encodeCall(
            harness.areParametersAllowedByConstraintsViaPolicyLibrary, (malformedConstraints, bytes(""), data)
        );

        // Call: invoke via low-level call so the test accepts either fail-closed `false`
        // or a decode revert for malformed ABI payloads.
        (bool success, bytes memory returnData) = address(harness).call(callData);

        // Verify: malformed payloads must not resolve to `true`.
        if (success) {
            bool allowed = abi.decode(returnData, (bool));
            assertFalse(allowed, "malformed constraints should not allow");
        }
    }

    /// @dev Verifies non-empty `parameterConstraints` payloads shorter than the ABI empty-array header fail closed.
    function test_areParametersAllowedByConstraints_nonEmptyPayloadShorterThanAbiEmptyArray_returnsFalse() public view {
        // Setup: use representative short non-empty payloads that cannot decode as a canonical constraints array.
        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(5));
        bytes memory shortPayloadA = hex"01";
        bytes memory shortPayloadB = new bytes(63);

        // Call: evaluate both undersized payloads through the public library wrapper.
        bool allowedA = harness.areParametersAllowedByConstraintsViaPolicyLibrary(shortPayloadA, bytes(""), data);
        bool allowedB = harness.areParametersAllowedByConstraintsViaPolicyLibrary(shortPayloadB, bytes(""), data);

        // Verify: non-empty payloads below 64 bytes must fail closed without authorizing.
        assertFalse(allowedA, "single-byte constraint payload should fail closed");
        assertFalse(allowedB, "63-byte constraint payload should fail closed");
    }

    /// @dev Verifies that malformed comparisonData in a constraint fails closed with false.
    function test_areParametersAllowedByConstraints_malformedComparisonData_failClosedDesiredBehavior() public {
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for malformed comparisonData in a
        // constraint fails closed with false.
        ParameterConstraint memory malformedConstraint = ParameterConstraint({
            paramType: ParamType.Bool,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: hex"01"
        });

        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, true);

        // Call: run `areParametersAllowedByConstraintsViaPolicyLibrary` across the prepared variants.
        try harness.areParametersAllowedByConstraintsViaPolicyLibrary(
            _encodeSingleConstraint(malformedConstraint), bytes(""), data
        ) returns (
            bool allowed
        ) {
            // Verify: assert each variant returns the expected branch outcome.
            assertFalse(allowed, "malformed comparisonData should fail closed with false");
        } catch {
            assertTrue(false, "malformed comparisonData should fail closed with false instead of reverting");
        }
    }

    /// @dev Verifies that Any constraints ignore malformed comparison bytes and still pass.
    function test_areParametersAllowedByConstraints_anyConstraint_ignoresMalformedComparisonData() public view {
        // Setup: use an Any constraint with intentionally malformed comparisonData to
        // verify the dispatcher short-circuits before type-specific decoding.
        ParameterConstraint memory anyConstraint = ParameterConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Any,
            paramCalldataHeadSlotCount: 1,
            comparisonData: hex"0102"
        });
        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(123));

        // Call: evaluate the malformed Any constraint payload.
        bool allowed = harness.areParametersAllowedByConstraintsViaPolicyLibrary(
            _encodeSingleConstraint(anyConstraint), bytes(""), data
        );

        // Verify: Any constraints should allow regardless of comparisonData contents.
        assertTrue(allowed, "Any constraint should not decode comparisonData");
    }

    /// @dev Verifies that valid constraints remain valid even with extra trailing bytes in the payload.
    function test_areParametersAllowedByConstraints_validConstraintsWithTrailingBytes_returnsTrue() public view {
        // Setup: build a valid encoded constraints blob and append trailing bytes to ensure
        // decoder behavior stays deterministic for canonical prefix-encoded data.
        ParameterConstraint memory constraint = ParameterConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(uint256(77))
        });
        bytes memory encodedConstraints = bytes.concat(_encodeSingleConstraint(constraint), hex"DEADBEEF");
        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(77));

        // Call: evaluate with trailing bytes after the canonical ABI payload.
        bool allowed = harness.areParametersAllowedByConstraintsViaPolicyLibrary(encodedConstraints, bytes(""), data);

        // Verify: the valid canonical constraints payload should still authorize.
        assertTrue(allowed, "trailing bytes should not change canonical decode result");
    }

    /// @dev Verifies that two `Address+OneOf` constraints in one function leaf both validate
    ///      against their own merkle roots when given a compact, traversal-ordered proof array.
    ///      This is the auditor's fix: previously a single function leaf could only carry one
    ///      proof embedded in `ParameterConstraint`, so multi-OneOf constraints were impossible.
    function test_areParametersAllowedByConstraints_multipleOneOfConstraints_succeedsWithCompactProofArray() public {
        // Setup: two distinct allowed-address sets; the function takes two address args.
        address[] memory firstAllowed = buildArray(reviewer1, reviewer2, initiator1);
        address[] memory secondAllowed = buildArray(reviewer3, initiator2);

        (bytes32 firstRoot, bytes32[] memory firstProof) = _buildAddressRootAndProof(firstAllowed, 1);
        (bytes32 secondRoot, bytes32[] memory secondProof) = _buildAddressRootAndProof(secondAllowed, 0);

        ParameterConstraint memory firstOneOf = ParameterConstraint({
            paramType: ParamType.Address,
            constraintType: ConstraintType.OneOf,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(firstRoot)
        });
        ParameterConstraint memory secondOneOf = ParameterConstraint({
            paramType: ParamType.Address,
            constraintType: ConstraintType.OneOf,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(secondRoot)
        });

        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, reviewer2, reviewer3);
        bytes memory encodedConstraints = abi.encode(_constraints(firstOneOf, secondOneOf));
        bytes memory encodedOneOfProofs = _encodeOneOfProofs(_twoOneOfProofs(firstProof, secondProof));

        // Call: validate the two-OneOf-constraint payload through the policy library wrapper.
        bool allowed =
            harness.areParametersAllowedByConstraintsViaPolicyLibrary(encodedConstraints, encodedOneOfProofs, data);

        // Verify: both OneOf constraints validate independently against their own roots.
        assertTrue(allowed, "two address-OneOf constraints should both pass with compact proofs");
    }

    /// @dev Verifies that the same OneOf constraint definition can validate two different
    ///      runtime addresses across separate calls by supplying different inclusion proofs.
    ///      Directly demonstrates the auditor-reported issue is fixed: the function leaf is
    ///      stable across runtime addresses, only the runtime proof changes.
    function test_areParametersAllowedByConstraints_singleOneOfWithDifferentRuntimeAddresses_succeeds() public {
        // Setup: a 3-leaf address tree backing a single Address+OneOf constraint.
        address[] memory allowed = buildArray(reviewer1, reviewer2, initiator1);
        (bytes32 root, bytes32[] memory proofForReviewer1) = _buildAddressRootAndProof(allowed, 0);
        (, bytes32[] memory proofForReviewer2) = _buildAddressRootAndProof(allowed, 1);
        (, bytes32[] memory proofForInitiator1) = _buildAddressRootAndProof(allowed, 2);

        ParameterConstraint memory oneOf = ParameterConstraint({
            paramType: ParamType.Address,
            constraintType: ConstraintType.OneOf,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(root)
        });
        bytes memory encodedConstraints = _encodeSingleConstraint(oneOf);

        // Call: validate three distinct runtime addresses against the same constraint by
        // supplying a different proof each time.
        bool allowed1 = harness.areParametersAllowedByConstraintsViaPolicyLibrary(
            encodedConstraints,
            _encodeOneOfProofs(_singleOneOfProof(proofForReviewer1)),
            abi.encodeWithSelector(BASE_SELECTOR, reviewer1)
        );
        bool allowed2 = harness.areParametersAllowedByConstraintsViaPolicyLibrary(
            encodedConstraints,
            _encodeOneOfProofs(_singleOneOfProof(proofForReviewer2)),
            abi.encodeWithSelector(BASE_SELECTOR, reviewer2)
        );
        bool allowed3 = harness.areParametersAllowedByConstraintsViaPolicyLibrary(
            encodedConstraints,
            _encodeOneOfProofs(_singleOneOfProof(proofForInitiator1)),
            abi.encodeWithSelector(BASE_SELECTOR, initiator1)
        );

        // Verify: all three allowed addresses validate against the same constraint definition.
        assertTrue(allowed1, "reviewer1 must validate against the OneOf root with its own proof");
        assertTrue(allowed2, "reviewer2 must validate against the OneOf root with its own proof");
        assertTrue(allowed3, "initiator1 must validate against the OneOf root with its own proof");
    }

    /// @dev Verifies that an Address+OneOf constraint without any matching proof fails closed.
    function test_areParametersAllowedByConstraints_oneOfConstraintWithoutMatchingProof_failsClosed() public {
        // Setup: one Address+OneOf constraint over a 2-leaf tree but pass empty `constraintOneOfProofs`.
        address[] memory allowed = buildArray(reviewer1, reviewer2);
        (bytes32 root,) = _buildAddressRootAndProof(allowed, 0);

        ParameterConstraint memory oneOf = ParameterConstraint({
            paramType: ParamType.Address,
            constraintType: ConstraintType.OneOf,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(root)
        });

        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, reviewer1);

        // Call: pass an empty constraintOneOfProofs payload (no proofs supplied).
        bool allowedEmpty =
            harness.areParametersAllowedByConstraintsViaPolicyLibrary(_encodeSingleConstraint(oneOf), bytes(""), data);

        // Verify: a missing proof for an Address+OneOf constraint must fail closed.
        assertFalse(allowedEmpty, "missing OneOf proof must fail closed");
    }

    /// @dev Verifies that supplying more proofs than `Address+OneOf` constraints fails closed.
    function test_areParametersAllowedByConstraints_extraProofsBeyondOneOfCount_failsClosed() public {
        // Setup: a single Address+OneOf constraint but pass two proofs in the compact array.
        address[] memory allowed = buildArray(reviewer1, reviewer2);
        (bytes32 root, bytes32[] memory proof) = _buildAddressRootAndProof(allowed, 0);

        ParameterConstraint memory oneOf = ParameterConstraint({
            paramType: ParamType.Address,
            constraintType: ConstraintType.OneOf,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(root)
        });

        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, reviewer1);

        bytes32[] memory secondProof = new bytes32[](1);
        secondProof[0] = bytes32(uint256(0xDEADBEEF));
        bytes memory encodedExtraProofs = _encodeOneOfProofs(_twoOneOfProofs(proof, secondProof));

        // Call: validate with one constraint but two proofs supplied.
        bool result = harness.areParametersAllowedByConstraintsViaPolicyLibrary(
            _encodeSingleConstraint(oneOf), encodedExtraProofs, data
        );

        // Verify: extra (unconsumed) proofs must fail closed so every supplied proof is observably consumed.
        assertFalse(result, "extra proofs beyond OneOf count must fail closed");
    }

    /// @dev Verifies that malformed `constraintOneOfProofs` bytes never authorize.
    function test_areParametersAllowedByConstraints_malformedConstraintOneOfProofsBytes_failsClosed() public {
        // Setup: one Address+OneOf constraint and a deliberately malformed proofs payload.
        address[] memory allowed = buildArray(reviewer1, reviewer2);
        (bytes32 root,) = _buildAddressRootAndProof(allowed, 0);

        ParameterConstraint memory oneOf = ParameterConstraint({
            paramType: ParamType.Address,
            constraintType: ConstraintType.OneOf,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(root)
        });

        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, reviewer1);

        // A length below the 64-byte ABI envelope minimum must fail closed before decode.
        bytes memory shortPayload = hex"01";
        bool resultShort = harness.areParametersAllowedByConstraintsViaPolicyLibrary(
            _encodeSingleConstraint(oneOf), shortPayload, data
        );
        assertFalse(resultShort, "short constraintOneOfProofs payload must fail closed");

        // A 64-byte payload that bypasses the length pre-check but cannot decode as `bytes32[][]`
        // is allowed to either fail closed (`false`) or revert from the compiler's ABI decoder.
        bytes memory malformedPayload = abi.encode(uint256(32), uint256(2));
        bytes memory callData = abi.encodeCall(
            harness.areParametersAllowedByConstraintsViaPolicyLibrary,
            (_encodeSingleConstraint(oneOf), malformedPayload, data)
        );
        (bool success, bytes memory returnData) = address(harness).call(callData);

        // Verify: malformed proofs must never authorize.
        if (success) {
            bool resultDecoded = abi.decode(returnData, (bool));
            assertFalse(resultDecoded, "malformed constraintOneOfProofs must not authorize");
        }
    }

    /// @dev Verifies that passing an empty proofs payload alongside non-OneOf constraints still validates.
    function test_areParametersAllowedByConstraints_oneOfProofsIgnoredForNonOneOfConstraints_succeeds() public view {
        // Setup: a constraints array containing only non-OneOf constraints.
        ParameterConstraint memory uintConstraint = ParameterConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(uint256(123))
        });
        ParameterConstraint memory addrExact = ParameterConstraint({
            paramType: ParamType.Address,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(reviewer1)
        });
        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(123), reviewer1);

        // Call: validate a non-OneOf constraints array with empty constraintOneOfProofs.
        bool allowed = harness.areParametersAllowedByConstraintsViaPolicyLibrary(
            abi.encode(_constraints(uintConstraint, addrExact)), bytes(""), data
        );

        // Verify: empty constraintOneOfProofs is a no-op when the array contains no Address+OneOf constraints.
        assertTrue(allowed, "non-OneOf constraints should validate with empty constraintOneOfProofs");
    }

    /// @dev Verifies that identical inputs produce deterministic output.
    function test_areParametersAllowedByConstraints_deterministicForSameInputs() public view {
        // Setup: configure a valid fixture for identical inputs produce deterministic output.
        ParameterConstraint memory constraint = ParameterConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Range,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(uint256(10), uint256(20))
        });

        bytes memory encodedConstraints = _encodeSingleConstraint(constraint);
        bytes memory data = abi.encodeWithSelector(BASE_SELECTOR, uint256(12));

        // Call: execute `areParametersAllowedByConstraintsViaPolicyLibrary` with the happy-path payload.
        bool first = harness.areParametersAllowedByConstraintsViaPolicyLibrary(encodedConstraints, bytes(""), data);
        bool second = harness.areParametersAllowedByConstraintsViaPolicyLibrary(encodedConstraints, bytes(""), data);

        // Verify: assert the expected success result and state updates.
        assertEq(first, second, "same inputs must produce same result");
    }
}
