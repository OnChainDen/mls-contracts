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
 */
contract OrganizationAccountSignaturePolicyIntegrationTest is LibOrganizationAccountSignatureSuiteBase {
    uint256 internal constant DEFAULT_POLICY_ID = 177;

    address internal constant ACCOUNT = address(0xAA7701);
    bytes32 internal constant MESSAGE_HASH = keccak256("policy-signature-message");

    function setUp() public override {
        super.setUp();

        policyStateHarness.setMemberStatus(initiator1, true);
        policyStateHarness.setMemberStatus(initiator2, true);
        policyStateHarness.setMemberStatus(reviewer1, true);
        policyStateHarness.setMemberStatus(reviewer2, true);
    }

    /// @dev Verifies that valid policy guardian initiator and approvals returns magic value.
    function test_validPolicyGuardianInitiatorAndApprovals_returnsMagicValue() public {
        // Setup: configure a valid fixture for valid policy guardian initiator and approvals returns magic value.
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

        // Call: execute `isValidSignatureViaLibrary` with the happy-path payload.
        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        // Verify: assert the expected success result and state updates.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "valid policy-based signature should return magic");
    }

    /// @dev Verifies that expired policy request returns invalid value.
    function test_expiredPolicyRequest_returnsInvalidValue() public {
        // Setup: configure a valid fixture for expired policy request returns invalid value.
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

        // Call: execute `isValidSignatureViaLibrary` with the happy-path payload.
        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        // Verify: assert the expected success result and state updates.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "expired requests should be invalid");
    }

    /// @dev Verifies that missing or invalid initiator signature returns invalid value.
    function test_missingOrInvalidInitiatorSignature_returnsInvalidValue() public {
        // Setup: configure a valid fixture for missing or invalid initiator signature returns invalid value.
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

        // Call: execute `isValidSignatureViaLibrary` with the happy-path payload.
        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        // Verify: assert the expected success result and state updates.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "missing initiator signature should be invalid");
    }

    /// @dev Verifies that invalid guardian signature returns invalid value.
    function test_invalidGuardianSignature_returnsInvalidValue() public {
        // Setup: configure a valid fixture for invalid guardian signature returns invalid value.
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

        // Call: execute `isValidSignatureViaLibrary` with the happy-path payload.
        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        // Verify: assert the expected success result and state updates.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "invalid guardian signatures should be rejected");
    }

    /// @dev Verifies that enabled guardian module signer is accepted.
    function test_enabledGuardianModuleSigner_isAccepted() public {
        // Setup: configure a valid fixture for enabled guardian module signer is accepted.
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

        // Call: execute `isValidSignatureViaLibrary` with the happy-path payload.
        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        // Verify: assert the expected success result and state updates.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "enabled module signer should be accepted");
    }

    /// @dev Verifies that disabled guardian module signer returns invalid value.
    function test_disabledGuardianModuleSigner_returnsInvalidValue() public {
        // Setup: configure a valid fixture for disabled guardian module signer returns invalid value.
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

        // Call: execute `isValidSignatureViaLibrary` with the happy-path payload.
        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        // Verify: assert the expected success result and state updates.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "disabled module signer should be rejected");
    }

    /// @dev Verifies that non safe guardian module path fails closed.
    function test_nonSafeGuardianModulePath_failsClosed() public {
        // Setup: configure a valid fixture for non safe guardian module path fails closed.
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

        // Call: execute `isValidSignatureViaLibrary` with the happy-path payload.
        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        // Verify: assert the expected success result and state updates.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "non-safe guardian module path should fail closed");
    }

    /// @dev Verifies that guardian module short return fails closed.
    function test_guardianModuleShortReturn_failsClosed() public {
        // Setup: configure a valid fixture for guardian module short return fails closed.
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

        // Call: execute `isValidSignatureViaLibrary` with the happy-path payload.
        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        // Verify: assert the expected success result and state updates.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "short-return guardian module check should fail closed");
    }

    /// @dev Verifies that invalid policy proof returns invalid value.
    function test_invalidPolicyProof_returnsInvalidValue() public {
        // Setup: configure a valid fixture for invalid policy proof returns invalid value.
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

        // Call: execute `isValidSignatureViaLibrary` with the happy-path payload.
        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        // Verify: assert the expected success result and state updates.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "invalid policy proof should be rejected");
    }

    /// @dev Verifies that non signature transaction type policy returns invalid value.
    function test_nonSignatureTransactionTypePolicy_returnsInvalidValue() public {
        // Setup: configure a valid fixture for non signature transaction type policy returns invalid value.
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

        // Call: execute `isValidSignatureViaLibrary` with the happy-path payload.
        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        // Verify: assert the expected success result and state updates.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "non-signature txType policies should be rejected");
    }

    /// @dev Verifies that source account not allowed returns invalid value.
    function test_sourceAccountNotAllowed_returnsInvalidValue() public {
        // Setup: configure a valid fixture for source account not allowed returns invalid value.
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

        // Call: execute `isValidSignatureViaLibrary` with the happy-path payload.
        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        // Verify: assert the expected success result and state updates.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "source-account mismatch should be rejected");
    }

    /// @dev Verifies that unauthorized initiator returns invalid value.
    function test_unauthorizedInitiator_returnsInvalidValue() public {
        // Setup: configure a valid fixture for unauthorized initiator returns invalid value.
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

        // Call: execute `isValidSignatureViaLibrary` with the happy-path payload.
        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        // Verify: assert the expected success result and state updates.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "unauthorized initiators should be rejected");
    }

    /// @dev Verifies that auto approve policy without review signatures returns magic value.
    function test_autoApprovePolicyWithoutReviewSignatures_returnsMagicValue() public {
        // Setup: configure a valid fixture for auto approve policy without review signatures returns magic value.
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

        // Call: execute `isValidSignatureViaLibrary` with the happy-path payload.
        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        // Verify: assert the expected success result and state updates.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "auto-approve should not require reviewer signatures");
    }

    /// @dev Verifies that manual policy without required approvals returns invalid value.
    function test_manualPolicyWithoutRequiredApprovals_returnsInvalidValue() public {
        // Setup: configure a valid fixture for manual policy without required approvals returns invalid value.
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

        // Call: execute `isValidSignatureViaLibrary` with the happy-path payload.
        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        // Verify: assert the expected success result and state updates.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "manual policy requires review signatures");
    }

    /// @dev Verifies that reviewer approvals bound to initiator signature bytes.
    function test_reviewerApprovalsBoundToInitiatorSignatureBytes() public {
        // Setup: configure a valid fixture for reviewer approvals bound to initiator signature bytes.
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

        // Call: execute `isValidSignatureViaLibrary` with the happy-path payload.
        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        // Verify: assert the expected success result and state updates.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "review signatures must bind initiator signature bytes");
    }

    /// @dev Verifies that `isERC1271SignatureAllowedByPolicy` fails closed when any required sub-check fails.
    function test_isERC1271SignatureAllowedByPolicy_failsClosedOnAnyFailedSubCheck() public {
        // Setup: prepare a baseline-valid proof set plus targeted variants that each break one policy sub-check.
        Policy memory policy = _buildSignaturePolicy(PolicyType.AutoApprove);
        ValidationProofs memory validProofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        // Call: run `isERC1271SignatureAllowedByPolicyViaLibrary` across the prepared variants.
        bool allowed =
            harness.isERC1271SignatureAllowedByPolicyViaLibrary(ACCOUNT, initiator1, DEFAULT_POLICY_ID, validProofs);
        // Verify: assert each variant returns the expected branch outcome.
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

    /// @dev Verifies that hash builders are deterministic and field bound.
    function test_hashBuildersAreDeterministicAndFieldBound() public {
        // Setup: configure a valid fixture for hash builders are deterministic and field bound.
        uint256 expiration = block.timestamp + 1 days;

        // Call: execute `getInitiatorSignatureHashViaLibrary` with the happy-path payload.
        bytes32 baseInitiatorHashA =
            harness.getInitiatorSignatureHashViaLibrary(ACCOUNT, MESSAGE_HASH, DEFAULT_POLICY_ID, expiration);
        bytes32 baseInitiatorHashB =
            harness.getInitiatorSignatureHashViaLibrary(ACCOUNT, MESSAGE_HASH, DEFAULT_POLICY_ID, expiration);
        // Verify: assert the expected success result and state updates.
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

    /// @dev Verifies that malformed policy signature payload reverts during decoding.
    function test_malformedPolicySignatureData_invalidOffsets_reverts() public {
        // Setup: build a policy-signature payload with invalid dynamic offsets.
        bytes memory malformedPolicySignatureData = abi.encode(
            uint256(1), uint256(block.timestamp + 1 days), type(uint256).max, uint256(0), uint256(0), uint256(0)
        );
        bytes memory malformed = abi.encodePacked(uint8(0x01), malformedPolicySignatureData);

        // Verify: malformed payload should revert in the current implementation.
        vm.expectRevert();
        // Call: execute `isValidSignatureViaLibrary` with malformed policy-signature data.
        harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, malformed);
    }

    /// @dev Verifies that malformed policy signature payloads revert during policy decode.
    function test_malformedSignatureData_invalidAbiData_reverts() public {
        // Setup: build malformed policy signature payload with insufficient ABI data.
        bytes memory malformed = abi.encodePacked(uint8(0x01), hex"deadbeef");

        // Verify: malformed policy payloads should revert.
        vm.expectRevert();
        // Call: execute `isValidSignatureViaLibrary` with malformed payload.
        harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, malformed);
    }

    /// @dev Verifies that desired manual approval validation reverts must return invalid without revert.
    function test_desired_manualApprovalValidationRevertsMustReturnInvalidWithoutRevert() public {
        // Setup: configure a valid fixture for desired manual approval validation reverts must return invalid without
        // revert.
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

        // Call: execute `isValidSignatureViaLibrary` with the happy-path payload.
        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        // Verify: assert the expected success result and state updates.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "reverting review validation should fail closed");
    }

    /// @dev Verifies that root transition guard clear root invalidates old policy proof.
    function test_rootTransitionGuard_clearRootInvalidatesOldPolicyProof() public {
        // Setup: configure a valid fixture for root transition guard clear root invalidates old policy proof.
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

        // Call: execute `isValidSignatureViaLibrary` with the happy-path payload.
        bytes4 beforeClear = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        // Verify: assert the expected success result and state updates.
        assertEq(beforeClear, SignatureUtils.ERC1271_MAGIC_VALUE, "baseline should succeed before root clear");

        policyStateHarness.setPoliciesRoot(bytes32(0));

        bytes4 afterClear = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        assertEq(afterClear, SignatureUtils.ERC1271_INVALID_VALUE, "cleared root must invalidate old proofs");
    }

    /// @dev Verifies that branch comparison auto approve magic manual without reviews invalid.
    function test_branchComparison_autoApproveMagic_manualWithoutReviewsInvalid() public {
        // Setup: configure a valid fixture for branch comparison auto approve magic manual without reviews invalid.
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

        // Verify: assert the expected success result and state updates.
        assertEq(
            // Call: execute `isValidSignatureViaLibrary` with the happy-path payload.
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

    /// @dev Verifies that branch comparison manual with reviews and auto with same payload both magic.
    function test_branchComparison_manualWithReviewsAndAutoWithSamePayloadBothMagic() public {
        // Setup: configure a valid fixture for branch comparison manual with reviews and auto with same payload both
        // magic.
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

        // Verify: assert the expected success result and state updates.
        assertEq(
            // Call: execute `isValidSignatureViaLibrary` with the happy-path payload.
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

    /// @dev Verifies that cross chain replay initiator signature returns invalid value.
    function test_crossChainReplayInitiatorSignature_returnsInvalidValue() public {
        // Setup: configure a valid fixture for cross chain replay initiator signature returns invalid value.
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

        // Call: execute `isValidSignatureViaLibrary` with the happy-path payload.
        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        // Verify: assert the expected success result and state updates.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "chain replayed initiator signature should fail");
    }

    /// @dev Verifies that cross chain replay guardian and reviewer signatures returns invalid value.
    function test_crossChainReplayGuardianAndReviewerSignatures_returnsInvalidValue() public {
        // Setup: configure a valid fixture for cross chain replay guardian and reviewer signatures returns invalid
        // value.
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

        // Call: execute `isValidSignatureViaLibrary` with the happy-path payload.
        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        // Verify: assert the expected success result and state updates.
        assertEq(
            actual, SignatureUtils.ERC1271_INVALID_VALUE, "chain replayed guardian/reviewer signatures should fail"
        );
    }

    /// @dev Verifies that empty top level signature returns invalid value.
    function test_emptyTopLevelSignature_returnsInvalidValue() public {
        // Setup: configure a valid fixture for empty top level signature returns invalid value.
        // Call: execute `isValidSignatureViaLibrary` with the happy-path payload.
        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, bytes(""));
        // Verify: assert the expected success result and state updates.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "empty top-level signature should be invalid");
    }

    /// @dev Verifies that unknown signature type prefix returns invalid value.
    function test_unknownSignatureTypePrefix_returnsInvalidValue() public {
        // Setup: configure a valid fixture for unknown signature type prefix returns invalid value.
        bytes memory signature = abi.encodePacked(uint8(0x7F), hex"AABBCC");
        // Call: execute `isValidSignatureViaLibrary` with the happy-path payload.
        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
        // Verify: assert the expected success result and state updates.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "unknown signature prefix should be invalid");
    }

    /// @dev Verifies that invalid approval policy type in signature payload reverts.
    function test_invalidApprovalPolicyType_reverts() public {
        // Setup: configure a valid fixture and mutate encoded signature payload with an invalid enum value.
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
        _setPolicyTypeInPolicySignature(signature, 2);

        // Verify: malformed enum values revert during decode.
        vm.expectRevert();
        // Call: invoke `isValidSignatureViaLibrary` with malformed enum payload.
        harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
    }

    /// @dev Verifies that cross organization replay initiator signature returns invalid value.
    function test_crossOrganizationReplayInitiatorSignature_returnsInvalidValue() public {
        // Setup: configure a valid fixture for cross organization replay initiator signature returns invalid value.
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
        // Verify: assert the expected success result and state updates.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "cross-org initiator replay should fail");
    }

    /// @dev Verifies that cross organization replay guardian and reviewer signatures returns invalid value.
    function test_crossOrganizationReplayGuardianAndReviewerSignatures_returnsInvalidValue() public {
        // Setup: configure a valid fixture for cross organization replay guardian and reviewer signatures returns
        // invalid value.
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
        // Verify: assert the expected success result and state updates.
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
        proofs = ValidationProofs({
            policy: policy,
            policyProof: empty,
            sourceAccountProof: empty,
            destinationProof: empty,
            functionProof: empty,
            constraints: bytes("")
        });
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

    function _setPolicyTypeInPolicySignature(bytes memory signature, uint256 rawValue) internal pure {
        // policy-signature payload format:
        // 1-byte signature type prefix + abi.encode(policy tuple)
        // tuple head word[5] contains offset to `ValidationProofs`
        uint256 proofsOffset = _readWord(signature, 1 + 5 * 32);
        // Within `ValidationProofs`, `Policy.config.approval.policyType` is slot 4.
        _setWord(signature, 1 + proofsOffset + 4 * 32, rawValue);
    }

    function _seedMembers(address target) internal {
        LibOrganizationAccountSignatureHarness targetHarness = LibOrganizationAccountSignatureHarness(target);
        targetHarness.setMemberStatus(initiator1, true);
        targetHarness.setMemberStatus(initiator2, true);
        targetHarness.setMemberStatus(reviewer1, true);
        targetHarness.setMemberStatus(reviewer2, true);
    }
}
