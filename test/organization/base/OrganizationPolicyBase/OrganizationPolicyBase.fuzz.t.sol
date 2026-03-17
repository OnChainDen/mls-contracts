// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {IOrganizationPolicy} from "interfaces/organization/IOrganizationPolicy.sol";
import {
    OrganizationPolicyBaseSuiteBase
} from "test/organization/base/OrganizationPolicyBase/OrganizationPolicyBaseSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {Policy, RateLimitType} from "types/PolicyTypes.sol";

/**
 * @dev Fuzz tests for `OrganizationPolicyBase`.
 */
contract OrganizationPolicyBaseFuzzTest is OrganizationPolicyBaseSuiteBase {
    /**
     * @dev Seeds the default one-admin membership configuration used by policy-base fuzz tests.
     */
    function setUp() public override {
        super.setUp();
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
    }

    /**
     * @dev Verifies `OrganizationPolicyBase.setPolicies` remains guardian-only and leaves the signed nonce unused on
     *      unauthorized calls.
     * @param caller Arbitrary caller fuzzed away from the guardian address
     * @param newRoot Random policies root used for the signed payload
     * @param cidSeed Random seed used to derive a deterministic IPFS CID string
     * @param saltRaw Raw salt used to derive a bounded admin-auth salt
     */
    function testFuzz_FOPB_USAGE_63_setPolicies_isGuardianOnlyAndLeavesNonceUnused(
        address caller,
        bytes32 newRoot,
        bytes32 cidSeed,
        uint256 saltRaw
    ) public {
        vm.assume(caller != address(0));
        vm.assume(caller != GUARDIAN);

        // Setup: configure one signed `setPolicies` payload for a guardian execution path.
        string memory ipfsCid = string.concat("ipfs://fopb-usage-63-", vm.toString(cidSeed));
        uint256 salt = bound(saltRaw, 1, type(uint256).max);
        (AdminAuthParams memory auth, bytes memory operationData) = _buildSetPoliciesAuth({
            newPoliciesRoot: newRoot,
            ipfsCid: ipfsCid,
            salt: salt,
            expirationTimestamp: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 nonce = _computeSetPoliciesNonce(operationData, salt);

        // Call: invoke `setPolicies` from a non-guardian caller, expecting the guardian gate to short-circuit first.
        _expectOnlyGuardianRevert(caller);
        vm.prank(caller);
        harness.setPolicies(newRoot, ipfsCid, auth);

        // Verify: unauthorized callers should not consume the signed nonce or mutate the stored policies root.
        assertFalse(harness.getUsedNonce(nonce), "guardian gate should leave the set-policies nonce unused");
        assertEq(harness.getPoliciesRoot(), bytes32(0), "guardian gate should block policy-root mutation");
    }

    /**
     * @dev Verifies `OrganizationPolicyBase.setPolicies` signatures bind exactly to `(newRoot, keccak256(ipfsCid))`.
     * @param signedRoot Policies root used for the signed payload
     * @param signedCidSeed Seed used to derive the signed IPFS CID
     * @param mutatedCidSeed Distinct seed used to derive a mutated IPFS CID when the mutation mode targets CID bytes
     * @param saltRaw Raw salt used to derive a bounded admin-auth salt
     * @param mutationSelector Chooses whether to mutate the signed root or the signed CID hash before replaying auth
     */
    function testFuzz_FOPB_USAGE_63_setPolicies_signaturesBindToExactRootAndCidHash(
        bytes32 signedRoot,
        bytes32 signedCidSeed,
        bytes32 mutatedCidSeed,
        uint256 saltRaw,
        uint8 mutationSelector
    ) public {
        string memory signedCid = string.concat("ipfs://fopb-usage-63-signed-", vm.toString(signedCidSeed));
        string memory otherCid = string.concat("ipfs://fopb-usage-63-mutated-", vm.toString(mutatedCidSeed));
        uint256 salt = bound(saltRaw, 1, type(uint256).max);

        // Setup: sign one exact `(root, keccak256(cid))` payload and derive a mutated replay target.
        (AdminAuthParams memory auth, bytes memory signedOperationData) = _buildSetPoliciesAuth({
            newPoliciesRoot: signedRoot,
            ipfsCid: signedCid,
            salt: salt,
            expirationTimestamp: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        bytes32 mutatedRoot = signedRoot;
        string memory mutatedCid = signedCid;
        if (mutationSelector % 2 == 0) {
            mutatedRoot = bytes32(uint256(signedRoot) ^ uint256(1));
        } else {
            vm.assume(keccak256(bytes(otherCid)) != keccak256(bytes(signedCid)));
            mutatedCid = otherCid;
        }

        bytes memory mutatedOperationData = abi.encode(mutatedRoot, keccak256(bytes(mutatedCid)));
        uint256 signedNonce = _computeSetPoliciesNonce(signedOperationData, salt);
        uint256 mutatedNonce = _computeSetPoliciesNonce(mutatedOperationData, salt);

        // Call: replay the signed auth against an altered root/CID tuple.
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.setPolicies(mutatedRoot, mutatedCid, auth);

        // Verify: altered payloads should not consume either nonce domain or change the stored root.
        assertFalse(harness.getUsedNonce(mutatedNonce), "altered payload should not consume its replay nonce");
        assertFalse(harness.getUsedNonce(signedNonce), "failed replay should preserve the signed nonce");
        assertEq(harness.getPoliciesRoot(), bytes32(0), "failed replay should not change the policies root");

        // Call: execute the exact signed tuple through the guardian entry point.
        vm.prank(GUARDIAN);
        harness.setPolicies(signedRoot, signedCid, auth);

        // Verify: only the exact signed root/CID hash should authorize and persist.
        assertTrue(harness.getUsedNonce(signedNonce), "exact signed tuple should consume the signed nonce");
        assertEq(harness.getPoliciesRoot(), signedRoot, "exact signed tuple should persist the signed policies root");
    }

    /**
     * @dev Verifies `OrganizationPolicyBase.getPolicyUsage` always reverts `PolicyVerificationFailed` for invalid
     *      policy proofs.
     * @param rawPolicyId Raw policy id used to derive a bounded non-zero policy id
     * @param mutationSelector Chooses which proof-invalidating mutation to apply
     * @param account Account used for the queried usage tuple
     * @param destination Destination used for the queried usage tuple
     * @param initiator Initiator used for the queried usage tuple
     * @param rootSeed Seed used to randomize policy fields that contribute to the stored merkle root
     */
    function testFuzz_FOPB_USAGE_63_getPolicyUsage_invalidProofAlwaysReverts(
        uint256 rawPolicyId,
        uint8 mutationSelector,
        address account,
        address destination,
        address initiator,
        bytes32 rootSeed
    ) public {
        uint256 signedPolicyId = bound(rawPolicyId, 1, type(uint96).max - 1);

        // Setup: store one valid policy root/proof pair, then mutate the query so proof verification must fail.
        Policy memory policy = _buildBasePolicy();
        policy.config.anyFunction = (uint8(rootSeed[0]) & 1) == 1;
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = uint16(bound(uint256(uint8(rootSeed[1])), 1, 24));
        policy.config.rateLimit.timeIntervalLimit = bound(uint256(uint8(rootSeed[2])) + 1, 1, 1_000_000);

        bytes32[] memory proof = _setStoredPolicyRootAndReturnProof(signedPolicyId, policy);

        uint8 mode = uint8(mutationSelector % 3);
        uint256 queriedPolicyId = signedPolicyId;
        Policy memory queriedPolicy = policy;
        bytes32[] memory queriedProof = proof;

        if (mode == 0) {
            queriedPolicyId = signedPolicyId + 1;
        } else if (mode == 1) {
            queriedProof[0] = bytes32(uint256(queriedProof[0]) ^ uint256(1));
        } else {
            queriedPolicy.config.anySourceAccount = !policy.config.anySourceAccount;
        }

        // Call: query `getPolicyUsage` with the mutated proof tuple, expecting policy verification to fail.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationPolicy.PolicyVerificationFailed.selector, queriedPolicyId));
        harness.getPolicyUsage({
            policyId: queriedPolicyId,
            policy: queriedPolicy,
            account: account,
            destination: destination,
            initiator: initiator,
            policyProof: queriedProof
        });
    }

    /**
     * @dev Stores a deterministic two-leaf policies root and returns the proof for the target policy.
     * @param policyId Policy id for the target leaf
     * @param policy Policy struct for the target leaf
     * @return proof Merkle proof for `policyId` within the stored root
     */
    function _setStoredPolicyRootAndReturnProof(uint256 policyId, Policy memory policy)
        internal
        returns (bytes32[] memory proof)
    {
        Policy memory companionPolicy = _buildBasePolicy();
        companionPolicy.config.anyFunction = !policy.config.anyFunction;

        Policy[] memory policies = new Policy[](2);
        policies[0] = policy;
        policies[1] = companionPolicy;

        uint256[] memory policyIds = buildUint256Array(policyId, policyId + 1);
        (bytes32 root, bytes32[] memory builtProof) = _buildPolicyRootAndProof(policyIds, policies, 0);
        policyStateHarness.setPoliciesRoot(root);
        return builtProof;
    }
}
