// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {PolicyLibrariesFuzzTestBase} from "test/organization/libraries/policy/PolicyLibrariesFuzzTestBase.sol";
import {DestinationType, Policy} from "types/PolicyTypes.sol";

/**
 * @dev Fuzz tests for `LibPolicyContractInteraction`.
 */
contract LibPolicyContractInteractionFuzzTest is PolicyLibrariesFuzzTestBase {
    /// @dev Verifies the contract-call value threshold is enforced as an inclusive `<=` bound.
    /// @param rawThreshold Fuzzed threshold constrained below `type(uint256).max` so an above-threshold case exists.
    /// @param rawAllowedValue Fuzzed value bounded into the allowed `[0, threshold]` range.
    function testFuzz_isContractInteractionAllowed_valueThresholdIsInclusive(
        uint256 rawThreshold,
        uint256 rawAllowedValue
    ) public {
        // Setup: configure a contract-interaction policy whose other checks are fully open.
        vm.assume(rawThreshold < type(uint256).max);
        Policy memory policy = _buildBasePolicy();
        policy.config.destinationType = DestinationType.Any;
        policy.config.anyFunction = true;
        policy.config.valueThresholdForContractCalls = rawThreshold;

        uint256 allowedValue = bound(rawAllowedValue, 0, rawThreshold);
        uint256 disallowedValue = rawThreshold + 1;
        bytes memory data = abi.encodePacked(bytes4(keccak256("f()")));

        // Call: evaluate one value at/below threshold and one value strictly above threshold.
        bool allowed = harness.isContractInteractionAllowedByPolicyViaPolicyLibrary(
            policy, address(0xCA11), allowedValue, data, new bytes32[](0), bytes(""), new bytes32[](0)
        );
        bool disallowed = harness.isContractInteractionAllowedByPolicyViaPolicyLibrary(
            policy, address(0xCA11), disallowedValue, data, new bytes32[](0), bytes(""), new bytes32[](0)
        );

        // Verify: only the value that stays within the configured threshold should pass.
        assertTrue(allowed, "allowed value should satisfy the inclusive threshold");
        assertFalse(disallowed, "value above threshold should fail");
    }

    /// @dev Verifies `LibPolicyContractInteraction._isFunctionAllowedByPolicy` bypasses proof validation when
    /// `anyFunction` is enabled.
    /// @param data Arbitrary calldata supplied to the function filter.
    /// @param functionProof Arbitrary merkle proof bytes.
    /// @param constraints Arbitrary constraints payload.
    function testFuzz_isFunctionAllowed_anyFunctionBypassesProofRequirements(
        bytes memory data,
        bytes32[] memory functionProof,
        bytes memory constraints
    ) public view {
        // Setup: configure a policy that explicitly enables the `anyFunction` bypass branch.
        Policy memory policy = _buildBasePolicy();
        policy.config.anyFunction = true;

        // Call: evaluate the function filter against arbitrary calldata, proof, and constraints.
        bool allowed = harness.isFunctionAllowedByPolicyViaPolicyLibrary(policy, data, functionProof, constraints);

        // Verify: `anyFunction` should bypass function membership checks entirely.
        assertTrue(allowed, "anyFunction should bypass function proof validation");
    }

    /// @dev Verifies `LibPolicyContractInteraction._isFunctionAllowedByPolicy` binds membership to both the selector
    /// and `keccak256(constraints)`.
    /// @param selector The allowed selector inserted into the merkle tree.
    /// @param differentSelector A selector used for the mutation branch.
    /// @param constraints The allowed constraints payload inserted into the merkle tree.
    /// @param differentConstraints The mutated constraints payload used for the negative branch.
    function testFuzz_isFunctionAllowed_bindsSelectorAndConstraintsHashExactly(
        bytes4 selector,
        bytes4 differentSelector,
        bytes memory constraints,
        bytes memory differentConstraints
    ) public {
        vm.assume(selector != differentSelector);
        vm.assume(keccak256(constraints) != keccak256(differentConstraints));

        // Setup: build a one-leaf function tree for the exact `(selector, constraintsHash)` pair.
        Policy memory policy = _buildBasePolicy();
        policy.config.anyFunction = false;

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = selector;
        bytes[] memory constraintsList = new bytes[](1);
        constraintsList[0] = constraints;
        bytes32[] memory functionProof;
        (policy.roots.allowedFunctionsRoot, functionProof) = _buildFunctionRootAndProof(selectors, constraintsList, 0);

        bytes memory data = bytes.concat(selector, bytes32(uint256(1)));
        bytes memory wrongSelectorData = bytes.concat(differentSelector, bytes32(uint256(1)));

        // Call: evaluate the exact leaf plus selector-mutation and constraints-hash-mutation branches.
        bool exactAllowed = harness.isFunctionAllowedByPolicyViaPolicyLibrary(policy, data, functionProof, constraints);
        bool wrongSelectorAllowed =
            harness.isFunctionAllowedByPolicyViaPolicyLibrary(policy, wrongSelectorData, functionProof, constraints);
        bool wrongConstraintsAllowed =
            harness.isFunctionAllowedByPolicyViaPolicyLibrary(policy, data, functionProof, differentConstraints);

        // Verify: only the exact selector and constraints hash accepted by the merkle tree should pass.
        assertTrue(exactAllowed, "exact selector and constraints hash should pass");
        assertFalse(wrongSelectorAllowed, "selector mutation should invalidate the proof");
        assertFalse(wrongConstraintsAllowed, "constraints-hash mutation should invalidate the proof");
    }
}
