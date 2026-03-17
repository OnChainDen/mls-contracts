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
import {OperationType} from "types/CommonTypes.sol";
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

    /// @dev Verifies that malformed packed signatures revert via admin-auth validation.
    function test_setPolicies_invalidPackedSignatures_revertsViaAdminAuthValidation() public {
        // Setup: assemble inputs expected to hit the guarded failure path for malformed packed signatures.
        bytes32 newRoot = keccak256("opb-set-3-invalid-packed-root");
        string memory ipfsCid = "ipfs://opb-set-3-invalid-packed";

        (AdminAuthParams memory auth, bytes memory operationData) = _buildSetPoliciesAuth({
            newPoliciesRoot: newRoot,
            ipfsCid: ipfsCid,
            salt: 8130,
            expirationTimestamp: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        auth.signatures = hex"1b";

        // Verify: assert that malformed packed signatures fail signature recovery.
        _expectSignatureRecoveryFailure();
        vm.prank(GUARDIAN);
        // Call: invoke `setPolicies` with malformed signatures to exercise the revert branch.
        harness.setPolicies(newRoot, ipfsCid, auth);

        uint256 nonce = _computeSetPoliciesNonce(operationData, 8130);
        assertFalse(harness.getUsedNonce(nonce), "failed auth should not consume nonce");
    }

    /// @dev Verifies that non-admin signer signatures revert via admin-auth validation.
    function test_setPolicies_nonAdminSignerSignature_revertsViaAdminAuthValidation() public {
        // Setup: assemble inputs expected to hit the guarded failure path for non-admin signer signatures.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1), threshold: 1});

        bytes32 newRoot = keccak256("opb-set-3-invalid-signer-root");
        string memory ipfsCid = "ipfs://opb-set-3-invalid-signer";

        (AdminAuthParams memory auth, bytes memory operationData) = _buildSetPoliciesAuth({
            newPoliciesRoot: newRoot,
            ipfsCid: ipfsCid,
            salt: 8131,
            expirationTimestamp: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_2)
        });

        // Verify: assert that signature from a non-admin account is rejected.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.SignerIsNotAdmin.selector, admin2));
        vm.prank(GUARDIAN);
        // Call: invoke `setPolicies` with a non-admin signer signature to exercise the revert branch.
        harness.setPolicies(newRoot, ipfsCid, auth);

        uint256 nonce = _computeSetPoliciesNonce(operationData, 8131);
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
    function test_NMPB_SP_1_setPolicies_replaySameNonce_revertsNonceAlreadyUsed() public {
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

    /// @dev Verifies `OrganizationPolicyBase.setPolicies` binds the hashed IPFS CID into nonce derivation while
    /// preserving deterministic nonces for identical `(newPoliciesRoot, ipfsCid)` payload bytes.
    function test_NMPB_SP_2__NMPB_SP_3_setPolicies_nonceBinding_tracksIpfsCidBytes() public view {
        bytes32 newRoot = keccak256("nmpb-sp-2-root");
        string memory ipfsCidA = "ipfs://nmpb-sp-2-a";
        string memory ipfsCidASameBytes = "ipfs://nmpb-sp-2-a";
        string memory ipfsCidB = "ipfs://nmpb-sp-2-b";

        // Setup: derive operation data for one root paired with equal-CID and different-CID byte strings.
        bytes memory operationDataA = abi.encode(newRoot, keccak256(bytes(ipfsCidA)));
        bytes memory operationDataASameBytes = abi.encode(newRoot, keccak256(bytes(ipfsCidASameBytes)));
        bytes memory operationDataB = abi.encode(newRoot, keccak256(bytes(ipfsCidB)));

        // Call: compute nonces for all three policy payload variants under the same admin-auth salt.
        uint256 nonceA = _computeSetPoliciesNonce(operationDataA, 81_051);
        uint256 nonceASameBytes = _computeSetPoliciesNonce(operationDataASameBytes, 81_051);
        uint256 nonceB = _computeSetPoliciesNonce(operationDataB, 81_051);

        // Verify: matching CID bytes preserve the nonce exactly, while a different CID changes the nonce even when the
        // policies root stays fixed.
        assertEq(nonceA, nonceASameBytes, "identical root and CID bytes should produce the same nonce");
        assertTrue(nonceA != nonceB, "changing only the CID should move the nonce into a different replay domain");
    }

    /// @dev Verifies `OrganizationPolicyBase.setPolicies` can apply the same `(newPoliciesRoot, ipfsCid)` tuple
    /// twice when the admin-auth salt changes.
    function test_NMPB_SP_4_setPolicies_sameTupleDifferentAdminAuthSalts_canBothSucceed() public {
        bytes32 newRoot = keccak256("nmpb-sp-4-root");
        string memory ipfsCid = "ipfs://nmpb-sp-4";

        // Setup: build two successful policy updates whose signed payload bytes are identical except for the
        // admin-auth salt used in nonce derivation.
        (AdminAuthParams memory firstAuth, bytes memory operationData) = _buildSetPoliciesAuth({
            newPoliciesRoot: newRoot,
            ipfsCid: ipfsCid,
            salt: 81_052,
            expirationTimestamp: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        (AdminAuthParams memory secondAuth,) = _buildSetPoliciesAuth({
            newPoliciesRoot: newRoot,
            ipfsCid: ipfsCid,
            salt: 81_053,
            expirationTimestamp: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        uint256 firstNonce = _computeSetPoliciesNonce(operationData, 81_052);
        uint256 secondNonce = _computeSetPoliciesNonce(operationData, 81_053);

        // Call: execute the same policy update twice using different admin-auth salts.
        vm.prank(GUARDIAN);
        harness.setPolicies(newRoot, ipfsCid, firstAuth);

        vm.prank(GUARDIAN);
        harness.setPolicies(newRoot, ipfsCid, secondAuth);

        // Verify: both admin-auth salts consume independent nonces while the idempotent policy root remains set to
        // the requested value after the second write.
        assertTrue(harness.getUsedNonce(firstNonce), "first salt should consume its policy-update nonce");
        assertTrue(harness.getUsedNonce(secondNonce), "second salt should consume its policy-update nonce");
        assertEq(harness.getPoliciesRoot(), newRoot, "repeated idempotent policy updates should preserve the root");
    }

    /// @dev Verifies rejecting a `ModifyPolicies` operation blocks later execution of the same signed payload.
    /// [OPB-SP-2]
    function test_OPB_SP_2_rejectAdminOperation_blocksLaterSetPoliciesForSameSignedOperation() public {
        bytes32 newRoot = keccak256("opb-sp-2-root");
        string memory ipfsCid = "ipfs://opb-sp-2";

        // Setup: build one approval payload and one rejection payload over the exact same
        // `(newPoliciesRoot, ipfsCid, salt, expiration)` tuple.
        (AdminAuthParams memory approvalAuth, bytes memory operationData) = _buildSetPoliciesAuth({
            newPoliciesRoot: newRoot,
            ipfsCid: ipfsCid,
            salt: 81_054,
            expirationTimestamp: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        AdminAuthParams memory rejectionAuth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.ModifyPolicies,
            operationData: operationData,
            isApproval: false,
            salt: 81_054,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 nonce = _computeSetPoliciesNonce(operationData, 81_054);

        vm.prank(GUARDIAN);
        harness.rejectAdminOperation(OperationType.ModifyPolicies, operationData, rejectionAuth);

        // Call: try to execute `setPolicies` with the approval signatures for the now-rejected nonce.
        assertTrue(harness.getUsedNonce(nonce), "rejection should burn the shared modify-policies nonce");
        _expectNonceAlreadyUsed(nonce);
        vm.prank(GUARDIAN);
        harness.setPolicies(newRoot, ipfsCid, approvalAuth);

        // Verify: the rejected operation never updates the policies root.
        assertEq(harness.getPoliciesRoot(), bytes32(0), "rejected modify-policies tuple must remain unexecutable");
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

        bytes memory tamperedOperationData = abi.encode(tamperedRoot, keccak256(bytes(ipfsCid)));
        bytes32 tamperedOperationHash = harness.getAdminOperationHash({
            operationType: OperationType.ModifyPolicies,
            operationData: tamperedOperationData,
            salt: auth.salt,
            expirationTimestamp: auth.expirationTimestamp,
            isApproval: true
        });
        address expectedRecoveredSigner = _recoverEoaSignerFromPackedSignature(tamperedOperationHash, auth.signatures);

        // Verify: assert that tampering invalidates the recovered signer and bubbles strict admin signer validation.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.SignerIsNotAdmin.selector, expectedRecoveredSigner));
        vm.prank(GUARDIAN);
        // Call: invoke `setPolicies` with the failing payload to exercise the revert branch.
        harness.setPolicies(tamperedRoot, ipfsCid, auth);

        uint256 signedNonce = _computeSetPoliciesNonce(signedOperationData, 8106);
        assertFalse(harness.getUsedNonce(signedNonce), "tampered payload should rollback nonce usage");
        assertEq(harness.getPoliciesRoot(), bytes32(0), "state should remain unchanged on tampering");
    }

    /// @dev Verifies `setPolicies` binds the signed IPFS CID hash and rejects CID tampering. [OPB-SP-3]
    function test_OPB_SP_3_setPolicies_ipfsCidTamperingAfterSigning_invalidatesAuthAndReverts() public {
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

        bytes memory tamperedOperationData = abi.encode(newRoot, keccak256(bytes(tamperedCid)));
        bytes32 tamperedOperationHash = harness.getAdminOperationHash({
            operationType: OperationType.ModifyPolicies,
            operationData: tamperedOperationData,
            salt: auth.salt,
            expirationTimestamp: auth.expirationTimestamp,
            isApproval: true
        });
        address expectedRecoveredSigner = _recoverEoaSignerFromPackedSignature(tamperedOperationHash, auth.signatures);

        // Verify: assert that tampering invalidates the recovered signer and bubbles strict admin signer validation.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.SignerIsNotAdmin.selector, expectedRecoveredSigner));
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

    /// @dev Verifies clearing the policy root invalidates signatures collected under the old policy set. [OPB-PGM-1]
    function test_OPB_PGM_1_setPolicies_transitionClearRoot_oldProofReadReverts() public {
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

    /// @dev Verifies a successful `setPolicies` update is immediately usable by `getPolicyUsage`. [OPB-SP-1,
    /// OPB-GPU-1]
    function test_OPB_SP_1__OPB_GPU_1_getPolicyUsage_validProof_returnsCurrentTrackedUsage() public {
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

    /// @dev Verifies invalid policy proofs revert `PolicyVerificationFailed`. [OPB-GPU-2]
    function test_OPB_GPU_2_getPolicyUsage_invalidPolicyProof_revertsPolicyVerificationFailed() public {
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
     * @dev Helper: recovers signer from one packed EOA signature (`v || r || s`) against `hash`.
     */
    function _recoverEoaSignerFromPackedSignature(bytes32 hash, bytes memory signatures)
        internal
        pure
        returns (address)
    {
        if (signatures.length < 65) return address(0);

        uint8 v;
        bytes32 r;
        bytes32 s;
        assembly {
            v := byte(0, mload(add(signatures, 0x20)))
            r := mload(add(signatures, 0x21))
            s := mload(add(signatures, 0x41))
        }

        return ecrecover(hash, v, r, s);
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
