// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {MerkleUtils} from "libraries/MerkleUtils.sol";
import {SignatureUtils} from "libraries/SignatureUtils.sol";

import {MockERC1271ValidSigner} from "test/helpers/MockERC1271Signers.sol";
import {MockGuardianSafe, MockGuardianSafeShortReturn} from "test/helpers/MockGuardianSafe.sol";
import {
    LibOrganizationAccountSignatureHarness
} from "test/organization/libraries/LibOrganizationAccountSignature/LibOrganizationAccountSignatureHarness.sol";
import {
    LibOrganizationAccountSignatureSuiteBase
} from "test/organization/libraries/LibOrganizationAccountSignature/LibOrganizationAccountSignatureSuiteBase.sol";
import {ApproverType, Policy, PolicyType, TransactionType, ValidationProofs} from "types/PolicyTypes.sol";

/**
 * @dev Policy-coupled ERC-1271 integration tests for `LibOrganizationAccountSignature`.
 *      Covers Section 10.2 IDs `LOAS-1` through `LOAS-29`.
 */
contract LibOrganizationAccountSignaturePolicyIntegrationTest is LibOrganizationAccountSignatureSuiteBase {
    uint256 internal constant DEFAULT_POLICY_ID = 177;

    address internal constant ACCOUNT = address(0xAA7701);
    bytes32 internal constant MESSAGE_HASH = keccak256("LOAS-policy-signature-message");

    function setUp() public override {
        super.setUp();

        policyStateHarness.setMemberStatus(initiator1, true);
        policyStateHarness.setMemberStatus(initiator2, true);
        policyStateHarness.setMemberStatus(reviewer1, true);
        policyStateHarness.setMemberStatus(reviewer2, true);
    }

    // LOAS-1
    function test_LOAS_1_validPolicyGuardianInitiatorAndApprovals_returnsMagicValue() public {
        policyStateHarness.setGuardian(guardianSigner);

        Policy memory policy = _buildSignaturePolicy(PolicyType.RequireManualApproval);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration
        });

        bytes memory reviewSignature = _signReviewSignature({
            sigHarness: harness,
            privateKey: REVIEWER_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });

        bytes memory guardianSignature = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });

        bytes memory signature = _buildPolicySignature({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature,
            reviewSignatures: reviewSignature,
            guardianSignature: guardianSignature,
            proofs: proofs
        });

        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "valid policy-based signature should return magic");
    }

    // LOAS-2
    function test_LOAS_2_expiredPolicyRequest_returnsInvalidValue() public {
        policyStateHarness.setGuardian(guardianSigner);

        Policy memory policy = _buildSignaturePolicy(PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        uint256 expiration = block.timestamp - 1;
        bytes memory initiatorSignature = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration
        });
        bytes memory guardianSignature = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });

        bytes memory signature = _buildPolicySignature({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            guardianSignature: guardianSignature,
            proofs: proofs
        });

        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "expired requests should be invalid");
    }

    // LOAS-3
    function test_LOAS_3_missingOrInvalidInitiatorSignature_returnsInvalidValue() public {
        policyStateHarness.setGuardian(guardianSigner);

        Policy memory policy = _buildSignaturePolicy(PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        uint256 expiration = block.timestamp + 1 days;
        bytes memory guardianSignature = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: bytes("")
        });

        bytes memory signature = _buildPolicySignature({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: bytes(""),
            reviewSignatures: bytes(""),
            guardianSignature: guardianSignature,
            proofs: proofs
        });

        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "missing initiator signature should be invalid");
    }

    // LOAS-4
    function test_LOAS_4_invalidGuardianSignature_returnsInvalidValue() public {
        policyStateHarness.setGuardian(guardianSigner);

        Policy memory policy = _buildSignaturePolicy(PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration
        });

        bytes memory wrongGuardianSignature = _signReviewSignature({
            sigHarness: harness,
            privateKey: REVIEWER_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });

        bytes memory signature = _buildPolicySignature({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            guardianSignature: wrongGuardianSignature,
            proofs: proofs
        });

        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "invalid guardian signatures should be rejected");
    }

    // LOAS-5
    function test_LOAS_5_enabledGuardianModuleSigner_isAccepted() public {
        MockGuardianSafe guardianSafe = new MockGuardianSafe();
        guardianSafe.setModuleEnabled(guardianSigner, true);
        policyStateHarness.setGuardian(address(guardianSafe));

        Policy memory policy = _buildSignaturePolicy(PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration
        });
        bytes memory moduleGuardianSignature = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });

        bytes memory signature = _buildPolicySignature({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            guardianSignature: moduleGuardianSignature,
            proofs: proofs
        });

        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "enabled module signer should be accepted");
    }

    // LOAS-6
    function test_LOAS_6_disabledGuardianModuleSigner_returnsInvalidValue() public {
        MockGuardianSafe guardianSafe = new MockGuardianSafe();
        policyStateHarness.setGuardian(address(guardianSafe));

        Policy memory policy = _buildSignaturePolicy(PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration
        });
        bytes memory moduleGuardianSignature = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });

        bytes memory signature = _buildPolicySignature({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            guardianSignature: moduleGuardianSignature,
            proofs: proofs
        });

        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "disabled module signer should be rejected");
    }

    // LOAS-7
    function test_LOAS_7_nonSafeGuardianModulePath_failsClosed() public {
        policyStateHarness.setGuardian(address(0xBEEFCAFE));

        Policy memory policy = _buildSignaturePolicy(PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration
        });
        bytes memory guardianSignature = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });

        bytes memory signature = _buildPolicySignature({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            guardianSignature: guardianSignature,
            proofs: proofs
        });

        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "non-safe guardian module path should fail closed");
    }

    // LOAS-8
    function test_LOAS_8_guardianModuleShortReturn_failsClosed() public {
        MockGuardianSafeShortReturn shortReturnGuardian = new MockGuardianSafeShortReturn();
        policyStateHarness.setGuardian(address(shortReturnGuardian));

        Policy memory policy = _buildSignaturePolicy(PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration
        });
        bytes memory guardianSignature = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });

        bytes memory signature = _buildPolicySignature({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            guardianSignature: guardianSignature,
            proofs: proofs
        });

        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "short-return guardian module check should fail closed");
    }

    // LOAS-9
    function test_LOAS_9_invalidPolicyProof_returnsInvalidValue() public {
        policyStateHarness.setGuardian(guardianSigner);

        Policy memory policy = _buildSignaturePolicy(PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        proofs.policyProof = new bytes32[](1);
        proofs.policyProof[0] = keccak256("tamper");

        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration
        });
        bytes memory guardianSignature = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });

        bytes memory signature = _buildPolicySignature({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            guardianSignature: guardianSignature,
            proofs: proofs
        });

        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "invalid policy proof should be rejected");
    }

    // LOAS-10
    function test_LOAS_10_nonSignatureTransactionTypePolicy_returnsInvalidValue() public {
        policyStateHarness.setGuardian(guardianSigner);

        Policy memory policy = _buildSignaturePolicy(PolicyType.AutoApprove);
        policy.config.transactionType = TransactionType.Any;
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration
        });
        bytes memory guardianSignature = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });

        bytes memory signature = _buildPolicySignature({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            guardianSignature: guardianSignature,
            proofs: proofs
        });

        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "non-signature txType policies should be rejected");
    }

    // LOAS-11
    function test_LOAS_11_sourceAccountNotAllowed_returnsInvalidValue() public {
        policyStateHarness.setGuardian(guardianSigner);

        Policy memory policy = _buildSignaturePolicy(PolicyType.AutoApprove);
        policy.config.anySourceAccount = false;
        policy.roots.sourceAccountsRoot = MerkleUtils.computeAddressLeaf(address(0xF00D));

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration
        });
        bytes memory guardianSignature = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });

        bytes memory signature = _buildPolicySignature({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            guardianSignature: guardianSignature,
            proofs: proofs
        });

        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "source-account mismatch should be rejected");
    }

    // LOAS-12
    function test_LOAS_12_unauthorizedInitiator_returnsInvalidValue() public {
        policyStateHarness.setGuardian(guardianSigner);

        Policy memory policy = _buildSignaturePolicy(PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        uint256 expiration = block.timestamp + 1 days;
        bytes memory unauthorizedInitiatorSignature = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_2,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration
        });
        bytes memory guardianSignature = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: unauthorizedInitiatorSignature
        });

        bytes memory signature = _buildPolicySignature({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: unauthorizedInitiatorSignature,
            reviewSignatures: bytes(""),
            guardianSignature: guardianSignature,
            proofs: proofs
        });

        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "unauthorized initiators should be rejected");
    }

    // LOAS-13
    function test_LOAS_13_autoApprovePolicyWithoutReviewSignatures_returnsMagicValue() public {
        policyStateHarness.setGuardian(guardianSigner);

        Policy memory policy = _buildSignaturePolicy(PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration
        });
        bytes memory guardianSignature = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });

        bytes memory signature = _buildPolicySignature({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            guardianSignature: guardianSignature,
            proofs: proofs
        });

        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "auto-approve should not require reviewer signatures");
    }

    // LOAS-14
    function test_LOAS_14_manualPolicyWithoutRequiredApprovals_returnsInvalidValue() public {
        policyStateHarness.setGuardian(guardianSigner);

        Policy memory policy = _buildSignaturePolicy(PolicyType.RequireManualApproval);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration
        });
        bytes memory guardianSignature = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });

        bytes memory signature = _buildPolicySignature({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            guardianSignature: guardianSignature,
            proofs: proofs
        });

        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "manual policy requires review signatures");
    }

    // LOAS-15
    function test_LOAS_15_reviewerApprovalsBoundToInitiatorSignatureBytes() public {
        policyStateHarness.setGuardian(guardianSigner);

        MockERC1271ValidSigner contractInitiator = new MockERC1271ValidSigner();
        policyStateHarness.setMemberStatus(address(contractInitiator), true);

        Policy memory policy = _buildSignaturePolicy(PolicyType.RequireManualApproval);
        policy.config.initiator.initiatorMember = address(contractInitiator);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        uint256 expiration = block.timestamp + 1 days;

        bytes memory initiatorSignatureA = _buildContractSignature(address(contractInitiator), hex"aaaa");
        bytes memory initiatorSignatureB = _buildContractSignature(address(contractInitiator), hex"bbbb");

        bytes memory reviewSignatureOverA = _signReviewSignature({
            sigHarness: harness,
            privateKey: REVIEWER_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignatureA
        });

        bytes memory guardianSignatureOverB = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignatureB
        });

        bytes memory signature = _buildPolicySignature({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignatureB,
            reviewSignatures: reviewSignatureOverA,
            guardianSignature: guardianSignatureOverB,
            proofs: proofs
        });

        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "review signatures must bind initiator signature bytes");
    }

    // LOAS-16
    function test_LOAS_16_isERC1271SignatureAllowedByPolicy_failsClosedOnAnyFailedSubCheck() public {
        Policy memory policy = _buildSignaturePolicy(PolicyType.AutoApprove);
        ValidationProofs memory validProofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        bool allowed =
            harness.isERC1271SignatureAllowedByPolicyViaLibrary(ACCOUNT, initiator1, DEFAULT_POLICY_ID, validProofs);
        assertTrue(allowed, "baseline should be allowed");

        ValidationProofs memory badProof = validProofs;
        badProof.policyProof = new bytes32[](1);
        badProof.policyProof[0] = keccak256("bad-proof");
        assertFalse(
            harness.isERC1271SignatureAllowedByPolicyViaLibrary(ACCOUNT, initiator1, DEFAULT_POLICY_ID, badProof),
            "invalid policy proof should fail closed"
        );

        ValidationProofs memory wrongTxTypeProofs = validProofs;
        wrongTxTypeProofs.policy.config.transactionType = TransactionType.Any;
        assertFalse(
            harness.isERC1271SignatureAllowedByPolicyViaLibrary(
                ACCOUNT, initiator1, DEFAULT_POLICY_ID, wrongTxTypeProofs
            ),
            "wrong transaction type should fail closed"
        );

        ValidationProofs memory sourceDeniedProofs = validProofs;
        sourceDeniedProofs.policy.config.anySourceAccount = false;
        sourceDeniedProofs.policy.roots.sourceAccountsRoot = MerkleUtils.computeAddressLeaf(address(0xDEAD));
        assertFalse(
            harness.isERC1271SignatureAllowedByPolicyViaLibrary(
                ACCOUNT, initiator1, DEFAULT_POLICY_ID, sourceDeniedProofs
            ),
            "source-account mismatch should fail closed"
        );

        ValidationProofs memory unauthorizedInitiatorProofs = validProofs;
        assertFalse(
            harness.isERC1271SignatureAllowedByPolicyViaLibrary(
                ACCOUNT, initiator2, DEFAULT_POLICY_ID, unauthorizedInitiatorProofs
            ),
            "unauthorized initiator should fail closed"
        );
    }

    // LOAS-17
    function test_LOAS_17_hashBuildersAreDeterministicAndFieldBound() public {
        uint256 expiration = block.timestamp + 1 days;

        bytes32 baseInitiatorHashA =
            harness.getInitiatorSignatureHashViaLibrary(ACCOUNT, MESSAGE_HASH, DEFAULT_POLICY_ID, expiration);
        bytes32 baseInitiatorHashB =
            harness.getInitiatorSignatureHashViaLibrary(ACCOUNT, MESSAGE_HASH, DEFAULT_POLICY_ID, expiration);
        assertEq(baseInitiatorHashA, baseInitiatorHashB, "initiator hash must be deterministic");

        assertTrue(
            baseInitiatorHashA
                != harness.getInitiatorSignatureHashViaLibrary(
                    address(uint160(ACCOUNT) + 1), MESSAGE_HASH, DEFAULT_POLICY_ID, expiration
                ),
            "account should be bound"
        );
        assertTrue(
            baseInitiatorHashA
                != harness.getInitiatorSignatureHashViaLibrary(
                    ACCOUNT, keccak256("different"), DEFAULT_POLICY_ID, expiration
                ),
            "message hash should be bound"
        );
        assertTrue(
            baseInitiatorHashA
                != harness.getInitiatorSignatureHashViaLibrary(
                    ACCOUNT, MESSAGE_HASH, DEFAULT_POLICY_ID + 1, expiration
                ),
            "policyId should be bound"
        );
        assertTrue(
            baseInitiatorHashA
                != harness.getInitiatorSignatureHashViaLibrary(
                    ACCOUNT, MESSAGE_HASH, DEFAULT_POLICY_ID, expiration + 1
                ),
            "expiration should be bound"
        );

        uint256 originalChainId = block.chainid;
        vm.chainId(originalChainId + 1);
        bytes32 chainChanged =
            harness.getInitiatorSignatureHashViaLibrary(ACCOUNT, MESSAGE_HASH, DEFAULT_POLICY_ID, expiration);
        vm.chainId(originalChainId);
        assertTrue(baseInitiatorHashA != chainChanged, "chainId should be bound");

        bytes memory initiatorSignatureA = _signHash(INITIATOR_PK_1, baseInitiatorHashA);
        bytes32 baseReviewHashA = harness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignatureA
        });
        bytes32 baseReviewHashB = harness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignatureA
        });
        assertEq(baseReviewHashA, baseReviewHashB, "review hash must be deterministic");

        bytes memory initiatorSignatureB = _signHash(INITIATOR_PK_2, baseInitiatorHashA);
        bytes32 changedReviewHash = harness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignatureB
        });
        assertTrue(baseReviewHashA != changedReviewHash, "review hash must bind initiator signature bytes");
    }

    // LOAS-18 (desired behavior)
    function test_LOAS_18_desired_malformedSignatureDataReturnsInvalidWithoutRevert() public {
        bytes memory malformed = abi.encodePacked(uint8(0x01), hex"deadbeef");
        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, malformed);
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "malformed payload should fail closed");
    }

    // LOAS-19 (desired behavior)
    function test_LOAS_19_desired_manualApprovalValidationRevertsMustReturnInvalidWithoutRevert() public {
        policyStateHarness.setGuardian(guardianSigner);

        Policy memory policy = _buildSignaturePolicy(PolicyType.RequireManualApproval);
        policy.config.approval.approverType = ApproverType.Group;
        policy.config.approval.approverGroupId = 519;
        policy.config.approval.approvalThreshold = 2;

        policyStateHarness.setGroupStatus(519, true);
        policyStateHarness.setGroupMemberStatus(519, reviewer1, true);

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        uint256 expiration = block.timestamp + 1 days;

        bytes memory initiatorSignature = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration
        });

        bytes memory duplicateReviewSig = _signReviewSignature({
            sigHarness: harness,
            privateKey: REVIEWER_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });

        bytes memory reviewSignatures = abi.encodePacked(duplicateReviewSig, duplicateReviewSig);
        bytes memory guardianSignature = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });

        bytes memory signature = _buildPolicySignature({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature,
            reviewSignatures: reviewSignatures,
            guardianSignature: guardianSignature,
            proofs: proofs
        });

        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "reverting review validation should fail closed");
    }

    // LOAS-20
    function test_LOAS_20_rootTransitionGuard_clearRootInvalidatesOldPolicyProof() public {
        policyStateHarness.setGuardian(guardianSigner);

        Policy memory policy = _buildSignaturePolicy(PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration
        });
        bytes memory guardianSignature = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });
        bytes memory signature = _buildPolicySignature({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            guardianSignature: guardianSignature,
            proofs: proofs
        });

        bytes4 beforeClear = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        assertEq(beforeClear, SignatureUtils.ERC1271_MAGIC_VALUE, "baseline should succeed before root clear");

        policyStateHarness.setPoliciesRoot(bytes32(0));

        bytes4 afterClear = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        assertEq(afterClear, SignatureUtils.ERC1271_INVALID_VALUE, "cleared root must invalidate old proofs");
    }

    // LOAS-21
    function test_LOAS_21_branchComparison_autoApproveMagic_manualWithoutReviewsInvalid() public {
        policyStateHarness.setGuardian(guardianSigner);

        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration
        });

        Policy memory autoPolicy = _buildSignaturePolicy(PolicyType.AutoApprove);
        ValidationProofs memory autoProofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, autoPolicy);
        bytes memory guardianSignatureAuto = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });
        bytes memory autoSig = _buildPolicySignature({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            guardianSignature: guardianSignatureAuto,
            proofs: autoProofs
        });

        assertEq(
            harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, autoSig),
            SignatureUtils.ERC1271_MAGIC_VALUE,
            "auto-approve should return magic"
        );

        Policy memory manualPolicy = _buildSignaturePolicy(PolicyType.RequireManualApproval);
        ValidationProofs memory manualProofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, manualPolicy);
        bytes memory guardianSignatureManual = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });
        bytes memory manualSig = _buildPolicySignature({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            guardianSignature: guardianSignatureManual,
            proofs: manualProofs
        });

        assertEq(
            harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, manualSig),
            SignatureUtils.ERC1271_INVALID_VALUE,
            "manual policy without reviews should be invalid"
        );
    }

    // LOAS-22
    function test_LOAS_22_branchComparison_manualWithReviewsAndAutoWithSamePayloadBothMagic() public {
        policyStateHarness.setGuardian(guardianSigner);

        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration
        });
        bytes memory reviewSignature = _signReviewSignature({
            sigHarness: harness,
            privateKey: REVIEWER_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });

        Policy memory manualPolicy = _buildSignaturePolicy(PolicyType.RequireManualApproval);
        ValidationProofs memory manualProofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, manualPolicy);
        bytes memory guardianSignatureManual = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });
        bytes memory manualSig = _buildPolicySignature({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature,
            reviewSignatures: reviewSignature,
            guardianSignature: guardianSignatureManual,
            proofs: manualProofs
        });

        assertEq(
            harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, manualSig),
            SignatureUtils.ERC1271_MAGIC_VALUE,
            "manual policy with valid reviews should return magic"
        );

        Policy memory autoPolicy = _buildSignaturePolicy(PolicyType.AutoApprove);
        ValidationProofs memory autoProofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, autoPolicy);
        bytes memory guardianSignatureAuto = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });
        bytes memory autoSig = _buildPolicySignature({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature,
            reviewSignatures: reviewSignature,
            guardianSignature: guardianSignatureAuto,
            proofs: autoProofs
        });

        assertEq(
            harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, autoSig),
            SignatureUtils.ERC1271_MAGIC_VALUE,
            "auto policy should still return magic with same review payload"
        );
    }

    // LOAS-23
    function test_LOAS_23_crossChainReplayInitiatorSignature_returnsInvalidValue() public {
        policyStateHarness.setGuardian(guardianSigner);

        Policy memory policy = _buildSignaturePolicy(PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        uint256 expiration = block.timestamp + 1 days;

        vm.chainId(1);
        bytes memory initiatorSignatureChainA = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration
        });

        vm.chainId(31_337);
        bytes memory guardianSignatureChainB = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignatureChainA
        });

        bytes memory signature = _buildPolicySignature({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignatureChainA,
            reviewSignatures: bytes(""),
            guardianSignature: guardianSignatureChainB,
            proofs: proofs
        });

        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "chain replayed initiator signature should fail");
    }

    // LOAS-24
    function test_LOAS_24_crossChainReplayGuardianAndReviewerSignatures_returnsInvalidValue() public {
        policyStateHarness.setGuardian(guardianSigner);

        Policy memory policy = _buildSignaturePolicy(PolicyType.RequireManualApproval);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        uint256 expiration = block.timestamp + 1 days;

        vm.chainId(31_337);
        bytes memory initiatorSignatureChainB = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration
        });

        vm.chainId(1);
        bytes memory reviewerSignatureChainA = _signReviewSignature({
            sigHarness: harness,
            privateKey: REVIEWER_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignatureChainB
        });
        bytes memory guardianSignatureChainA = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignatureChainB
        });

        vm.chainId(31_337);
        bytes memory signature = _buildPolicySignature({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignatureChainB,
            reviewSignatures: reviewerSignatureChainA,
            guardianSignature: guardianSignatureChainA,
            proofs: proofs
        });

        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        assertEq(
            actual, SignatureUtils.ERC1271_INVALID_VALUE, "chain replayed guardian/reviewer signatures should fail"
        );
    }

    // LOAS-25
    function test_LOAS_25_emptyTopLevelSignature_returnsInvalidValue() public {
        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, bytes(""));
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "empty top-level signature should be invalid");
    }

    // LOAS-26
    function test_LOAS_26_unknownSignatureTypePrefix_returnsInvalidValue() public {
        bytes memory signature = abi.encodePacked(uint8(0x7F), hex"AABBCC");
        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "unknown signature prefix should be invalid");
    }

    // LOAS-27
    function test_LOAS_27_invalidApprovalPolicyType_returnsInvalidValueFailClosed() public {
        policyStateHarness.setGuardian(guardianSigner);

        Policy memory policy = _buildSignaturePolicy(PolicyType.AutoApprove);
        _unsafeSetApprovalPolicyTypeRaw(policy, 2);

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        uint256 expiration = block.timestamp + 1 days;

        bytes memory initiatorSignature = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration
        });
        bytes memory guardianSignature = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });

        bytes memory signature = _buildPolicySignature({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            guardianSignature: guardianSignature,
            proofs: proofs
        });

        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "invalid approval enum should fail closed");
    }

    // LOAS-28
    function test_LOAS_28_crossOrganizationReplayInitiatorSignature_returnsInvalidValue() public {
        LibOrganizationAccountSignatureHarness orgB = new LibOrganizationAccountSignatureHarness();
        _seedMembers(address(orgB));

        policyStateHarness.setGuardian(guardianSigner);
        orgB.setGuardian(guardianSigner);

        Policy memory policy = _buildSignaturePolicy(PolicyType.AutoApprove);
        bytes32 root = _computePolicyLeaf(DEFAULT_POLICY_ID, policy);
        policyStateHarness.setPoliciesRoot(root);
        orgB.setPoliciesRoot(root);
        ValidationProofs memory proofs = _emptyProofsForPolicy(policy);

        uint256 expiration = block.timestamp + 1 days;

        bytes memory initiatorSignatureOrgA = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration
        });
        bytes memory guardianSignatureOrgB = _signGuardianReviewHash({
            sigHarness: orgB,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignatureOrgA
        });

        bytes memory signature = _buildPolicySignature({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignatureOrgA,
            reviewSignatures: bytes(""),
            guardianSignature: guardianSignatureOrgB,
            proofs: proofs
        });

        bytes4 actual = orgB.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "cross-org initiator replay should fail");
    }

    // LOAS-29
    function test_LOAS_29_crossOrganizationReplayGuardianAndReviewerSignatures_returnsInvalidValue() public {
        LibOrganizationAccountSignatureHarness orgB = new LibOrganizationAccountSignatureHarness();
        _seedMembers(address(orgB));

        policyStateHarness.setGuardian(guardianSigner);
        orgB.setGuardian(guardianSigner);

        Policy memory policy = _buildSignaturePolicy(PolicyType.RequireManualApproval);
        bytes32 root = _computePolicyLeaf(DEFAULT_POLICY_ID, policy);
        policyStateHarness.setPoliciesRoot(root);
        orgB.setPoliciesRoot(root);
        ValidationProofs memory proofs = _emptyProofsForPolicy(policy);

        uint256 expiration = block.timestamp + 1 days;

        bytes memory initiatorSignatureOrgB = _signInitiatorSignature({
            sigHarness: orgB,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration
        });

        bytes memory reviewerSignatureOrgA = _signReviewSignature({
            sigHarness: harness,
            privateKey: REVIEWER_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignatureOrgB
        });

        bytes memory guardianSignatureOrgA = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignatureOrgB
        });

        bytes memory signature = _buildPolicySignature({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignatureOrgB,
            reviewSignatures: reviewerSignatureOrgA,
            guardianSignature: guardianSignatureOrgA,
            proofs: proofs
        });

        bytes4 actual = orgB.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "cross-org guardian/reviewer replay should fail");
    }

    // Helpers

    function _buildSignaturePolicy(PolicyType approvalType) internal view returns (Policy memory policy) {
        policy = _buildBasePolicy();
        policy.config.transactionType = TransactionType.Signatures;
        policy.config.approval.policyType = approvalType;

        policy.config.initiator.anyInitiator = false;
        policy.config.initiator.initiatorType = ApproverType.Member;
        policy.config.initiator.initiatorMember = initiator1;

        policy.config.approval.approverType = ApproverType.Member;
        policy.config.approval.approverMember = reviewer1;
        policy.config.approval.approvalThreshold = 1;
    }

    function _emptyProofsForPolicy(Policy memory policy) internal pure returns (ValidationProofs memory proofs) {
        bytes32[] memory empty = new bytes32[](0);
        proofs = _buildValidationProofs(policy, empty, empty, empty, empty, bytes(""));
    }

    function _setSinglePolicyRootAndBuildProofs(uint256 policyId, Policy memory policy)
        internal
        returns (ValidationProofs memory proofs)
    {
        policyStateHarness.setPoliciesRoot(_computePolicyLeaf(policyId, policy));
        proofs = _emptyProofsForPolicy(policy);
    }

    function _buildPolicySignature(
        uint256 policyId,
        uint256 expirationTimestamp,
        bytes memory initiatorSignature,
        bytes memory reviewSignatures,
        bytes memory guardianSignature,
        ValidationProofs memory proofs
    ) internal pure returns (bytes memory) {
        bytes memory signatureData = abi.encode(
            policyId, expirationTimestamp, initiatorSignature, reviewSignatures, guardianSignature, proofs
        );
        return abi.encodePacked(uint8(0x01), signatureData);
    }

    // solhint-disable-next-line func-name-mixedcase
    function _signInitiatorSignature(
        LibOrganizationAccountSignatureHarness sigHarness,
        uint256 privateKey,
        address account,
        bytes32 hash,
        uint256 policyId,
        uint256 expirationTimestamp
    ) internal view returns (bytes memory) {
        bytes32 initiatorHash = sigHarness.getInitiatorSignatureHashViaLibrary(
            account, hash, policyId, expirationTimestamp
        );
        return _signHash(privateKey, initiatorHash);
    }

    // solhint-disable-next-line func-name-mixedcase
    function _signReviewSignature(
        LibOrganizationAccountSignatureHarness sigHarness,
        uint256 privateKey,
        address account,
        bytes32 hash,
        uint256 policyId,
        uint256 expirationTimestamp,
        bytes memory initiatorSignature
    ) internal view returns (bytes memory) {
        bytes32 reviewHash = sigHarness.getReviewSignatureHashViaLibrary(
            account, hash, policyId, expirationTimestamp, initiatorSignature
        );
        return _signHash(privateKey, reviewHash);
    }

    // solhint-disable-next-line func-name-mixedcase
    function _signGuardianReviewHash(
        LibOrganizationAccountSignatureHarness sigHarness,
        uint256 privateKey,
        address account,
        bytes32 hash,
        uint256 policyId,
        uint256 expirationTimestamp,
        bytes memory initiatorSignature
    ) internal view returns (bytes memory) {
        bytes32 reviewHash = sigHarness.getReviewSignatureHashViaLibrary(
            account, hash, policyId, expirationTimestamp, initiatorSignature
        );
        return _signHash(privateKey, reviewHash);
    }

    function _unsafeSetApprovalPolicyTypeRaw(Policy memory policy, uint256 rawValue) internal pure {
        // `Policy.config.approval.policyType` is at offset 0x80 in the in-memory `Policy` struct.
        assembly {
            mstore(add(policy, 0x80), rawValue)
        }
    }

    function _seedMembers(address target) internal {
        LibOrganizationAccountSignatureHarness targetHarness = LibOrganizationAccountSignatureHarness(target);
        targetHarness.setMemberStatus(initiator1, true);
        targetHarness.setMemberStatus(initiator2, true);
        targetHarness.setMemberStatus(reviewer1, true);
        targetHarness.setMemberStatus(reviewer2, true);
    }
}
