// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {IOrganizationPolicy} from "interfaces/organization/IOrganizationPolicy.sol";
import {LibOrganizationPolicy} from "organization/libraries/LibOrganizationPolicy.sol";
import {
    OrganizationPolicyBaseSuiteBase
} from "test/organization/base/OrganizationPolicyBase/OrganizationPolicyBaseSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {Policy, RateLimitScope, RateLimitType} from "types/PolicyTypes.sol";

/**
 * @dev Unit tests for `OrganizationPolicyBase.setPolicies` and root-transition behavior.
 */
contract OrganizationPolicyBaseSetPoliciesTest is OrganizationPolicyBaseSuiteBase {
    /**
     * @dev Initializes default threshold-one admin config used by positive-path policy updates.
     */
    function setUp() public override {
        super.setUp();
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
    }

    /// @dev Verifies that guardian + valid admin auth updates root and emits `PoliciesUpdated`.
    function test_setPolicies_guardianWithValidAuth_updatesRootAndEmitsPoliciesUpdated() public {
        // Setup: configure a valid fixture for guardian + valid admin auth updates root and emits `PoliciesUpdated`.
        bytes32 newRoot = keccak256("opb-set-1-root");
        string memory ipfsCid = "ipfs://opb-set-1";

        (AdminAuthParams memory auth,) = _buildSetPoliciesAuth({
            newPoliciesRoot: newRoot,
            ipfsCid: ipfsCid,
            salt: 8101,
            expirationTimestamp: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.expectEmit(true, true, true, true);
        emit IOrganizationPolicy.PoliciesUpdated(newRoot, ipfsCid);

        vm.prank(GUARDIAN);
        // Call: execute `setPolicies` with the happy-path payload.
        harness.setPolicies(newRoot, ipfsCid, auth);

        // Verify: assert the expected success result and state updates.
        assertEq(harness.getPoliciesRoot(), newRoot, "policies root should be updated");
    }

    /// @dev Verifies that non-guardian caller reverts with guardian access-control error.
    function test_setPolicies_nonGuardianCaller_revertsOnlyGuardian() public {
        // Setup: configure a valid fixture for non-guardian caller reverts with guardian access-control error.
        AdminAuthParams memory auth;
        _expectOnlyGuardianRevert(NON_GUARDIAN);
        vm.prank(NON_GUARDIAN);
        // Call: execute `setPolicies` with the happy-path payload.
        harness.setPolicies(bytes32(uint256(1)), "ipfs://ignored", auth);
    }

    /// @dev Verifies that insufficient signatures revert via admin-auth validation.
    function test_setPolicies_insufficientSignatures_revertsViaAdminAuthValidation() public {
        // Setup: assemble inputs expected to hit the guarded failure path for insufficient signatures revert via
        // admin-auth validation.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});

        bytes32 newRoot = keccak256("opb-set-3-root");
        string memory ipfsCid = "ipfs://opb-set-3";

        (AdminAuthParams memory auth, bytes memory operationData) = _buildSetPoliciesAuth({
            newPoliciesRoot: newRoot,
            ipfsCid: ipfsCid,
            salt: 8103,
            expirationTimestamp: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert(IOrganizationAdmin.InsufficientAdminAuthorization.selector);
        vm.prank(GUARDIAN);
        // Call: invoke `setPolicies` with the failing payload to exercise the revert branch.
        harness.setPolicies(newRoot, ipfsCid, auth);

        uint256 nonce = _computeSetPoliciesNonce(operationData, 8103);
        assertFalse(harness.getUsedNonce(nonce), "failed auth should not consume nonce");
    }

    /// @dev Verifies that expired `authParams` revert.
    function test_setPolicies_expiredAuthParams_revertsAdminOperationExpired() public {
        // Setup: assemble inputs expected to hit the guarded failure path for expired `authParams` revert.
        bytes32 newRoot = keccak256("opb-set-4-root");
        string memory ipfsCid = "ipfs://opb-set-4";
        uint256 expirationTimestamp = block.timestamp - 1;

        (AdminAuthParams memory auth,) = _buildSetPoliciesAuth({
            newPoliciesRoot: newRoot,
            ipfsCid: ipfsCid,
            salt: 8104,
            expirationTimestamp: expirationTimestamp,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdmin.AdminOperationExpired.selector, expirationTimestamp, block.timestamp
            )
        );
        vm.prank(GUARDIAN);
        // Call: invoke `setPolicies` with the failing payload to exercise the revert branch.
        harness.setPolicies(newRoot, ipfsCid, auth);
    }

    /// @dev Verifies that replay with same nonce/salt reverts after first successful execution.
    function test_setPolicies_replaySameNonce_revertsNonceAlreadyUsed() public {
        // Setup: configure a valid fixture for replay with same nonce/salt reverts after first successful execution.
        bytes32 newRoot = keccak256("opb-set-5-root");
        string memory ipfsCid = "ipfs://opb-set-5";

        (AdminAuthParams memory auth, bytes memory operationData) = _buildSetPoliciesAuth({
            newPoliciesRoot: newRoot,
            ipfsCid: ipfsCid,
            salt: 8105,
            expirationTimestamp: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        // Call: execute `setPolicies` with the happy-path payload.
        harness.setPolicies(newRoot, ipfsCid, auth);

        uint256 nonce = _computeSetPoliciesNonce(operationData, 8105);
        _expectNonceAlreadyUsed(nonce);
        vm.prank(GUARDIAN);
        harness.setPolicies(newRoot, ipfsCid, auth);
    }

    /// @dev Verifies that tampering `newPoliciesRoot` after signing invalidates auth and reverts.
    function test_setPolicies_rootTamperingAfterSigning_invalidatesAuthAndReverts() public {
        // Setup: assemble inputs expected to hit the guarded failure path for tampering `newPoliciesRoot` after signing
        // invalidates auth and reverts.
        bytes32 signedRoot = keccak256("opb-set-6-signed");
        bytes32 tamperedRoot = keccak256("opb-set-6-tampered");
        string memory ipfsCid = "ipfs://opb-set-6";

        (AdminAuthParams memory auth, bytes memory signedOperationData) = _buildSetPoliciesAuth({
            newPoliciesRoot: signedRoot,
            ipfsCid: ipfsCid,
            salt: 8106,
            expirationTimestamp: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert();
        vm.prank(GUARDIAN);
        // Call: invoke `setPolicies` with the failing payload to exercise the revert branch.
        harness.setPolicies(tamperedRoot, ipfsCid, auth);

        uint256 signedNonce = _computeSetPoliciesNonce(signedOperationData, 8106);
        assertFalse(harness.getUsedNonce(signedNonce), "tampered payload should rollback nonce usage");
        assertEq(harness.getPoliciesRoot(), bytes32(0), "state should remain unchanged on tampering");
    }

    /// @dev Verifies that tampering `ipfsCid` after signing invalidates auth and reverts.
    function test_setPolicies_ipfsCidTamperingAfterSigning_invalidatesAuthAndReverts() public {
        // Setup: assemble inputs expected to hit the guarded failure path for tampering `ipfsCid` after signing
        // invalidates auth and reverts.
        bytes32 newRoot = keccak256("opb-set-7-root");
        string memory signedCid = "ipfs://opb-set-7-signed";
        string memory tamperedCid = "ipfs://opb-set-7-tampered";

        (AdminAuthParams memory auth, bytes memory signedOperationData) = _buildSetPoliciesAuth({
            newPoliciesRoot: newRoot,
            ipfsCid: signedCid,
            salt: 8107,
            expirationTimestamp: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert();
        vm.prank(GUARDIAN);
        // Call: invoke `setPolicies` with the failing payload to exercise the revert branch.
        harness.setPolicies(newRoot, tamperedCid, auth);

        uint256 signedNonce = _computeSetPoliciesNonce(signedOperationData, 8107);
        assertFalse(harness.getUsedNonce(signedNonce), "tampered payload should rollback nonce usage");
        assertEq(harness.getPoliciesRoot(), bytes32(0), "state should remain unchanged on tampering");
    }

    /// @dev Verifies that `newPoliciesRoot == bytes32(0)` is allowed and clears policy tree.
    function test_setPolicies_zeroRoot_allowedAndClearsPolicyTree() public {
        // Setup: configure a valid fixture for `newPoliciesRoot == bytes32(0)` is allowed and clears policy tree.
        _setPoliciesAsGuardian(keccak256("opb-set-8-initial"), "ipfs://opb-set-8-initial", 8108);
        // Call: execute `getPoliciesRoot` with the happy-path payload.
        assertTrue(harness.getPoliciesRoot() != bytes32(0), "precondition: non-zero root should be set");

        _setPoliciesAsGuardian(bytes32(0), "ipfs://opb-set-8-clear", 8109);
        assertEq(harness.getPoliciesRoot(), bytes32(0), "zero-root update should clear policy tree root");
    }

    /// @dev Verifies that empty `ipfsCid` is allowed and still emits event.
    function test_setPolicies_emptyIpfsCid_allowedAndEmitsEvent() public {
        // Setup: configure a valid fixture for empty `ipfsCid` is allowed and still emits event.
        bytes32 newRoot = keccak256("opb-set-9-root");
        string memory ipfsCid = "";

        (AdminAuthParams memory auth,) = _buildSetPoliciesAuth({
            newPoliciesRoot: newRoot,
            ipfsCid: ipfsCid,
            salt: 8110,
            expirationTimestamp: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.expectEmit(true, true, true, true);
        emit IOrganizationPolicy.PoliciesUpdated(newRoot, ipfsCid);

        vm.prank(GUARDIAN);
        // Call: execute `setPolicies` with the happy-path payload.
        harness.setPolicies(newRoot, ipfsCid, auth);
        // Verify: assert the expected success result and state updates.
        assertEq(harness.getPoliciesRoot(), newRoot, "root should still update with empty CID");
    }

    /// @dev Verifies that failed auth does not consume nonce; same salt can later succeed.
    function test_setPolicies_failedAuthDoesNotConsumeNonce_sameSaltCanLaterSucceed() public {
        // Setup: assemble inputs expected to hit the guarded failure path for failed auth does not consume nonce; same
        // salt can later succeed.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});

        bytes32 newRoot = keccak256("opb-set-10-root");
        string memory ipfsCid = "ipfs://opb-set-10";

        (AdminAuthParams memory badAuth, bytes memory operationData) = _buildSetPoliciesAuth({
            newPoliciesRoot: newRoot,
            ipfsCid: ipfsCid,
            salt: 8111,
            expirationTimestamp: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert(IOrganizationAdmin.InsufficientAdminAuthorization.selector);
        vm.prank(GUARDIAN);
        // Call: invoke `setPolicies` with the failing payload to exercise the revert branch.
        harness.setPolicies(newRoot, ipfsCid, badAuth);

        uint256 nonce = _computeSetPoliciesNonce(operationData, 8111);
        assertFalse(harness.getUsedNonce(nonce), "failed auth attempt must not consume nonce");

        (AdminAuthParams memory goodAuth,) = _buildSetPoliciesAuth({
            newPoliciesRoot: newRoot,
            ipfsCid: ipfsCid,
            salt: 8111,
            expirationTimestamp: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1, ADMIN_PK_2)
        });

        vm.prank(GUARDIAN);
        harness.setPolicies(newRoot, ipfsCid, goodAuth);
        assertTrue(harness.getUsedNonce(nonce), "successful retry should consume the nonce");
    }

    /// @dev Verifies that after clearing root to zero, old proof reads must revert (no stale-root reads).
    function test_setPolicies_transitionClearRoot_oldProofReadReverts() public {
        // Setup: assemble inputs expected to hit the guarded failure path for after clearing root to zero, old proof
        // reads must revert (no stale-root reads).
        Policy memory policy = _buildRateLimitedPolicy();
        uint256 policyId = 9111;

        Policy[] memory policies = new Policy[](1);
        policies[0] = policy;
        uint256[] memory policyIds = new uint256[](1);
        policyIds[0] = policyId;
        (bytes32 rootR1, bytes32[] memory proofR1) = _buildPolicyRootAndProof(policyIds, policies, 0);

        _setPoliciesAsGuardian(rootR1, "ipfs://opb-set-11-r1", 8112);

        // Call: invoke `getPolicyUsage` with the failing payload to exercise the revert branch.
        uint256 usageBefore = harness.getPolicyUsage(policyId, policy, admin1, admin2, initiator1, proofR1);
        // Verify: assert that the revert reason matches the policy guard under test.
        assertEq(usageBefore, 0, "baseline read with active root should succeed");

        _setPoliciesAsGuardian(bytes32(0), "ipfs://opb-set-11-clear", 8113);

        vm.expectRevert(abi.encodeWithSelector(IOrganizationPolicy.PolicyVerificationFailed.selector, policyId));
        harness.getPolicyUsage(policyId, policy, admin1, admin2, initiator1, proofR1);
    }

    /// @dev Verifies that r1->0->R2 hardening transition rejects old proofs and accepts new proofs.
    function test_setPolicies_hardeningTransition_rejectsOldProofsAcceptsNewProofs() public {
        // Setup: assemble inputs expected to hit the guarded failure path for r1->0->R2 hardening transition rejects
        // old proofs and accepts new proofs.
        uint256 policyId = 9112;
        Policy memory policyR1 = _buildRateLimitedPolicy();
        Policy memory policyR2 = _buildRateLimitedPolicy();
        policyR2.config.rateLimit.timeIntervalLimit = 777;

        Policy[] memory policySingle = new Policy[](1);
        uint256[] memory idSingle = new uint256[](1);
        idSingle[0] = policyId;

        policySingle[0] = policyR1;
        (bytes32 rootR1, bytes32[] memory proofR1) = _buildPolicyRootAndProof(idSingle, policySingle, 0);
        _setPoliciesAsGuardian(rootR1, "ipfs://opb-set-12-r1", 8114);

        _setPoliciesAsGuardian(bytes32(0), "ipfs://opb-set-12-clear", 8115);

        policySingle[0] = policyR2;
        (bytes32 rootR2, bytes32[] memory proofR2) = _buildPolicyRootAndProof(idSingle, policySingle, 0);
        _setPoliciesAsGuardian(rootR2, "ipfs://opb-set-12-r2", 8116);

        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationPolicy.PolicyVerificationFailed.selector, policyId));
        // Call: invoke `getPolicyUsage` with the failing payload to exercise the revert branch.
        harness.getPolicyUsage(policyId, policyR1, admin1, admin2, initiator1, proofR1);

        uint256 usageR2 = harness.getPolicyUsage(policyId, policyR2, admin1, admin2, initiator1, proofR2);
        assertEq(usageR2, 0, "fresh root proof should read successfully");
    }

    /// @dev Verifies that `policiesRoot()` returns zero before any successful update.
    function test_policiesRoot_beforeAnyUpdate_returnsZero() public view {
        // Setup: configure a valid fixture for `policiesRoot()` returns zero before any successful update.
        // Call: execute `policiesRoot` with the happy-path payload.
        assertEq(harness.policiesRoot(), bytes32(0), "default policies root should be zero");
    }

    /// @dev Verifies that `policiesRoot()` returns latest root after one and multiple updates.
    function test_policiesRoot_afterMultipleUpdates_returnsLatestRoot() public {
        // Setup: configure a valid fixture for `policiesRoot()` returns latest root after one and multiple updates.
        bytes32 root1 = keccak256("opb-root-2-r1");
        bytes32 root2 = keccak256("opb-root-2-r2");
        _setPoliciesAsGuardian(root1, "ipfs://opb-root-2-r1", 8117);
        // Call: execute `policiesRoot` with the happy-path payload.
        assertEq(harness.policiesRoot(), root1, "first update should be reflected");

        _setPoliciesAsGuardian(root2, "ipfs://opb-root-2-r2", 8118);
        assertEq(harness.policiesRoot(), root2, "second update should be reflected");
    }

    /// @dev Verifies that valid policy proof returns current usage from rate-limit storage.
    function test_getPolicyUsage_validProof_returnsCurrentTrackedUsage() public {
        // Setup: configure a valid fixture for valid policy proof returns current usage from rate-limit storage.
        Policy memory policy = _buildRateLimitedPolicy();
        uint256 policyId = 9201;

        Policy[] memory policies = new Policy[](1);
        policies[0] = policy;
        uint256[] memory ids = new uint256[](1);
        ids[0] = policyId;
        (bytes32 root, bytes32[] memory proof) = _buildPolicyRootAndProof(ids, policies, 0);
        _setPoliciesAsGuardian(root, "ipfs://opb-usage-1", 8119);

        bytes32 usageKey = LibOrganizationPolicy.computeUsageKey(policyId, policy, admin1, admin2, initiator1);
        uint256 window = LibOrganizationPolicy.computeTimeWindow(policy);
        harness.setPolicyUsage(usageKey, window, 42);

        // Call: execute `getPolicyUsage` with the happy-path payload.
        uint256 usage = harness.getPolicyUsage(policyId, policy, admin1, admin2, initiator1, proof);
        // Verify: assert the expected success result and state updates.
        assertEq(usage, 42, "view should return current tracked usage");
    }

    /// @dev Verifies that invalid policy proof reverts with `PolicyVerificationFailed(policyId)`.
    function test_getPolicyUsage_invalidPolicyProof_revertsPolicyVerificationFailed() public {
        // Setup: assemble inputs expected to hit the guarded failure path for invalid policy proof reverts with
        // `PolicyVerificationFailed(policyId)`.
        Policy memory policy = _buildRateLimitedPolicy();
        uint256 policyId = 9202;

        Policy[] memory policies = new Policy[](1);
        policies[0] = policy;
        uint256[] memory ids = new uint256[](1);
        ids[0] = policyId;
        (bytes32 root,) = _buildPolicyRootAndProof(ids, policies, 0);
        _setPoliciesAsGuardian(root, "ipfs://opb-usage-2", 8120);

        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = keccak256("bad-proof");

        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationPolicy.PolicyVerificationFailed.selector, policyId));
        // Call: invoke `getPolicyUsage` with the failing payload to exercise the revert branch.
        harness.getPolicyUsage(policyId, policy, admin1, admin2, initiator1, invalidProof);
    }

    /// @dev Verifies that wrong `policyId` for otherwise-valid proof reverts.
    function test_getPolicyUsage_wrongPolicyIdForProof_revertsPolicyVerificationFailed() public {
        // Setup: assemble inputs expected to hit the guarded failure path for wrong `policyId` for otherwise-valid
        // proof reverts.
        Policy memory policy = _buildRateLimitedPolicy();
        uint256 signedPolicyId = 9203;
        uint256 queriedPolicyId = 9204;

        Policy[] memory policies = new Policy[](1);
        policies[0] = policy;
        uint256[] memory ids = new uint256[](1);
        ids[0] = signedPolicyId;
        (bytes32 root, bytes32[] memory proof) = _buildPolicyRootAndProof(ids, policies, 0);
        _setPoliciesAsGuardian(root, "ipfs://opb-usage-3", 8121);

        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationPolicy.PolicyVerificationFailed.selector, queriedPolicyId));
        // Call: invoke `getPolicyUsage` with the failing payload to exercise the revert branch.
        harness.getPolicyUsage(queriedPolicyId, policy, admin1, admin2, initiator1, proof);
    }

    /// @dev Verifies that `policiesRoot == 0` rejects non-empty policy via `PolicyVerificationFailed`.
    function test_getPolicyUsage_zeroPoliciesRoot_revertsPolicyVerificationFailed() public {
        // Setup: assemble inputs expected to hit the guarded failure path for `policiesRoot == 0` rejects non-empty
        // policy via `PolicyVerificationFailed`.
        Policy memory policy = _buildRateLimitedPolicy();
        uint256 policyId = 9205;
        bytes32[] memory emptyProof = new bytes32[](0);

        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationPolicy.PolicyVerificationFailed.selector, policyId));
        // Call: invoke `getPolicyUsage` with the failing payload to exercise the revert branch.
        harness.getPolicyUsage(policyId, policy, admin1, admin2, initiator1, emptyProof);
    }

    /// @dev Verifies that policy with no active rate limit returns `0` usage.
    function test_getPolicyUsage_noActiveRateLimit_returnsZero() public {
        // Setup: configure a valid fixture for policy with no active rate limit returns `0` usage.
        Policy memory policy = _buildBasePolicy();
        uint256 policyId = 9206;

        Policy[] memory policies = new Policy[](1);
        policies[0] = policy;
        uint256[] memory ids = new uint256[](1);
        ids[0] = policyId;
        (bytes32 root, bytes32[] memory proof) = _buildPolicyRootAndProof(ids, policies, 0);
        _setPoliciesAsGuardian(root, "ipfs://opb-usage-5", 8122);

        // Call: execute `getPolicyUsage` with the happy-path payload.
        uint256 usage = harness.getPolicyUsage(policyId, policy, admin1, admin2, initiator1, proof);
        // Verify: assert the expected success result and state updates.
        assertEq(usage, 0, "no active rate limit should report zero usage");
    }

    /// @dev Verifies that usage keying is correctly scoped by account/destination/initiator config.
    function test_getPolicyUsage_scopeKeying_separatesEntitiesCorrectly() public {
        // Setup: configure a valid fixture for usage keying is correctly scoped by account/destination/initiator
        // config.
        Policy memory policy = _buildRateLimitedPolicy();
        policy.config.rateLimit.sourceScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.destinationScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.initiatorScope = RateLimitScope.PerEntity;

        uint256 policyId = 9207;
        Policy[] memory policies = new Policy[](1);
        policies[0] = policy;
        uint256[] memory ids = new uint256[](1);
        ids[0] = policyId;
        (bytes32 root, bytes32[] memory proof) = _buildPolicyRootAndProof(ids, policies, 0);
        _setPoliciesAsGuardian(root, "ipfs://opb-usage-6", 8123);

        bytes32 keyA = LibOrganizationPolicy.computeUsageKey(policyId, policy, admin1, admin2, initiator1);
        bytes32 keyB = LibOrganizationPolicy.computeUsageKey(policyId, policy, admin2, admin2, initiator1);
        uint256 window = LibOrganizationPolicy.computeTimeWindow(policy);
        harness.setPolicyUsage(keyA, window, 9);
        harness.setPolicyUsage(keyB, window, 3);

        // Call: execute `getPolicyUsage` with the happy-path payload.
        assertEq(harness.getPolicyUsage(policyId, policy, admin1, admin2, initiator1, proof), 9, "key A usage mismatch");
        assertEq(harness.getPolicyUsage(policyId, policy, admin2, admin2, initiator1, proof), 3, "key B usage mismatch");
    }

    /// @dev Verifies that usage reflects time-window rollover (old window not counted).
    function test_getPolicyUsage_windowRollover_oldWindowNotCounted() public {
        // Setup: configure a valid fixture for usage reflects time-window rollover (old window not counted).
        Policy memory policy = _buildRateLimitedPolicy();
        policy.config.rateLimit.timeIntervalHours = 1;

        uint256 policyId = 9208;
        Policy[] memory policies = new Policy[](1);
        policies[0] = policy;
        uint256[] memory ids = new uint256[](1);
        ids[0] = policyId;
        (bytes32 root, bytes32[] memory proof) = _buildPolicyRootAndProof(ids, policies, 0);
        _setPoliciesAsGuardian(root, "ipfs://opb-usage-7", 8124);

        bytes32 key = LibOrganizationPolicy.computeUsageKey(policyId, policy, admin1, admin2, initiator1);
        uint256 firstWindow = LibOrganizationPolicy.computeTimeWindow(policy);
        harness.setPolicyUsage(key, firstWindow, 15);
        // Call: execute `getPolicyUsage` with the happy-path payload.
        assertEq(harness.getPolicyUsage(policyId, policy, admin1, admin2, initiator1, proof), 15, "window-1 usage");

        vm.warp(block.timestamp + 3600);
        assertEq(
            harness.getPolicyUsage(policyId, policy, admin1, admin2, initiator1, proof),
            0,
            "new window should read zero"
        );
    }

    /// @dev Verifies that `getPolicyUsage` does not mutate state.
    function test_getPolicyUsage_viewCallDoesNotMutateState() public {
        // Setup: configure a valid fixture for `getPolicyUsage` does not mutate state.
        Policy memory policy = _buildRateLimitedPolicy();
        uint256 policyId = 9209;

        Policy[] memory policies = new Policy[](1);
        policies[0] = policy;
        uint256[] memory ids = new uint256[](1);
        ids[0] = policyId;
        (bytes32 root, bytes32[] memory proof) = _buildPolicyRootAndProof(ids, policies, 0);
        _setPoliciesAsGuardian(root, "ipfs://opb-usage-8", 8125);

        bytes32 key = LibOrganizationPolicy.computeUsageKey(policyId, policy, admin1, admin2, initiator1);
        uint256 window = LibOrganizationPolicy.computeTimeWindow(policy);
        harness.setPolicyUsage(key, window, 21);

        // Call: execute `getPolicyUsage` with the happy-path payload.
        uint256 beforeUsage = harness.getPolicyUsage(key, window);
        uint256 viewed = harness.getPolicyUsage(policyId, policy, admin1, admin2, initiator1, proof);
        uint256 afterUsage = harness.getPolicyUsage(key, window);

        // Verify: assert the expected success result and state updates.
        assertEq(viewed, 21, "view result mismatch");
        assertEq(beforeUsage, afterUsage, "view should not mutate usage storage");
    }

    /// @dev Verifies that rotating root from R1 to R2 invalidates stale proofs and accepts fresh proofs.
    function test_getPolicyUsage_rootRotation_staleProofFailsFreshProofSucceeds() public {
        // Setup: assemble inputs expected to hit the guarded failure path for rotating root from R1 to R2 invalidates
        // stale proofs and accepts fresh proofs.
        uint256 policyId = 9210;
        Policy memory policyR1 = _buildRateLimitedPolicy();
        Policy memory policyR2 = _buildRateLimitedPolicy();
        policyR2.config.rateLimit.timeIntervalLimit = 1234;

        Policy[] memory policies = new Policy[](1);
        uint256[] memory ids = new uint256[](1);
        ids[0] = policyId;

        policies[0] = policyR1;
        (bytes32 rootR1, bytes32[] memory proofR1) = _buildPolicyRootAndProof(ids, policies, 0);
        _setPoliciesAsGuardian(rootR1, "ipfs://opb-usage-9-r1", 8126);
        // Call: invoke `getPolicyUsage` with the failing payload to exercise the revert branch.
        assertEq(harness.getPolicyUsage(policyId, policyR1, admin1, admin2, initiator1, proofR1), 0, "R1 read");

        policies[0] = policyR2;
        (bytes32 rootR2, bytes32[] memory proofR2) = _buildPolicyRootAndProof(ids, policies, 0);
        _setPoliciesAsGuardian(rootR2, "ipfs://opb-usage-9-r2", 8127);

        vm.expectRevert(abi.encodeWithSelector(IOrganizationPolicy.PolicyVerificationFailed.selector, policyId));
        harness.getPolicyUsage(policyId, policyR1, admin1, admin2, initiator1, proofR1);

        assertEq(harness.getPolicyUsage(policyId, policyR2, admin1, admin2, initiator1, proofR2), 0, "R2 read");
    }

    /**
     * @dev Helper: executes `setPolicies` with threshold-one admin auth.
     */
    function _setPoliciesAsGuardian(bytes32 newRoot, string memory ipfsCid, uint256 salt) internal {
        (AdminAuthParams memory auth,) = _buildSetPoliciesAuth({
            newPoliciesRoot: newRoot,
            ipfsCid: ipfsCid,
            salt: salt,
            expirationTimestamp: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        harness.setPolicies(newRoot, ipfsCid, auth);
    }

    /**
     * @dev Helper: builds an active time-interval rate-limited policy fixture.
     */
    function _buildRateLimitedPolicy() internal view returns (Policy memory policy) {
        policy = _buildBasePolicy();
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 24;
        policy.config.rateLimit.timeIntervalLimit = 1000;
        policy.config.rateLimit.sourceScope = RateLimitScope.AcrossAll;
        policy.config.rateLimit.destinationScope = RateLimitScope.AcrossAll;
        policy.config.rateLimit.initiatorScope = RateLimitScope.AcrossAll;
    }
}
