// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {MerkleUtils} from "libraries/MerkleUtils.sol";
import {
    LibOrganizationAccountSignatureTestBase
} from "test/organization/libraries/LibOrganizationAccountSignature/LibOrganizationAccountSignatureTestBase.sol";
import {ApproverType, Policy, PolicyType, TransactionType, ValidationProofs} from "types/PolicyTypes.sol";

/**
 * @dev Unit tests for `LibOrganizationAccountSignature._isERC1271SignatureAllowedByPolicy`.
 */
contract LibOrganizationAccountSignatureIsERC1271SignatureAllowedByPolicyTest is
    LibOrganizationAccountSignatureTestBase
{
    /// @dev Verifies that invalid policy proofs return false.
    function test_isERC1271SignatureAllowedByPolicy_invalidPolicyProof_returnsFalse() public {
        // Setup: build a valid fixture and then tamper policy proof bytes.
        (Policy memory policy, ValidationProofs memory proofs) = _buildAllowedFixture();
        policy;
        proofs.policyProof = new bytes32[](1);
        proofs.policyProof[0] = keccak256("bad-proof");

        // Call: execute `isERC1271SignatureAllowedByPolicyViaLibrary` with invalid policy proof.
        bool allowed =
            harness.isERC1271SignatureAllowedByPolicyViaLibrary(ACCOUNT, initiator1, DEFAULT_POLICY_ID, proofs);

        // Verify: invalid policy proofs should fail closed.
        assertFalse(allowed, "invalid policy proof should return false");
    }

    /// @dev Verifies that `TokenTransfers` policies are not valid for ERC-1271 signatures.
    function test_isERC1271SignatureAllowedByPolicy_tokenTransfersPolicy_returnsFalse() public {
        // Setup: build policy fixture with non-signature transaction type.
        (Policy memory policy,) = _buildAllowedFixture();
        policy.config.transactionType = TransactionType.TokenTransfers;
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        // Call: execute `isERC1271SignatureAllowedByPolicyViaLibrary` with token-transfer policy.
        bool allowed =
            harness.isERC1271SignatureAllowedByPolicyViaLibrary(ACCOUNT, initiator1, DEFAULT_POLICY_ID, proofs);

        // Verify: non-signature transaction types should be rejected.
        assertFalse(allowed, "token-transfer policy should be rejected for signatures");
    }

    /// @dev Verifies that `ContractInteractions` policies are not valid for ERC-1271 signatures.
    function test_isERC1271SignatureAllowedByPolicy_contractInteractionsPolicy_returnsFalse() public {
        // Setup: build policy fixture with non-signature transaction type.
        (Policy memory policy,) = _buildAllowedFixture();
        policy.config.transactionType = TransactionType.ContractInteractions;
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        // Call: execute `isERC1271SignatureAllowedByPolicyViaLibrary` with contract-interaction policy.
        bool allowed =
            harness.isERC1271SignatureAllowedByPolicyViaLibrary(ACCOUNT, initiator1, DEFAULT_POLICY_ID, proofs);

        // Verify: non-signature transaction types should be rejected.
        assertFalse(allowed, "contract-interaction policy should be rejected for signatures");
    }

    /// @dev Verifies that `Any` transaction type is rejected for ERC-1271 signatures.
    function test_isERC1271SignatureAllowedByPolicy_anyTransactionType_returnsFalse() public {
        // Setup: build policy fixture with `TransactionType.Any`.
        (Policy memory policy,) = _buildAllowedFixture();
        policy.config.transactionType = TransactionType.Any;
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        // Call: execute `isERC1271SignatureAllowedByPolicyViaLibrary` with `Any` tx type policy.
        bool allowed =
            harness.isERC1271SignatureAllowedByPolicyViaLibrary(ACCOUNT, initiator1, DEFAULT_POLICY_ID, proofs);

        // Verify: policy must be exactly `Signatures` to pass.
        assertFalse(allowed, "transactionType=Any should be rejected for signatures");
    }

    /// @dev Verifies that source-account mismatches return false when source filtering is enabled.
    function test_isERC1271SignatureAllowedByPolicy_sourceAccountMismatch_returnsFalse() public {
        // Setup: build source-account constrained policy allowing only `OTHER_ACCOUNT`.
        (Policy memory policy,) = _buildAllowedFixture();
        policy.config.anySourceAccount = false;
        policy.roots.sourceAccountsRoot = MerkleUtils.computeAddressLeaf(OTHER_ACCOUNT);

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        // Call: execute `isERC1271SignatureAllowedByPolicyViaLibrary` for a disallowed account.
        bool allowed =
            harness.isERC1271SignatureAllowedByPolicyViaLibrary(ACCOUNT, initiator1, DEFAULT_POLICY_ID, proofs);

        // Verify: source-account mismatch should fail closed.
        assertFalse(allowed, "source-account mismatch should return false");
    }

    /// @dev Verifies that `anySourceAccount=true` bypasses source-account proof checks.
    function test_isERC1271SignatureAllowedByPolicy_anySourceAccountBypassesSourceProof_returnsTrue() public {
        // Setup: build valid fixture with permissive `anySourceAccount=true` and empty source proof.
        (, ValidationProofs memory proofs) = _buildAllowedFixture();
        proofs.sourceAccountProof = new bytes32[](0);

        // Call: execute `isERC1271SignatureAllowedByPolicyViaLibrary` for arbitrary account.
        bool allowed =
            harness.isERC1271SignatureAllowedByPolicyViaLibrary(OTHER_ACCOUNT, initiator1, DEFAULT_POLICY_ID, proofs);

        // Verify: permissive source-account policies should allow arbitrary accounts.
        assertTrue(allowed, "anySourceAccount should bypass source-account proof checks");
    }

    /// @dev Verifies that unauthorized initiators return false.
    function test_isERC1271SignatureAllowedByPolicy_unauthorizedInitiator_returnsFalse() public {
        // Setup: build valid fixture constrained to `initiator1`.
        (, ValidationProofs memory proofs) = _buildAllowedFixture();

        // Call: execute `isERC1271SignatureAllowedByPolicyViaLibrary` with unauthorized initiator.
        bool allowed =
            harness.isERC1271SignatureAllowedByPolicyViaLibrary(ACCOUNT, initiator2, DEFAULT_POLICY_ID, proofs);

        // Verify: unauthorized initiators should fail closed.
        assertFalse(allowed, "unauthorized initiator should return false");
    }

    /// @dev Verifies that all policy checks passing returns true.
    function test_isERC1271SignatureAllowedByPolicy_allChecksPass_returnsTrue() public {
        // Setup: build fully valid baseline fixture.
        (, ValidationProofs memory proofs) = _buildAllowedFixture();

        // Call: execute `isERC1271SignatureAllowedByPolicyViaLibrary` with valid account + initiator + proofs.
        bool allowed =
            harness.isERC1271SignatureAllowedByPolicyViaLibrary(ACCOUNT, initiator1, DEFAULT_POLICY_ID, proofs);

        // Verify: all checks passing should authorize signature validation.
        assertTrue(allowed, "all checks passing should return true");
    }

    /// @dev Verifies that policy-proof failure short-circuits composite failing inputs.
    function test_isERC1271SignatureAllowedByPolicy_firstCheckPolicyProofFailure_failsClosed() public {
        // Setup: build fixture with multiple failing conditions, including invalid policy proof.
        (Policy memory policy, ValidationProofs memory proofs) = _buildAllowedFixture();
        policy.config.transactionType = TransactionType.TokenTransfers;
        proofs.policy = policy;
        proofs.policyProof = new bytes32[](1);
        proofs.policyProof[0] = keccak256("bad-proof-short-circuit");

        // Call: execute `isERC1271SignatureAllowedByPolicyViaLibrary` on the multi-failure payload.
        bool allowed =
            harness.isERC1271SignatureAllowedByPolicyViaLibrary(OTHER_ACCOUNT, initiator2, DEFAULT_POLICY_ID, proofs);

        // Verify: proof failure should fail closed for the entire check sequence.
        assertFalse(allowed, "invalid policy proof should fail closed");
    }

    /// @dev Verifies that empty source proofs fail when policy requires specific source accounts.
    function test_isERC1271SignatureAllowedByPolicy_emptySourceProofWithSpecificSource_returnsFalse() public {
        // Setup: build source-restricted policy but provide empty source proof.
        (Policy memory policy,) = _buildAllowedFixture();
        policy.config.anySourceAccount = false;
        policy.roots.sourceAccountsRoot = MerkleUtils.computeAddressLeaf(ACCOUNT);

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        proofs.sourceAccountProof = new bytes32[](0);

        // Call: execute `isERC1271SignatureAllowedByPolicyViaLibrary` without required source proof.
        bool allowed =
            harness.isERC1271SignatureAllowedByPolicyViaLibrary(OTHER_ACCOUNT, initiator1, DEFAULT_POLICY_ID, proofs);

        // Verify: missing required source proof should return false.
        assertFalse(allowed, "empty source proof for specific-source policy should fail");
    }

    /// @dev Verifies that `anyInitiator=true` still requires initiator membership.
    function test_isERC1271SignatureAllowedByPolicy_anyInitiatorStillRequiresMembership_returnsFalseForNonMember()
        public
    {
        // Setup: build valid fixture and enable `anyInitiator`.
        (Policy memory policy,) = _buildAllowedFixture();
        policy.config.initiator.anyInitiator = true;
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        address nonMember = address(0xF0F0);
        policyStateHarness.setMemberStatus(nonMember, false);

        // Call: execute `isERC1271SignatureAllowedByPolicyViaLibrary` for non-member initiator.
        bool allowed =
            harness.isERC1271SignatureAllowedByPolicyViaLibrary(ACCOUNT, nonMember, DEFAULT_POLICY_ID, proofs);

        // Verify: non-member initiators should remain unauthorized.
        assertFalse(allowed, "anyInitiator should still enforce membership");
    }

    /// @dev Verifies that group-based initiator authorization returns true for existing groups and members.
    function test_isERC1271SignatureAllowedByPolicy_groupInitiatorExistingGroupMember_returnsTrue() public {
        // Setup: build valid fixture and switch initiator auth to group membership.
        (Policy memory policy,) = _buildAllowedFixture();
        policy.config.initiator.anyInitiator = false;
        policy.config.initiator.initiatorType = ApproverType.Group;
        policy.config.initiator.initiatorGroupId = DEFAULT_GROUP_ID;

        policyStateHarness.setGroupStatus(DEFAULT_GROUP_ID, true);
        policyStateHarness.setGroupMemberStatus(DEFAULT_GROUP_ID, initiator1, true);

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        // Call: execute `isERC1271SignatureAllowedByPolicyViaLibrary` for group member initiator.
        bool allowed =
            harness.isERC1271SignatureAllowedByPolicyViaLibrary(ACCOUNT, initiator1, DEFAULT_POLICY_ID, proofs);

        // Verify: existing-group member initiators should be authorized.
        assertTrue(allowed, "group initiator should be authorized when in active group");
    }

    /// @dev Verifies that group-based initiator authorization returns false for non-existent groups.
    function test_isERC1271SignatureAllowedByPolicy_groupInitiatorMissingGroup_returnsFalse() public {
        // Setup: build valid fixture and switch initiator auth to a missing group id.
        (Policy memory policy,) = _buildAllowedFixture();
        policy.config.initiator.anyInitiator = false;
        policy.config.initiator.initiatorType = ApproverType.Group;
        policy.config.initiator.initiatorGroupId = DEFAULT_GROUP_ID;

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        // Call: execute `isERC1271SignatureAllowedByPolicyViaLibrary` with missing initiator group.
        bool allowed =
            harness.isERC1271SignatureAllowedByPolicyViaLibrary(ACCOUNT, initiator1, DEFAULT_POLICY_ID, proofs);

        // Verify: missing initiator groups should fail closed.
        assertFalse(allowed, "missing initiator group should return false");
    }

    /**
     * @dev Builds a baseline-valid policy/proof fixture for ERC-1271 signature authorization.
     */
    function _buildAllowedFixture() internal returns (Policy memory policy, ValidationProofs memory proofs) {
        policy = _buildSignaturePolicy(PolicyType.AutoApprove);
        policy.config.transactionType = TransactionType.Signatures;
        policy.config.anySourceAccount = true;
        policy.config.initiator.anyInitiator = false;
        policy.config.initiator.initiatorType = ApproverType.Member;
        policy.config.initiator.initiatorMember = initiator1;

        proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
    }
}
