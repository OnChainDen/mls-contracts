// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {PolicyLibrariesSuiteBase} from "test/organization/libraries/policy/PolicyLibrariesSuiteBase.sol";
import {ConstraintType, DestinationType, ParamType, ParameterConstraint, Policy} from "types/PolicyTypes.sol";

/**
 * @dev Unit tests for `LibPolicyContractInteraction` wrappers.
 */
contract LibPolicyContractInteractionTest is PolicyLibrariesSuiteBase {
    /// @dev Verifies that valid destination + valid function proof + valid params returns true.
    function test_isContractInteractionAllowed_validDestinationFunctionAndParams_returnsTrue() public {
        // Setup: configure a valid fixture for valid destination + valid function proof + valid params returns true.
        address target = address(0xC701);
        bytes4 selector = bytes4(keccak256("setValue(uint256)"));
        bytes memory constraints = _encodeUintExactConstraint(7);

        (Policy memory policy, bytes32[] memory functionProof, bytes32[] memory destinationProof) =
            _buildPolicyWithSingleAllowedFunctionAndDestination(target, selector, constraints);

        bytes memory data = abi.encodeWithSelector(selector, uint256(7));

        // Call: execute `isContractInteractionAllowedByPolicyViaPolicyLibrary` with the happy-path payload.
        bool allowed = harness.isContractInteractionAllowedByPolicyViaPolicyLibrary(
            policy, target, 0, data, functionProof, constraints, destinationProof
        );
        // Verify: assert the expected success result and state updates.
        assertTrue(allowed, "valid destination/function/params should pass");
    }

    /// @dev Verifies that destination disallowed returns false.
    function test_isContractInteractionAllowed_destinationDisallowed_returnsFalse() public {
        // Setup: build fixture inputs where destination disallowed returns false should be denied.
        address allowedTarget = address(0xC702);
        address actualTarget = address(0xC7AA);
        bytes4 selector = bytes4(keccak256("setValue(uint256)"));
        bytes memory constraints = _encodeUintExactConstraint(7);

        (Policy memory policy, bytes32[] memory functionProof,) =
            _buildPolicyWithSingleAllowedFunctionAndDestination(allowedTarget, selector, constraints);

        bytes memory data = abi.encodeWithSelector(selector, uint256(7));
        // Call: execute `isContractInteractionAllowedByPolicyViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.isContractInteractionAllowedByPolicyViaPolicyLibrary(
            policy, actualTarget, 0, data, functionProof, constraints, new bytes32[](0)
        );
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "disallowed destination should fail");
    }

    /// @dev Verifies that function disallowed returns false.
    function test_isContractInteractionAllowed_functionDisallowed_returnsFalse() public {
        // Setup: build fixture inputs where function disallowed returns false should be denied.
        address target = address(0xC703);
        bytes4 allowedSelector = bytes4(keccak256("setValue(uint256)"));
        bytes4 actualSelector = bytes4(keccak256("setOther(uint256)"));
        bytes memory constraints = _encodeUintExactConstraint(7);

        (Policy memory policy, bytes32[] memory functionProof, bytes32[] memory destinationProof) =
            _buildPolicyWithSingleAllowedFunctionAndDestination(target, allowedSelector, constraints);

        bytes memory data = abi.encodeWithSelector(actualSelector, uint256(7));
        // Call: execute `isContractInteractionAllowedByPolicyViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.isContractInteractionAllowedByPolicyViaPolicyLibrary(
            policy, target, 0, data, functionProof, constraints, destinationProof
        );
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "selector mismatch should fail function check");
    }

    /// @dev Verifies that parameter constraints mismatch returns false.
    function test_isContractInteractionAllowed_parameterConstraintMismatch_returnsFalse() public {
        // Setup: build fixture inputs where parameter constraints mismatch returns false should be denied.
        address target = address(0xC704);
        bytes4 selector = bytes4(keccak256("setValue(uint256)"));
        bytes memory constraints = _encodeUintExactConstraint(7);

        (Policy memory policy, bytes32[] memory functionProof, bytes32[] memory destinationProof) =
            _buildPolicyWithSingleAllowedFunctionAndDestination(target, selector, constraints);

        bytes memory data = abi.encodeWithSelector(selector, uint256(8));
        // Call: execute `isContractInteractionAllowedByPolicyViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.isContractInteractionAllowedByPolicyViaPolicyLibrary(
            policy, target, 0, data, functionProof, constraints, destinationProof
        );
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "constraint mismatch should fail");
    }

    /// @dev Verifies that `anyFunction == true` bypasses function-proof check but still enforces destination + params.
    function test_isContractInteractionAllowed_anyFunctionBypassesProofStillEnforcesDestinationAndParams() public {
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for `anyFunction == true` bypasses function-proof check but still enforces destination + params.
        address target = address(0xC705);
        bytes4 selector = bytes4(keccak256("setValue(uint256)"));
        bytes memory passingConstraints = _encodeUintExactConstraint(11);
        bytes memory failingConstraints = _encodeUintExactConstraint(12);

        (Policy memory policy,, bytes32[] memory destinationProof) =
            _buildPolicyWithSingleAllowedFunctionAndDestination(target, selector, passingConstraints);
        policy.config.anyFunction = true;

        bytes memory data = abi.encodeWithSelector(selector, uint256(11));

        // Call: run `isContractInteractionAllowedByPolicyViaPolicyLibrary` across the prepared variants.
        bool pass = harness.isContractInteractionAllowedByPolicyViaPolicyLibrary(
            policy, target, 0, data, new bytes32[](0), passingConstraints, destinationProof
        );
        bool fail = harness.isContractInteractionAllowedByPolicyViaPolicyLibrary(
            policy, target, 0, data, new bytes32[](0), failingConstraints, destinationProof
        );

        // Verify: assert each variant returns the expected branch outcome.
        assertTrue(pass, "anyFunction should bypass proof with valid destination/params");
        assertFalse(fail, "anyFunction must still enforce parameter constraints");
    }

    /// @dev Verifies that empty constraints can be valid when function leaf uses empty constraints hash.
    function test_isContractInteractionAllowed_emptyConstraintsValidWhenLeafUsesEmptyHash() public {
        // Setup: configure a valid fixture for empty constraints can be valid when function leaf uses empty constraints hash.
        address target = address(0xC706);
        bytes4 selector = bytes4(keccak256("ping()"));
        bytes memory constraints = bytes("");

        (Policy memory policy, bytes32[] memory functionProof, bytes32[] memory destinationProof) =
            _buildPolicyWithSingleAllowedFunctionAndDestination(target, selector, constraints);

        // Call: execute `isContractInteractionAllowedByPolicyViaPolicyLibrary` with the happy-path payload.
        bool allowed = harness.isContractInteractionAllowedByPolicyViaPolicyLibrary(
            policy, target, 0, abi.encodePacked(selector), functionProof, constraints, destinationProof
        );
        // Verify: assert the expected success result and state updates.
        assertTrue(allowed, "empty constraints should validate when function leaf was built with empty hash");
    }

    /// @dev Verifies that same selector with different constraints hash must not validate with old proof.
    function test_isContractInteractionAllowed_sameSelectorDifferentConstraintsHash_invalidatesProof() public {
        // Setup: build fixture inputs where same selector with different constraints hash must not validate with old proof should be denied.
        address target = address(0xC707);
        bytes4 selector = bytes4(keccak256("setValue(uint256)"));
        bytes memory constraintsA = _encodeUintExactConstraint(33);
        bytes memory constraintsB = _encodeUintExactConstraint(34);

        (Policy memory policy, bytes32[] memory functionProof, bytes32[] memory destinationProof) =
            _buildPolicyWithSingleAllowedFunctionAndDestination(target, selector, constraintsA);

        bytes memory data = abi.encodeWithSelector(selector, uint256(34));
        // Call: execute `isContractInteractionAllowedByPolicyViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.isContractInteractionAllowedByPolicyViaPolicyLibrary(
            policy, target, 0, data, functionProof, constraintsB, destinationProof
        );
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "constraint-hash mismatch should invalidate function proof");
    }

    /// @dev Verifies that data shorter than selector is rejected when function filtering is required.
    function test_isContractInteractionAllowed_dataShorterThanSelector_rejectedWhenFunctionFiltered() public {
        // Setup: build fixture inputs where data shorter than selector is rejected when function filtering is required should be denied.
        Policy memory policy = _buildBasePolicy();
        policy.config.destinationType = DestinationType.Any;
        policy.config.anyFunction = false;

        // Call: execute `isContractInteractionAllowedByPolicyViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.isContractInteractionAllowedByPolicyViaPolicyLibrary(
            policy, address(0xC708), 0, hex"010203", new bytes32[](0), bytes(""), new bytes32[](0)
        );
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "data shorter than selector should fail when anyFunction is false");
    }

    /// @dev Verifies that desired behavior: malformed constraints payload fails closed instead of reverting.
    function test_isContractInteractionAllowed_malformedConstraints_failsClosed_desired() public {
        // Setup: build fixture inputs where desired behavior: malformed constraints payload fails closed instead of reverting should be denied.
        Policy memory policy = _buildBasePolicy();
        policy.config.destinationType = DestinationType.Any;
        policy.config.anyFunction = true;

        // Call: execute `isContractInteractionAllowedByPolicyViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.isContractInteractionAllowedByPolicyViaPolicyLibrary(
            policy,
            address(0xC709),
            0,
            abi.encodePacked(bytes4(keccak256("f()"))),
            new bytes32[](0),
            hex"01",
            new bytes32[](0)
        );
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "desired behavior: malformed constraints should fail closed");
    }

    /// @dev Verifies that `anyFunction == true` returns true regardless of data/proof.
    function test_isFunctionAllowed_anyFunctionTrue_returnsTrue() public {
        // Setup: configure a valid fixture for `anyFunction == true` returns true regardless of data/proof.
        Policy memory policy = _buildBasePolicy();
        policy.config.anyFunction = true;

        // Call: execute `isFunctionAllowedByPolicyViaPolicyLibrary` with the happy-path payload.
        bool allowed = harness.isFunctionAllowedByPolicyViaPolicyLibrary(policy, hex"", new bytes32[](0), hex"1234");
        // Verify: assert the expected success result and state updates.
        assertTrue(allowed, "anyFunction should bypass function proof checks");
    }

    /// @dev Verifies that `anyFunction == false` and `data.length < 4` returns false.
    function test_isFunctionAllowed_anyFunctionFalseAndShortData_returnsFalse() public {
        // Setup: build fixture inputs where `anyFunction == false` and `data.length < 4` returns false should be denied.
        Policy memory policy = _buildBasePolicy();
        policy.config.anyFunction = false;

        // Call: execute `isFunctionAllowedByPolicyViaPolicyLibrary` and capture the authorization decision.
        bool allowed =
            harness.isFunctionAllowedByPolicyViaPolicyLibrary(policy, hex"010203", new bytes32[](0), bytes(""));
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "short data should fail when anyFunction is false");
    }

    /// @dev Verifies that valid (selector, constraintsHash) proof returns true.
    function test_isFunctionAllowed_validFunctionProof_returnsTrue() public {
        // Setup: configure a valid fixture for valid (selector, constraintsHash) proof returns true.
        bytes4 selector = bytes4(keccak256("setValue(uint256)"));
        bytes memory constraints = _encodeUintExactConstraint(55);
        Policy memory policy = _buildBasePolicy();
        policy.config.anyFunction = false;

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = selector;
        bytes[] memory constraintsList = new bytes[](1);
        constraintsList[0] = constraints;
        bytes32[] memory proof;
        (policy.roots.allowedFunctionsRoot, proof) = _buildFunctionRootAndProof(selectors, constraintsList, 0);

        // Call: execute `isFunctionAllowedByPolicyViaPolicyLibrary` with the happy-path payload.
        bool allowed = harness.isFunctionAllowedByPolicyViaPolicyLibrary(
            policy, abi.encodeWithSelector(selector, uint256(55)), proof, constraints
        );
        // Verify: assert the expected success result and state updates.
        assertTrue(allowed, "valid function proof should pass");
    }

    /// @dev Verifies that invalid function proof returns false.
    function test_isFunctionAllowed_invalidFunctionProof_returnsFalse() public {
        // Setup: build fixture inputs where invalid function proof returns false should be denied.
        bytes4 selector = bytes4(keccak256("setValue(uint256)"));
        bytes memory constraints = _encodeUintExactConstraint(56);
        Policy memory policy = _buildBasePolicy();
        policy.config.anyFunction = false;

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = selector;
        selectors[1] = bytes4(keccak256("setOther(uint256)"));
        bytes[] memory constraintsList = new bytes[](2);
        constraintsList[0] = constraints;
        constraintsList[1] = constraints;
        bytes32[] memory wrongProof;
        (policy.roots.allowedFunctionsRoot, wrongProof) = _buildFunctionRootAndProof(selectors, constraintsList, 1);

        // Call: execute `isFunctionAllowedByPolicyViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.isFunctionAllowedByPolicyViaPolicyLibrary(
            policy, abi.encodeWithSelector(selector, uint256(56)), wrongProof, constraints
        );
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "invalid function proof should fail");
    }

    /// @dev Verifies that selector tampering invalidates previously valid proof.
    function test_isFunctionAllowed_selectorTampering_invalidatesProof() public {
        // Setup: build fixture inputs where selector tampering invalidates previously valid proof should be denied.
        bytes4 selectorA = bytes4(keccak256("setValue(uint256)"));
        bytes4 selectorB = bytes4(keccak256("setOther(uint256)"));
        bytes memory constraints = _encodeUintExactConstraint(57);
        Policy memory policy = _buildBasePolicy();
        policy.config.anyFunction = false;

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = selectorA;
        bytes[] memory constraintsList = new bytes[](1);
        constraintsList[0] = constraints;
        bytes32[] memory proof;
        (policy.roots.allowedFunctionsRoot, proof) = _buildFunctionRootAndProof(selectors, constraintsList, 0);

        // Call: execute `isFunctionAllowedByPolicyViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.isFunctionAllowedByPolicyViaPolicyLibrary(
            policy, abi.encodeWithSelector(selectorB, uint256(57)), proof, constraints
        );
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "selector tampering should invalidate proof");
    }

    /// @dev Verifies that constraints tampering invalidates proof via changed constraints hash.
    function test_isFunctionAllowed_constraintsTampering_invalidatesProof() public {
        // Setup: build fixture inputs where constraints tampering invalidates proof via changed constraints hash should be denied.
        bytes4 selector = bytes4(keccak256("setValue(uint256)"));
        bytes memory constraintsA = _encodeUintExactConstraint(58);
        bytes memory constraintsB = _encodeUintExactConstraint(59);
        Policy memory policy = _buildBasePolicy();
        policy.config.anyFunction = false;

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = selector;
        bytes[] memory constraintsList = new bytes[](1);
        constraintsList[0] = constraintsA;
        bytes32[] memory proof;
        (policy.roots.allowedFunctionsRoot, proof) = _buildFunctionRootAndProof(selectors, constraintsList, 0);

        // Call: execute `isFunctionAllowedByPolicyViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.isFunctionAllowedByPolicyViaPolicyLibrary(
            policy, abi.encodeWithSelector(selector, uint256(59)), proof, constraintsB
        );
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "constraints hash tampering should invalidate proof");
    }

    /// @dev Verifies that golden vector for known selector/hash produces expected leaf.
    function test_computeFunctionLeaf_goldenVector_matchesExpectedDoubleHash() public {
        // Setup: configure a valid fixture for golden vector for known selector/hash produces expected leaf.
        bytes4 selector = 0x11223344;
        bytes32 constraintsHash = keccak256("golden-constraints");

        bytes32 expected = keccak256(bytes.concat(keccak256(abi.encode(selector, constraintsHash))));
        // Call: execute `computeFunctionLeafViaPolicyLibrary` with the happy-path payload.
        bytes32 actual = harness.computeFunctionLeafViaPolicyLibrary(selector, constraintsHash);

        // Verify: assert the expected success result and state updates.
        assertEq(actual, expected, "function leaf should match golden vector");
    }

    /// @dev Verifies that deterministic for identical inputs.
    function test_computeFunctionLeaf_identicalInputs_deterministic() public {
        // Setup: configure a valid fixture for deterministic for identical inputs.
        bytes4 selector = 0xABCD1234;
        bytes32 constraintsHash = keccak256("same-inputs");

        // Call: execute `computeFunctionLeafViaPolicyLibrary` with the happy-path payload.
        bytes32 first = harness.computeFunctionLeafViaPolicyLibrary(selector, constraintsHash);
        bytes32 second = harness.computeFunctionLeafViaPolicyLibrary(selector, constraintsHash);

        // Verify: assert the expected success result and state updates.
        assertEq(first, second, "leaf computation must be deterministic");
    }

    /// @dev Verifies that changing selector or constraintsHash changes leaf.
    function test_computeFunctionLeaf_changingInputs_changesLeaf() public {
        // Setup: configure a valid fixture for changing selector or constraintsHash changes leaf.
        // Call: execute `computeFunctionLeafViaPolicyLibrary` with the happy-path payload.
        bytes32 base = harness.computeFunctionLeafViaPolicyLibrary(0xAAAABBBB, keccak256("base"));
        bytes32 changedSelector = harness.computeFunctionLeafViaPolicyLibrary(0xAAAABBBC, keccak256("base"));
        bytes32 changedHash = harness.computeFunctionLeafViaPolicyLibrary(0xAAAABBBB, keccak256("changed"));

        // Verify: assert the expected success result and state updates.
        assertTrue(base != changedSelector, "selector change should change leaf");
        assertTrue(base != changedHash, "constraints hash change should change leaf");
    }

    /// @dev Verifies that leaf uses double-hash construction, not single-hash variant.
    function test_computeFunctionLeaf_notSingleHashVariant() public {
        // Setup: configure a valid fixture for leaf uses double-hash construction, not single-hash variant.
        bytes4 selector = 0x01020304;
        bytes32 constraintsHash = keccak256("double-hash-check");

        // Call: execute `computeFunctionLeafViaPolicyLibrary` with the happy-path payload.
        bytes32 actual = harness.computeFunctionLeafViaPolicyLibrary(selector, constraintsHash);
        bytes32 singleHash = keccak256(abi.encode(selector, constraintsHash));

        // Verify: assert the expected success result and state updates.
        assertTrue(actual != singleHash, "function leaf must use double hash");
    }

    function _buildPolicyWithSingleAllowedFunctionAndDestination(
        address destination,
        bytes4 selector,
        bytes memory constraints
    ) internal returns (Policy memory policy, bytes32[] memory functionProof, bytes32[] memory destinationProof) {
        policy = _buildBasePolicy();
        policy.config.destinationType = DestinationType.CustomList;
        policy.config.anyFunction = false;

        address[] memory destinations = buildArray(destination);
        (policy.roots.customDestinationsRoot, destinationProof) = _buildAddressRootAndProof(destinations, 0);

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = selector;
        bytes[] memory constraintsList = new bytes[](1);
        constraintsList[0] = constraints;
        (policy.roots.allowedFunctionsRoot, functionProof) = _buildFunctionRootAndProof(selectors, constraintsList, 0);
    }

    function _encodeUintExactConstraint(uint256 expectedValue) internal pure returns (bytes memory) {
        ParameterConstraint memory constraint = ParameterConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(expectedValue),
            paramValueInListProof: new bytes32[](0)
        });

        ParameterConstraint[] memory constraints = new ParameterConstraint[](1);
        constraints[0] = constraint;
        return abi.encode(constraints);
    }
}
