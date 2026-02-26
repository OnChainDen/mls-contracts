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
    /// @dev LOP-SET-1: `setPolicies` writes `policiesRoot` exactly to `newPoliciesRoot`.
    function test_setPolicies_writesPoliciesRootExactly() public {
        bytes32 newRoot = keccak256("lop-set-1-root");
        harness.setPoliciesViaLibrary(newRoot, "ipfs://lop-set-1");
        assertEq(harness.getPoliciesRoot(), newRoot, "policies root storage mismatch");
    }

    /// @dev LOP-SET-2: `setPolicies` emits `PoliciesUpdated(newPoliciesRoot, ipfsCid)` with exact args.
    function test_setPolicies_emitsPoliciesUpdatedWithExactArgs() public {
        bytes32 newRoot = keccak256("lop-set-2-root");
        string memory ipfsCid = "ipfs://lop-set-2";

        vm.expectEmit(true, true, true, true);
        emit IOrganizationPolicy.PoliciesUpdated(newRoot, ipfsCid);
        harness.setPoliciesViaLibrary(newRoot, ipfsCid);
    }

    /// @dev LOP-SET-3: repeated write of same root/CID is idempotent and still emits event.
    function test_setPolicies_repeatedSameRootCid_idempotentAndStillEmits() public {
        bytes32 newRoot = keccak256("lop-set-3-root");
        string memory ipfsCid = "ipfs://lop-set-3";

        harness.setPoliciesViaLibrary(newRoot, ipfsCid);
        vm.expectEmit(true, true, true, true);
        emit IOrganizationPolicy.PoliciesUpdated(newRoot, ipfsCid);
        harness.setPoliciesViaLibrary(newRoot, ipfsCid);

        assertEq(harness.getPoliciesRoot(), newRoot, "root should remain unchanged on idempotent write");
    }

    /// @dev LOP-MERKLE-1: valid policy + valid proof returns true.
    function test_isPolicyInOrg_validPolicyAndProof_returnsTrue() public {
        Policy memory policy = _buildBasePolicy();
        uint256[] memory policyIds = new uint256[](1);
        policyIds[0] = 1001;
        Policy[] memory policies = new Policy[](1);
        policies[0] = policy;

        (bytes32 root, bytes32[] memory proof) = _buildPolicyRootAndProof(policyIds, policies, 0);
        harness.setPoliciesRoot(root);

        assertTrue(harness.isPolicyInOrgViaLibrary(1001, policy, proof), "valid policy proof should verify");
    }

    /// @dev LOP-MERKLE-2: invalid proof returns false.
    function test_isPolicyInOrg_invalidProof_returnsFalse() public {
        Policy memory policy = _buildBasePolicy();
        uint256[] memory policyIds = new uint256[](1);
        policyIds[0] = 1002;
        Policy[] memory policies = new Policy[](1);
        policies[0] = policy;

        (bytes32 root,) = _buildPolicyRootAndProof(policyIds, policies, 0);
        harness.setPoliciesRoot(root);

        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = keccak256("lop-merkle-2-invalid");
        assertFalse(harness.isPolicyInOrgViaLibrary(1002, policy, invalidProof), "invalid proof should fail");
    }

    /// @dev LOP-MERKLE-3: wrong `policyId` with otherwise-valid proof returns false.
    function test_isPolicyInOrg_wrongPolicyId_returnsFalse() public {
        Policy memory policy = _buildBasePolicy();
        uint256[] memory policyIds = new uint256[](1);
        policyIds[0] = 1003;
        Policy[] memory policies = new Policy[](1);
        policies[0] = policy;

        (bytes32 root, bytes32[] memory proof) = _buildPolicyRootAndProof(policyIds, policies, 0);
        harness.setPoliciesRoot(root);

        assertFalse(harness.isPolicyInOrgViaLibrary(1004, policy, proof), "mismatched policyId should fail");
    }

    /// @dev LOP-MERKLE-4: changing any policy field invalidates proof.
    function test_isPolicyInOrg_mutatedPolicyField_invalidatesProof() public {
        Policy memory originalPolicy = _buildBasePolicy();
        Policy memory mutatedPolicy = _buildBasePolicy();
        mutatedPolicy.config.anySourceAccount = false;

        uint256[] memory policyIds = new uint256[](1);
        policyIds[0] = 1005;
        Policy[] memory policies = new Policy[](1);
        policies[0] = originalPolicy;

        (bytes32 root, bytes32[] memory proof) = _buildPolicyRootAndProof(policyIds, policies, 0);
        harness.setPoliciesRoot(root);

        assertFalse(
            harness.isPolicyInOrgViaLibrary(1005, mutatedPolicy, proof), "mutating policy fields must invalidate proof"
        );
    }

    /// @dev LOP-MERKLE-5: empty proof works only for single-leaf tree.
    function test_isPolicyInOrg_emptyProof_onlySingleLeafTreeCasePasses() public {
        Policy memory policy = _buildBasePolicy();

        uint256[] memory oneId = new uint256[](1);
        oneId[0] = 1006;
        Policy[] memory onePolicy = new Policy[](1);
        onePolicy[0] = policy;
        (bytes32 singleRoot,) = _buildPolicyRootAndProof(oneId, onePolicy, 0);
        harness.setPoliciesRoot(singleRoot);
        bytes32[] memory emptyProof = new bytes32[](0);
        assertTrue(
            harness.isPolicyInOrgViaLibrary(1006, policy, emptyProof), "single-leaf root should accept empty proof"
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

    /// @dev LOP-MERKLE-6: proof order matters (reordered siblings fail).
    function test_isPolicyInOrg_reorderedProofSiblings_failsVerification() public {
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
        assertTrue(harness.isPolicyInOrgViaLibrary(1010, policyC, proof), "precondition: proof should verify");
        assertGe(proof.length, 2, "proof should contain at least two siblings for reordering check");

        (proof[0], proof[1]) = (proof[1], proof[0]);
        assertFalse(harness.isPolicyInOrgViaLibrary(1010, policyC, proof), "reordered proof should fail");
    }

    /// @dev LOP-MERKLE-7: `policiesRoot == 0` fails for normal policies.
    function test_isPolicyInOrg_zeroRoot_returnsFalse() public view {
        Policy memory policy = _buildBasePolicy();
        bytes32[] memory proof = new bytes32[](0);
        assertFalse(harness.isPolicyInOrgViaLibrary(1012, policy, proof), "zero root must fail for normal policy");
    }

    /// @dev LOP-MERKLE-8: deterministic behavior across repeated calls with same inputs.
    function test_isPolicyInOrg_repeatedCalls_sameInputsDeterministic() public {
        Policy memory policy = _buildBasePolicy();
        uint256[] memory policyIds = new uint256[](1);
        policyIds[0] = 1013;
        Policy[] memory policies = new Policy[](1);
        policies[0] = policy;
        (bytes32 root, bytes32[] memory proof) = _buildPolicyRootAndProof(policyIds, policies, 0);
        harness.setPoliciesRoot(root);

        bool first = harness.isPolicyInOrgViaLibrary(1013, policy, proof);
        bool second = harness.isPolicyInOrgViaLibrary(1013, policy, proof);
        assertEq(first, second, "repeated calls should be deterministic");
        assertTrue(first, "baseline verification should pass");
    }

    /// @dev LOP-MERKLE-9: leaf hashing uses double-hash construction.
    function test_isPolicyInOrg_leafHashing_usesDoubleHashConstruction() public {
        Policy memory policy = _buildBasePolicy();
        uint256 policyId = 1014;

        bytes32 expectedDoubleHashedLeaf = keccak256(bytes.concat(keccak256(abi.encode(policyId, policy))));
        bytes32 singleHashLeaf = keccak256(abi.encode(policyId, policy));
        bytes32 actualLeaf = harness.computePolicyLeafViaLibrary(policyId, policy);

        assertEq(actualLeaf, expectedDoubleHashedLeaf, "library should use double-hash leaf construction");
        assertTrue(actualLeaf != singleHashLeaf, "leaf should not use single-hash variant");
    }

    /// @dev LOP-LEAF-1: deterministic golden-vector check for policy leaf helper.
    function test_computePolicyLeaf_goldenVector_matchesExpectedFormula() public {
        Policy memory policy = _buildBasePolicy();
        uint256 policyId = 2001;

        bytes32 expected = keccak256(bytes.concat(keccak256(abi.encode(policyId, policy))));
        bytes32 actual = harness.computePolicyLeafViaLibrary(policyId, policy);
        assertEq(actual, expected, "golden vector mismatch");
    }

    /// @dev LOP-LEAF-2: same `(policyId, policy)` always yields same leaf.
    function test_computePolicyLeaf_sameInputs_alwaysSameLeaf() public {
        Policy memory policy = _buildBasePolicy();
        uint256 policyId = 2002;

        bytes32 leafA = harness.computePolicyLeafViaLibrary(policyId, policy);
        bytes32 leafB = harness.computePolicyLeafViaLibrary(policyId, policy);
        assertEq(leafA, leafB, "leaf computation should be deterministic");
    }

    /// @dev LOP-LEAF-3: changing `policyId` or any policy field changes leaf.
    function test_computePolicyLeaf_changingPolicyIdOrField_changesLeaf() public {
        Policy memory policy = _buildBasePolicy();
        Policy memory mutatedPolicy = _buildBasePolicy();
        mutatedPolicy.config.anyFunction = false;

        bytes32 baseLeaf = harness.computePolicyLeafViaLibrary(2003, policy);
        bytes32 differentIdLeaf = harness.computePolicyLeafViaLibrary(2004, policy);
        bytes32 differentPolicyLeaf = harness.computePolicyLeafViaLibrary(2003, mutatedPolicy);

        assertTrue(baseLeaf != differentIdLeaf, "policyId must be hash-bound");
        assertTrue(baseLeaf != differentPolicyLeaf, "policy fields must be hash-bound");
    }

    /// @dev LOP-LEAF-4: helper output matches double-hash and differs from single-hash.
    function test_computePolicyLeaf_doubleHashNotSingleHash() public {
        Policy memory policy = _buildBasePolicy();
        uint256 policyId = 2005;

        bytes32 leaf = harness.computePolicyLeafViaLibrary(policyId, policy);
        assertEq(leaf, keccak256(bytes.concat(keccak256(abi.encode(policyId, policy)))), "double-hash mismatch");
        assertTrue(leaf != keccak256(abi.encode(policyId, policy)), "single-hash variant should not match");
    }
}
