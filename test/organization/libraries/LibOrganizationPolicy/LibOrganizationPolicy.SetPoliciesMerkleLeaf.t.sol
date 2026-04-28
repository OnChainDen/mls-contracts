// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationPolicy} from "interfaces/organization/IOrganizationPolicy.sol";
import {
    LibOrganizationPolicySuiteBase
} from "test/organization/libraries/LibOrganizationPolicy/LibOrganizationPolicySuiteBase.sol";
import {Policy} from "types/PolicyTypes.sol";

/**
 * @dev Unit tests for `LibOrganizationPolicy` set/merkle/leaf behavior.
 */
contract LibOrganizationPolicySetPoliciesMerkleLeafTest is LibOrganizationPolicySuiteBase {
    /// @dev Verifies that `setPolicies` writes `policiesRoot` exactly to `newPoliciesRoot`.
    function test_setPolicies_writesPoliciesRootExactly() public {
        // Setup: configure a valid fixture for `setPolicies` writes `policiesRoot` exactly to `newPoliciesRoot`.
        bytes32 newRoot = keccak256("lop-set-1-root");
        // Call: execute `setPoliciesViaLibrary` with the happy-path payload.
        harness.setPoliciesViaLibrary(newRoot, "ipfs://lop-set-1");
        assertEq(harness.getPoliciesRoot(), newRoot, "policies root storage mismatch");
    }

    /// @dev Verifies that `setPolicies` emits `PoliciesUpdated(newPoliciesRoot, ipfsCid)` with exact args.
    function test_setPolicies_emitsPoliciesUpdatedWithExactArgs() public {
        // Setup: configure a valid fixture for `setPolicies` emits `PoliciesUpdated(newPoliciesRoot, ipfsCid)` with
        // exact args.
        bytes32 newRoot = keccak256("lop-set-2-root");
        string memory ipfsCid = "ipfs://lop-set-2";

        vm.expectEmit(true, true, true, true);
        emit IOrganizationPolicy.PoliciesUpdated(newRoot, ipfsCid);
        // Call: execute `setPoliciesViaLibrary` with the happy-path payload.
        harness.setPoliciesViaLibrary(newRoot, ipfsCid);
    }

    /// @dev Verifies that repeated write of same root/CID is idempotent and still emits event.
    function test_setPolicies_repeatedSameRootCid_idempotentAndStillEmits() public {
        // Setup: configure a valid fixture for repeated write of same root/CID is idempotent and still emits event.
        bytes32 newRoot = keccak256("lop-set-3-root");
        string memory ipfsCid = "ipfs://lop-set-3";

        // Call: execute `setPoliciesViaLibrary` with the happy-path payload.
        harness.setPoliciesViaLibrary(newRoot, ipfsCid);
        vm.expectEmit(true, true, true, true);
        emit IOrganizationPolicy.PoliciesUpdated(newRoot, ipfsCid);
        harness.setPoliciesViaLibrary(newRoot, ipfsCid);

        assertEq(harness.getPoliciesRoot(), newRoot, "root should remain unchanged on idempotent write");
    }

    /// @dev Verifies that valid policy + valid proof returns true.
    function test_isPolicyInOrg_validPolicyAndProof_returnsTrue() public {
        // Setup: configure a valid fixture for valid policy + valid proof returns true.
        Policy memory policy = _buildBasePolicy();
        uint256[] memory policyIds = new uint256[](1);
        policyIds[0] = 1001;
        Policy[] memory policies = new Policy[](1);
        policies[0] = policy;

        (bytes32 root, bytes32[] memory proof) = _buildPolicyRootAndProof(policyIds, policies, 0);
        harness.setPoliciesRoot(root);

        // Call: execute `isPolicyInOrgViaLibrary` with the happy-path payload.
        assertTrue(harness.isPolicyInOrgViaLibrary(1001, policy, proof), "valid policy proof should verify");
    }

    /// @dev Verifies that invalid proof returns false.
    function test_isPolicyInOrg_invalidProof_returnsFalse() public {
        // Setup: build fixture inputs where invalid proof returns false should be denied.
        Policy memory policy = _buildBasePolicy();
        uint256[] memory policyIds = new uint256[](1);
        policyIds[0] = 1002;
        Policy[] memory policies = new Policy[](1);
        policies[0] = policy;

        (bytes32 root,) = _buildPolicyRootAndProof(policyIds, policies, 0);
        harness.setPoliciesRoot(root);

        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = keccak256("lop-merkle-2-invalid");
        // Call: execute `isPolicyInOrgViaLibrary` and capture the authorization decision.
        assertFalse(harness.isPolicyInOrgViaLibrary(1002, policy, invalidProof), "invalid proof should fail");
    }

    /// @dev Verifies that wrong `policyId` with otherwise-valid proof returns false.
    function test_isPolicyInOrg_wrongPolicyId_returnsFalse() public {
        // Setup: build fixture inputs where wrong `policyId` with otherwise-valid proof returns false should be denied.
        Policy memory policy = _buildBasePolicy();
        uint256[] memory policyIds = new uint256[](1);
        policyIds[0] = 1003;
        Policy[] memory policies = new Policy[](1);
        policies[0] = policy;

        (bytes32 root, bytes32[] memory proof) = _buildPolicyRootAndProof(policyIds, policies, 0);
        harness.setPoliciesRoot(root);

        // Call: execute `isPolicyInOrgViaLibrary` and capture the authorization decision.
        assertFalse(harness.isPolicyInOrgViaLibrary(1004, policy, proof), "mismatched policyId should fail");
    }

    /// @dev Verifies that changing any policy field invalidates proof.
    function test_isPolicyInOrg_mutatedPolicyField_invalidatesProof() public {
        // Setup: build fixture inputs where changing any policy field invalidates proof should be denied.
        Policy memory originalPolicy = _buildBasePolicy();
        Policy memory mutatedPolicy = _buildBasePolicy();
        mutatedPolicy.config.anySourceAccount = false;

        uint256[] memory policyIds = new uint256[](1);
        policyIds[0] = 1005;
        Policy[] memory policies = new Policy[](1);
        policies[0] = originalPolicy;

        (bytes32 root, bytes32[] memory proof) = _buildPolicyRootAndProof(policyIds, policies, 0);
        harness.setPoliciesRoot(root);

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(
            // Call: execute `isPolicyInOrgViaLibrary` and capture the authorization decision.
            harness.isPolicyInOrgViaLibrary(1005, mutatedPolicy, proof),
            "mutating policy fields must invalidate proof"
        );
    }

    /// @dev Verifies that empty proof works only for single-leaf tree.
    function test_isPolicyInOrg_emptyProof_onlySingleLeafTreeCasePasses() public {
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for empty proof works only for
        // single-leaf tree.
        Policy memory policy = _buildBasePolicy();

        uint256[] memory oneId = new uint256[](1);
        oneId[0] = 1006;
        Policy[] memory onePolicy = new Policy[](1);
        onePolicy[0] = policy;
        (bytes32 singleRoot,) = _buildPolicyRootAndProof(oneId, onePolicy, 0);
        harness.setPoliciesRoot(singleRoot);
        bytes32[] memory emptyProof = new bytes32[](0);
        // Verify: assert each variant returns the expected branch outcome.
        assertTrue(
            // Call: run `isPolicyInOrgViaLibrary` across the prepared variants.
            harness.isPolicyInOrgViaLibrary(1006, policy, emptyProof),
            "single-leaf root should accept empty proof"
        );

        Policy memory otherPolicy = _buildBasePolicy();
        otherPolicy.config.anyFunction = false;
        uint256[] memory twoIds = new uint256[](2);
        twoIds[0] = 1006;
        twoIds[1] = 1007;
        Policy[] memory twoPolicies = new Policy[](2);
        twoPolicies[0] = policy;
        twoPolicies[1] = otherPolicy;
        (bytes32 twoLeafRoot,) = _buildPolicyRootAndProof(twoIds, twoPolicies, 0);
        harness.setPoliciesRoot(twoLeafRoot);
        assertFalse(
            harness.isPolicyInOrgViaLibrary(1006, policy, emptyProof), "multi-leaf root must reject empty proof"
        );
    }

    /// @dev Verifies that proof order matters (reordered siblings fail).
    function test_isPolicyInOrg_reorderedProofSiblings_failsVerification() public {
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for proof order matters (reordered
        // siblings fail).
        Policy memory policyA = _buildBasePolicy();
        Policy memory policyB = _buildBasePolicy();
        Policy memory policyC = _buildBasePolicy();
        Policy memory policyD = _buildBasePolicy();
        policyB.config.anyFunction = false;
        policyC.config.anySourceAccount = false;
        policyD.config.token.hasAmountThreshold = true;
        policyD.config.token.amountThreshold = 10;

        uint256[] memory ids = new uint256[](4);
        ids[0] = 1008;
        ids[1] = 1009;
        ids[2] = 1010;
        ids[3] = 1011;
        Policy[] memory policies = new Policy[](4);
        policies[0] = policyA;
        policies[1] = policyB;
        policies[2] = policyC;
        policies[3] = policyD;

        (bytes32 root, bytes32[] memory proof) = _buildPolicyRootAndProof(ids, policies, 2);
        harness.setPoliciesRoot(root);
        // Call: run `isPolicyInOrgViaLibrary` across the prepared variants.
        assertTrue(harness.isPolicyInOrgViaLibrary(1010, policyC, proof), "precondition: proof should verify");
        assertGe(proof.length, 2, "proof should contain at least two siblings for reordering check");

        (proof[0], proof[1]) = (proof[1], proof[0]);
        assertFalse(harness.isPolicyInOrgViaLibrary(1010, policyC, proof), "reordered proof should fail");
    }

    /// @dev Verifies that `policiesRoot == 0` fails for normal policies.
    function test_isPolicyInOrg_zeroRoot_returnsFalse() public view {
        // Setup: build fixture inputs where `policiesRoot == 0` fails for normal policies should be denied.
        Policy memory policy = _buildBasePolicy();
        bytes32[] memory proof = new bytes32[](0);
        // Call: execute `isPolicyInOrgViaLibrary` and capture the authorization decision.
        assertFalse(harness.isPolicyInOrgViaLibrary(1012, policy, proof), "zero root must fail for normal policy");
    }

    /// @dev Verifies that deterministic behavior across repeated calls with same inputs.
    function test_isPolicyInOrg_repeatedCalls_sameInputsDeterministic() public {
        // Setup: configure a valid fixture for deterministic behavior across repeated calls with same inputs.
        Policy memory policy = _buildBasePolicy();
        uint256[] memory policyIds = new uint256[](1);
        policyIds[0] = 1013;
        Policy[] memory policies = new Policy[](1);
        policies[0] = policy;
        (bytes32 root, bytes32[] memory proof) = _buildPolicyRootAndProof(policyIds, policies, 0);
        harness.setPoliciesRoot(root);

        // Call: execute `isPolicyInOrgViaLibrary` with the happy-path payload.
        bool first = harness.isPolicyInOrgViaLibrary(1013, policy, proof);
        bool second = harness.isPolicyInOrgViaLibrary(1013, policy, proof);
        // Verify: assert the expected success result and state updates.
        assertEq(first, second, "repeated calls should be deterministic");
        assertTrue(first, "baseline verification should pass");
    }

    /// @dev Verifies that leaf hashing uses double-hash construction.
    function test_isPolicyInOrg_leafHashing_usesDoubleHashConstruction() public {
        // Setup: configure a valid fixture for leaf hashing uses double-hash construction.
        Policy memory policy = _buildBasePolicy();
        uint256 policyId = 1014;

        bytes32 expectedDoubleHashedLeaf = keccak256(bytes.concat(keccak256(abi.encode(policyId, policy))));
        bytes32 singleHashLeaf = keccak256(abi.encode(policyId, policy));
        // Call: execute `computePolicyLeafViaLibrary` with the happy-path payload.
        bytes32 actualLeaf = harness.computePolicyLeafViaLibrary(policyId, policy);

        // Verify: assert the expected success result and state updates.
        assertEq(actualLeaf, expectedDoubleHashedLeaf, "library should use double-hash leaf construction");
        assertTrue(actualLeaf != singleHashLeaf, "leaf should not use single-hash variant");
    }

    /// @dev Verifies that deterministic golden-vector check for policy leaf helper.
    function test_computePolicyLeaf_goldenVector_matchesExpectedFormula() public {
        // Setup: configure a valid fixture for deterministic golden-vector check for policy leaf helper.
        Policy memory policy = _buildBasePolicy();
        uint256 policyId = 2001;

        bytes32 expected = keccak256(bytes.concat(keccak256(abi.encode(policyId, policy))));
        // Call: execute `computePolicyLeafViaLibrary` with the happy-path payload.
        bytes32 actual = harness.computePolicyLeafViaLibrary(policyId, policy);
        // Verify: assert the expected success result and state updates.
        assertEq(actual, expected, "golden vector mismatch");
    }

    /// @dev Verifies that same `(policyId, policy)` always yields same leaf.
    function test_computePolicyLeaf_sameInputs_alwaysSameLeaf() public {
        // Setup: configure a valid fixture for same `(policyId, policy)` always yields same leaf.
        Policy memory policy = _buildBasePolicy();
        uint256 policyId = 2002;

        // Call: execute `computePolicyLeafViaLibrary` with the happy-path payload.
        bytes32 leafA = harness.computePolicyLeafViaLibrary(policyId, policy);
        bytes32 leafB = harness.computePolicyLeafViaLibrary(policyId, policy);
        // Verify: assert the expected success result and state updates.
        assertEq(leafA, leafB, "leaf computation should be deterministic");
    }

    /// @dev Verifies that changing `policyId` or any policy field changes leaf.
    function test_computePolicyLeaf_changingPolicyIdOrField_changesLeaf() public {
        // Setup: configure a valid fixture for changing `policyId` or any policy field changes leaf.
        Policy memory policy = _buildBasePolicy();
        Policy memory mutatedPolicy = _buildBasePolicy();
        mutatedPolicy.config.anyFunction = false;

        // Call: execute `computePolicyLeafViaLibrary` with the happy-path payload.
        bytes32 baseLeaf = harness.computePolicyLeafViaLibrary(2003, policy);
        bytes32 differentIdLeaf = harness.computePolicyLeafViaLibrary(2004, policy);
        bytes32 differentPolicyLeaf = harness.computePolicyLeafViaLibrary(2003, mutatedPolicy);

        // Verify: assert the expected success result and state updates.
        assertTrue(baseLeaf != differentIdLeaf, "policyId must be hash-bound");
        assertTrue(baseLeaf != differentPolicyLeaf, "policy fields must be hash-bound");
    }

    /// @dev Verifies that changing `valueThresholdForContractCalls` changes the policy leaf.
    function test_computePolicyLeaf_valueThresholdForContractCalls_changesLeaf() public {
        // Setup: build two otherwise-identical policies that differ only by the contract-call value threshold.
        Policy memory basePolicy = _buildBasePolicy();
        Policy memory mutatedPolicy = _buildBasePolicy();
        mutatedPolicy.config.valueThresholdForContractCalls = 123;

        // Call: compute leaves for the same policy id under the two threshold variants.
        bytes32 baseLeaf = harness.computePolicyLeafViaLibrary(2006, basePolicy);
        bytes32 mutatedLeaf = harness.computePolicyLeafViaLibrary(2006, mutatedPolicy);

        // Verify: the threshold must be bound into the Merkle leaf.
        assertTrue(baseLeaf != mutatedLeaf, "contract-call value threshold must change the leaf");
    }

    /// @dev Verifies that helper output matches double-hash and differs from single-hash.
    function test_computePolicyLeaf_doubleHashNotSingleHash() public {
        // Setup: configure a valid fixture for helper output matches double-hash and differs from single-hash.
        Policy memory policy = _buildBasePolicy();
        uint256 policyId = 2005;

        // Call: execute `computePolicyLeafViaLibrary` with the happy-path payload.
        bytes32 leaf = harness.computePolicyLeafViaLibrary(policyId, policy);
        // Verify: assert the expected success result and state updates.
        assertEq(leaf, keccak256(bytes.concat(keccak256(abi.encode(policyId, policy)))), "double-hash mismatch");
        assertTrue(leaf != keccak256(abi.encode(policyId, policy)), "single-hash variant should not match");
    }
}
