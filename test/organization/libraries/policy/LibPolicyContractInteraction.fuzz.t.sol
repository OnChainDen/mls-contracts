// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {PolicyLibrariesFuzzTestBase} from "test/organization/libraries/policy/PolicyLibrariesFuzzTestBase.sol";
import {Policy} from "types/PolicyTypes.sol";

/**
 * @dev Fuzz tests for `LibPolicyContractInteraction`.
 */
contract LibPolicyContractInteractionFuzzTest is PolicyLibrariesFuzzTestBase {
    /// @dev Verifies `LibPolicyContractInteraction._isFunctionAllowedByPolicy` bypasses proof validation when
    /// `anyFunction` is enabled.
    /// @param data Arbitrary calldata supplied to the function filter.
    /// @param functionProof Arbitrary merkle proof bytes.
    /// @param constraints Arbitrary constraints payload.
    function testFuzz_FLPCI_FUNC_69_isFunctionAllowed_anyFunctionBypassesProofRequirements(
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
    function testFuzz_FLPCI_FUNC_70_isFunctionAllowed_bindsSelectorAndConstraintsHashExactly(
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

    /// @dev Verifies `LibPolicyContractInteraction._computeFunctionLeaf` is deterministic, double-hashed, and field
    /// sensitive.
    /// @param selector The selector used in the baseline leaf.
    /// @param differentSelector A selector used to prove selector sensitivity.
    /// @param constraintsHash The constraints hash used in the baseline leaf.
    /// @param differentConstraintsHash A constraints hash used to prove hash sensitivity.
    function testFuzz_FLPCI_FLEAF_71_computeFunctionLeaf_isDeterministicDoubleHashedAndFieldSensitive(
        bytes4 selector,
        bytes4 differentSelector,
        bytes32 constraintsHash,
        bytes32 differentConstraintsHash
    ) public view {
        vm.assume(selector != differentSelector);
        vm.assume(constraintsHash != differentConstraintsHash);

        // Setup: compute the expected double-hash leaf and prepare selector/hash mutations.
        bytes32 expected = keccak256(bytes.concat(keccak256(abi.encode(selector, constraintsHash))));

        // Call: compute the baseline leaf twice plus two single-field mutations.
        bytes32 baseline = harness.computeFunctionLeafViaPolicyLibrary(selector, constraintsHash);
        bytes32 repeated = harness.computeFunctionLeafViaPolicyLibrary(selector, constraintsHash);
        bytes32 selectorMutation = harness.computeFunctionLeafViaPolicyLibrary(differentSelector, constraintsHash);
        bytes32 hashMutation = harness.computeFunctionLeafViaPolicyLibrary(selector, differentConstraintsHash);

        // Verify: the helper matches the double-hash formula, stays deterministic, and changes when either field
        // changes.
        assertEq(baseline, expected, "function leaf should match the double-hash formula");
        assertEq(repeated, baseline, "function leaf should be deterministic");
        assertTrue(baseline != keccak256(abi.encode(selector, constraintsHash)), "single-hash variant should differ");
        assertTrue(selectorMutation != baseline, "selector mutation should change the leaf");
        assertTrue(hashMutation != baseline, "constraints hash mutation should change the leaf");
    }
}
