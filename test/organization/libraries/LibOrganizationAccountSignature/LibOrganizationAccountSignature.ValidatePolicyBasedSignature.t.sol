// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {SignatureUtils} from "libraries/SignatureUtils.sol";
import {MockERC1271ValidSigner} from "test/helpers/MockERC1271Signers.sol";
import {
    LibOrganizationAccountSignatureTestBase
} from "test/organization/libraries/LibOrganizationAccountSignature/LibOrganizationAccountSignatureTestBase.sol";
import {ApproverType, Policy, PolicyType, TransactionType, ValidationProofs} from "types/PolicyTypes.sol";

/**
 * @dev Unit tests for `LibOrganizationAccountSignature._validatePolicyBasedSignature`.
 */
contract LibOrganizationAccountSignatureValidatePolicyBasedSignatureTest is LibOrganizationAccountSignatureTestBase {
    struct PolicyValidationFixture {
        uint256 policyId;
        uint256 expirationTimestamp;
        Policy policy;
        ValidationProofs proofs;
        bytes initiatorSignature;
        bytes reviewSignatures;
        bytes guardianSignature;
        bytes signatureData;
    }

    /// @dev Verifies that valid ABI-encoded policy-signature payloads decode and validate successfully.
    function test_validatePolicyBasedSignature_validAbiEncodedPayload_decodesAndValidates() public {
        // Setup: build a fully valid auto-approve fixture.
        PolicyValidationFixture memory fixture = _buildPolicyValidationFixture({
            approvalType: PolicyType.AutoApprove, expirationTimestamp: block.timestamp + 1 days
        });

        // Call: execute `validatePolicyBasedSignatureViaLibrary` with the ABI-encoded payload.
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, fixture.signatureData);

        // Verify: valid ABI-encoded payloads should decode and return magic value.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "valid encoded payload should return magic");
    }

    /// @dev Verifies that expired policy-signature requests return ERC-1271 invalid value.
    function test_validatePolicyBasedSignature_expiredRequest_returnsInvalidValue() public {
        // Setup: build a fixture with expiration strictly before current block timestamp.
        PolicyValidationFixture memory fixture = _buildPolicyValidationFixture({
            approvalType: PolicyType.AutoApprove, expirationTimestamp: block.timestamp - 1
        });

        // Call: execute `validatePolicyBasedSignatureViaLibrary` with an expired payload.
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, fixture.signatureData);

        // Verify: expired payloads should fail closed.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "expired payload should be invalid");
    }

    /// @dev Verifies that expiration exactly at `block.timestamp` is accepted.
    function test_validatePolicyBasedSignature_expirationAtCurrentTimestamp_succeeds() public {
        // Setup: build a fixture where expiration equals `block.timestamp`.
        PolicyValidationFixture memory fixture =
            _buildPolicyValidationFixture({approvalType: PolicyType.AutoApprove, expirationTimestamp: block.timestamp});

        // Call: execute `validatePolicyBasedSignatureViaLibrary` at exact expiration boundary.
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, fixture.signatureData);

        // Verify: strict `>` expiry checks should accept equality boundary.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "expiration == block.timestamp should be valid");
    }

    /// @dev Verifies that expiration at `block.timestamp + 1` is accepted.
    function test_validatePolicyBasedSignature_expirationOneSecondInFuture_succeeds() public {
        // Setup: build a fixture where expiration is one second in the future.
        PolicyValidationFixture memory fixture = _buildPolicyValidationFixture({
            approvalType: PolicyType.AutoApprove, expirationTimestamp: block.timestamp + 1
        });

        // Call: execute `validatePolicyBasedSignatureViaLibrary` with near-future expiration.
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, fixture.signatureData);

        // Verify: near-future payloads should be accepted.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "future expiration should be valid");
    }

    /// @dev Verifies that empty initiator signatures return ERC-1271 invalid value.
    function test_validatePolicyBasedSignature_emptyInitiatorSignature_returnsInvalidValue() public {
        // Setup: build a valid fixture and clear initiator signature bytes.
        PolicyValidationFixture memory fixture = _buildPolicyValidationFixture({
            approvalType: PolicyType.AutoApprove, expirationTimestamp: block.timestamp + 1 days
        });
        fixture.signatureData = _buildPolicySignatureData({
            policyId: fixture.policyId,
            expirationTimestamp: fixture.expirationTimestamp,
            initiatorSignature: bytes(""),
            reviewSignatures: fixture.reviewSignatures,
            guardianSignature: fixture.guardianSignature,
            proofs: fixture.proofs
        });

        // Call: execute `validatePolicyBasedSignatureViaLibrary` with missing initiator signature.
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, fixture.signatureData);

        // Verify: empty initiator signatures must be rejected.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "empty initiator signature should be invalid");
    }

    /// @dev Verifies that malformed initiator signatures fail closed.
    function test_validatePolicyBasedSignature_malformedInitiatorSignature_returnsInvalidValue() public {
        // Setup: build a valid fixture and replace initiator signature with malformed bytes.
        PolicyValidationFixture memory fixture = _buildPolicyValidationFixture({
            approvalType: PolicyType.AutoApprove, expirationTimestamp: block.timestamp + 1 days
        });

        bytes memory malformedInitiator = hex"1b";
        bytes memory guardianSignature = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: fixture.policyId,
            expirationTimestamp: fixture.expirationTimestamp,
            initiatorSignature: malformedInitiator
        });

        fixture.signatureData = _buildPolicySignatureData({
            policyId: fixture.policyId,
            expirationTimestamp: fixture.expirationTimestamp,
            initiatorSignature: malformedInitiator,
            reviewSignatures: bytes(""),
            guardianSignature: guardianSignature,
            proofs: fixture.proofs
        });

        // Call: execute `validatePolicyBasedSignatureViaLibrary` with malformed initiator bytes.
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, fixture.signatureData);

        // Verify: unrecoverable initiator signatures should fail closed.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "malformed initiator signature should be invalid");
    }

    /// @dev Verifies that invalid guardian signatures return ERC-1271 invalid value.
    function test_validatePolicyBasedSignature_invalidGuardianSignature_returnsInvalidValue() public {
        // Setup: build a valid fixture and replace guardian signature with wrong signer.
        PolicyValidationFixture memory fixture = _buildPolicyValidationFixture({
            approvalType: PolicyType.AutoApprove, expirationTimestamp: block.timestamp + 1 days
        });

        bytes memory wrongGuardian = _signReviewSignature({
            sigHarness: harness,
            privateKey: REVIEWER_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: fixture.policyId,
            expirationTimestamp: fixture.expirationTimestamp,
            initiatorSignature: fixture.initiatorSignature
        });

        fixture.signatureData = _buildPolicySignatureData({
            policyId: fixture.policyId,
            expirationTimestamp: fixture.expirationTimestamp,
            initiatorSignature: fixture.initiatorSignature,
            reviewSignatures: fixture.reviewSignatures,
            guardianSignature: wrongGuardian,
            proofs: fixture.proofs
        });

        // Call: execute `validatePolicyBasedSignatureViaLibrary` with invalid guardian signature.
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, fixture.signatureData);

        // Verify: invalid guardian signatures must be rejected.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "invalid guardian signature should be rejected");
    }

    /// @dev Verifies that payloads not allowed by policy checks return ERC-1271 invalid value.
    function test_validatePolicyBasedSignature_policyNotAllowed_returnsInvalidValue() public {
        // Setup: build a valid fixture and tamper the policy proof to fail policy-in-org validation.
        PolicyValidationFixture memory fixture = _buildPolicyValidationFixture({
            approvalType: PolicyType.AutoApprove, expirationTimestamp: block.timestamp + 1 days
        });

        fixture.proofs.policyProof = new bytes32[](1);
        fixture.proofs.policyProof[0] = keccak256("tampered-proof");

        fixture.signatureData = _buildPolicySignatureData({
            policyId: fixture.policyId,
            expirationTimestamp: fixture.expirationTimestamp,
            initiatorSignature: fixture.initiatorSignature,
            reviewSignatures: fixture.reviewSignatures,
            guardianSignature: fixture.guardianSignature,
            proofs: fixture.proofs
        });

        // Call: execute `validatePolicyBasedSignatureViaLibrary` with disallowed policy proof.
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, fixture.signatureData);

        // Verify: policy-check failures should return invalid value.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "policy disallow should be invalid");
    }

    /// @dev Verifies that valid auto-approve policy signatures return ERC-1271 magic value.
    function test_validatePolicyBasedSignature_autoApproveValidSignatures_returnsMagicValue() public {
        // Setup: build a valid auto-approve fixture.
        PolicyValidationFixture memory fixture = _buildPolicyValidationFixture({
            approvalType: PolicyType.AutoApprove, expirationTimestamp: block.timestamp + 1 days
        });

        // Call: execute `validatePolicyBasedSignatureViaLibrary` with valid auto-approve payload.
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, fixture.signatureData);

        // Verify: auto-approve path should return magic when initiator + guardian are valid.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "valid auto-approve payload should return magic");
    }

    /// @dev Verifies that valid manual-approval signatures with threshold approvals return ERC-1271 magic value.
    function test_validatePolicyBasedSignature_manualApprovalWithSufficientReviews_returnsMagicValue() public {
        // Setup: build a valid manual-approval fixture with one valid reviewer signature.
        PolicyValidationFixture memory fixture = _buildPolicyValidationFixture({
            approvalType: PolicyType.RequireManualApproval, expirationTimestamp: block.timestamp + 1 days
        });

        // Call: execute `validatePolicyBasedSignatureViaLibrary` with valid manual-approval payload.
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, fixture.signatureData);

        // Verify: manual path should return magic when approval threshold is met.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "manual approvals meeting threshold should return magic");
    }

    /// @dev Verifies that manual-approval payloads with insufficient reviewer signatures return invalid value.
    function test_validatePolicyBasedSignature_manualApprovalInsufficientReviews_returnsInvalidValue() public {
        // Setup: build a valid manual fixture and clear review signatures.
        PolicyValidationFixture memory fixture = _buildPolicyValidationFixture({
            approvalType: PolicyType.RequireManualApproval, expirationTimestamp: block.timestamp + 1 days
        });

        fixture.signatureData = _buildPolicySignatureData({
            policyId: fixture.policyId,
            expirationTimestamp: fixture.expirationTimestamp,
            initiatorSignature: fixture.initiatorSignature,
            reviewSignatures: bytes(""),
            guardianSignature: fixture.guardianSignature,
            proofs: fixture.proofs
        });

        // Call: execute `validatePolicyBasedSignatureViaLibrary` with missing reviewer approvals.
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, fixture.signatureData);

        // Verify: manual path must reject payloads below approval threshold.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "missing manual approvals should be invalid");
    }

    /// @dev Verifies that manual reviewer signatures over a mismatched review hash are rejected.
    function test_validatePolicyBasedSignature_manualApprovalWrongReviewHash_returnsInvalidValue() public {
        // Setup: build manual policy fixture and sign reviewer approval over a different message hash.
        PolicyValidationFixture memory fixture = _buildPolicyValidationFixture({
            approvalType: PolicyType.RequireManualApproval, expirationTimestamp: block.timestamp + 1 days
        });

        bytes memory wrongReviewSignature = _signReviewSignature({
            sigHarness: harness,
            privateKey: REVIEWER_PK_1,
            account: ACCOUNT,
            hash: OTHER_MESSAGE_HASH,
            policyId: fixture.policyId,
            expirationTimestamp: fixture.expirationTimestamp,
            initiatorSignature: fixture.initiatorSignature
        });

        fixture.signatureData = _buildPolicySignatureData({
            policyId: fixture.policyId,
            expirationTimestamp: fixture.expirationTimestamp,
            initiatorSignature: fixture.initiatorSignature,
            reviewSignatures: wrongReviewSignature,
            guardianSignature: fixture.guardianSignature,
            proofs: fixture.proofs
        });

        // Call: execute `validatePolicyBasedSignatureViaLibrary` with mismatched review signature hash.
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, fixture.signatureData);

        // Verify: wrong-message review signatures should fail closed.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "review signatures must bind message + initiator");
    }

    /// @dev Verifies that review hash derivation is bound to the initiator signature bytes.
    function test_validatePolicyBasedSignature_reviewHashBindsInitiatorSignatureBytes() public {
        // Setup: compute review hashes for two different initiator signature byte arrays.
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorA = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration
        });
        bytes memory initiatorB = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_2,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration
        });

        // Call: execute review-hash builders for each initiator signature.
        bytes32 reviewHashA = harness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorA
        });
        bytes32 reviewHashB = harness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorB
        });

        // Verify: changing initiator signature bytes must change review hash.
        assertTrue(reviewHashA != reviewHashB, "review hash should bind initiator signature bytes");
    }

    /// @dev Verifies that representative failure paths return invalid without reverting.
    function test_validatePolicyBasedSignature_failurePaths_failClosedWithoutRevert() public {
        // Setup: build three failing fixtures (expired, empty initiator, unauthorized initiator) for graceful handling.
        PolicyValidationFixture memory expiredFixture = _buildPolicyValidationFixture({
            approvalType: PolicyType.AutoApprove, expirationTimestamp: block.timestamp - 1
        });

        PolicyValidationFixture memory emptyInitiatorFixture = _buildPolicyValidationFixture({
            approvalType: PolicyType.AutoApprove, expirationTimestamp: block.timestamp + 1 days
        });
        emptyInitiatorFixture.signatureData = _buildPolicySignatureData({
            policyId: emptyInitiatorFixture.policyId,
            expirationTimestamp: emptyInitiatorFixture.expirationTimestamp,
            initiatorSignature: bytes(""),
            reviewSignatures: bytes(""),
            guardianSignature: emptyInitiatorFixture.guardianSignature,
            proofs: emptyInitiatorFixture.proofs
        });

        PolicyValidationFixture memory unauthorizedFixture = _buildPolicyValidationFixture({
            approvalType: PolicyType.AutoApprove, expirationTimestamp: block.timestamp + 1 days
        });
        bytes memory unauthorizedInitiator = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_2,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: unauthorizedFixture.policyId,
            expirationTimestamp: unauthorizedFixture.expirationTimestamp
        });
        bytes memory unauthorizedGuardian = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: unauthorizedFixture.policyId,
            expirationTimestamp: unauthorizedFixture.expirationTimestamp,
            initiatorSignature: unauthorizedInitiator
        });
        unauthorizedFixture.signatureData = _buildPolicySignatureData({
            policyId: unauthorizedFixture.policyId,
            expirationTimestamp: unauthorizedFixture.expirationTimestamp,
            initiatorSignature: unauthorizedInitiator,
            reviewSignatures: bytes(""),
            guardianSignature: unauthorizedGuardian,
            proofs: unauthorizedFixture.proofs
        });

        // Call: execute low-level wrapper calls to capture graceful fail-closed behavior.
        (bool expiredSuccess, bytes memory expiredResult) = address(harness)
            .staticcall(
                abi.encodeCall(
                    harness.validatePolicyBasedSignatureViaLibrary,
                    (ACCOUNT, MESSAGE_HASH, expiredFixture.signatureData)
                )
            );
        (bool emptySuccess, bytes memory emptyResult) = address(harness)
            .staticcall(
                abi.encodeCall(
                    harness.validatePolicyBasedSignatureViaLibrary,
                    (ACCOUNT, MESSAGE_HASH, emptyInitiatorFixture.signatureData)
                )
            );
        (bool unauthorizedSuccess, bytes memory unauthorizedResult) = address(harness)
            .staticcall(
                abi.encodeCall(
                    harness.validatePolicyBasedSignatureViaLibrary,
                    (ACCOUNT, MESSAGE_HASH, unauthorizedFixture.signatureData)
                )
            );

        // Verify: all failure paths should return invalid value without reverting.
        assertTrue(expiredSuccess, "expired payload should fail closed without revert");
        assertTrue(emptySuccess, "empty-initiator payload should fail closed without revert");
        assertTrue(unauthorizedSuccess, "unauthorized-initiator payload should fail closed without revert");

        assertEq(abi.decode(expiredResult, (bytes4)), SignatureUtils.ERC1271_INVALID_VALUE, "expired should be invalid");
        assertEq(
            abi.decode(emptyResult, (bytes4)), SignatureUtils.ERC1271_INVALID_VALUE, "empty initiator should be invalid"
        );
        assertEq(
            abi.decode(unauthorizedResult, (bytes4)),
            SignatureUtils.ERC1271_INVALID_VALUE,
            "unauthorized initiator should be invalid"
        );
    }

    /// @dev Verifies that malformed ABI payloads revert during ABI decoding.
    function test_validatePolicyBasedSignature_malformedAbiPayload_reverts() public {
        // Setup: build malformed head-only data with out-of-bounds dynamic offsets.
        bytes memory malformed = abi.encode(
            uint256(DEFAULT_POLICY_ID),
            uint256(block.timestamp + 1 days),
            uint256(type(uint256).max),
            uint256(type(uint256).max),
            uint256(type(uint256).max),
            uint256(type(uint256).max)
        );

        // Verify: malformed payload triggers ABI decode revert.
        vm.expectRevert();
        // Call: execute wrapper with malformed payload.
        harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, malformed);
    }

    /// @dev Verifies that authorized ERC-1271 initiator contracts are accepted.
    function test_validatePolicyBasedSignature_authorizedERC1271Initiator_returnsMagicValue() public {
        // Setup: configure policy with ERC-1271 initiator member and valid guardian approval.
        policyStateHarness.setGuardian(guardianSigner);

        MockERC1271ValidSigner contractInitiator = new MockERC1271ValidSigner();
        policyStateHarness.setMemberStatus(address(contractInitiator), true);

        Policy memory policy = _buildSignaturePolicy(PolicyType.AutoApprove);
        policy.config.initiator.initiatorMember = address(contractInitiator);

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        uint256 expiration = block.timestamp + 1 days;

        bytes memory initiatorSignature = _buildContractSignature(address(contractInitiator), hex"CAFE");
        bytes memory guardianSignature = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });

        bytes memory signatureData = _buildPolicySignatureData({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            guardianSignature: guardianSignature,
            proofs: proofs
        });

        // Call: execute `validatePolicyBasedSignatureViaLibrary` with ERC-1271 initiator payload.
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signatureData);

        // Verify: authorized ERC-1271 initiator signatures should return magic.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "authorized ERC-1271 initiator should be accepted");
    }

    /// @dev Verifies that manual approvals accept authorized ERC-1271 reviewer signatures when threshold is met.
    function test_validatePolicyBasedSignature_manualApprovalWithERC1271Reviewers_returnsMagicValue() public {
        // Setup: configure manual group-approver policy with one EOA and one ERC-1271 reviewer.
        policyStateHarness.setGuardian(guardianSigner);

        MockERC1271ValidSigner contractReviewer = new MockERC1271ValidSigner();
        policyStateHarness.setMemberStatus(address(contractReviewer), true);

        Policy memory policy = _buildSignaturePolicy(PolicyType.RequireManualApproval);
        policy.config.approval.approverType = ApproverType.Group;
        policy.config.approval.approverGroupId = DEFAULT_GROUP_ID;
        policy.config.approval.approvalThreshold = 2;

        policyStateHarness.setGroupStatus(DEFAULT_GROUP_ID, true);
        policyStateHarness.setGroupMemberStatus(DEFAULT_GROUP_ID, reviewer1, true);
        policyStateHarness.setGroupMemberStatus(DEFAULT_GROUP_ID, address(contractReviewer), true);

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

        bytes memory eoaReviewSignature = _signReviewSignature({
            sigHarness: harness,
            privateKey: REVIEWER_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });
        bytes memory erc1271ReviewSignature = _buildContractSignature(address(contractReviewer), hex"BEEF");

        address[] memory signers = new address[](2);
        signers[0] = reviewer1;
        signers[1] = address(contractReviewer);

        bytes[] memory signatures = new bytes[](2);
        signatures[0] = eoaReviewSignature;
        signatures[1] = erc1271ReviewSignature;

        bytes memory packedReviewSignatures = _sortAndConcatSignatures(signers, signatures);
        bytes memory guardianSignature = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });

        bytes memory signatureData = _buildPolicySignatureData({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature,
            reviewSignatures: packedReviewSignatures,
            guardianSignature: guardianSignature,
            proofs: proofs
        });

        // Call: execute `validatePolicyBasedSignatureViaLibrary` with mixed reviewer signature encodings.
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signatureData);

        // Verify: authorized mixed EOA/ERC-1271 reviewer bundles should return magic.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "mixed authorized reviewers meeting threshold should pass");
    }

    /// @dev Verifies that manual member-approver policies accept the designated reviewer signature.
    function test_validatePolicyBasedSignature_manualMemberApproverValidReviewer_returnsMagicValue() public {
        // Setup: build manual fixture with member approver set to `reviewer1`.
        PolicyValidationFixture memory fixture = _buildPolicyValidationFixture({
            approvalType: PolicyType.RequireManualApproval, expirationTimestamp: block.timestamp + 1 days
        });
        fixture.policy.config.approval.approverType = ApproverType.Member;
        fixture.policy.config.approval.approverMember = reviewer1;
        fixture.proofs = _setSinglePolicyRootAndBuildProofs(fixture.policyId, fixture.policy);

        fixture.signatureData = _buildPolicySignatureData({
            policyId: fixture.policyId,
            expirationTimestamp: fixture.expirationTimestamp,
            initiatorSignature: fixture.initiatorSignature,
            reviewSignatures: fixture.reviewSignatures,
            guardianSignature: fixture.guardianSignature,
            proofs: fixture.proofs
        });

        // Call: execute `validatePolicyBasedSignatureViaLibrary` with designated-member reviewer signature.
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, fixture.signatureData);

        // Verify: designated member reviewer should satisfy manual approval.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "designated member reviewer should be accepted");
    }

    /// @dev Verifies that unknown approval policy-type enum values revert during enum decoding.
    function test_validatePolicyBasedSignature_unknownPolicyType_reverts() public {
        // Setup: build a valid policy signature then mutate encoded policyType enum to an unknown value.
        uint256 expiration = block.timestamp + 1 days;
        (bytes memory signature,,,,,) =
            _buildValidPolicySignature(PolicyType.AutoApprove, DEFAULT_POLICY_ID, expiration);
        _setPolicyTypeInPolicySignature(signature, 2);

        // Verify: unknown policy type triggers enum decode revert.
        vm.expectRevert();
        // Call: execute type-routed validation with unknown enum payload.
        harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);
    }

    /// @dev Verifies that malformed packed reviewer signature bytes fail closed with invalid value.
    function test_validatePolicyBasedSignature_malformedReviewSignatureBytes_returnsInvalidValue() public {
        // Setup: build manual fixture and replace packed reviewer signatures with malformed bytes.
        PolicyValidationFixture memory fixture = _buildPolicyValidationFixture({
            approvalType: PolicyType.RequireManualApproval, expirationTimestamp: block.timestamp + 1 days
        });

        fixture.signatureData = _buildPolicySignatureData({
            policyId: fixture.policyId,
            expirationTimestamp: fixture.expirationTimestamp,
            initiatorSignature: fixture.initiatorSignature,
            reviewSignatures: hex"1b",
            guardianSignature: fixture.guardianSignature,
            proofs: fixture.proofs
        });

        // Call: execute low-level wrapper call to assert no unexpected revert.
        (bool success, bytes memory result) = address(harness)
            .staticcall(
                abi.encodeCall(
                    harness.validatePolicyBasedSignatureViaLibrary, (ACCOUNT, MESSAGE_HASH, fixture.signatureData)
                )
            );

        // Verify: malformed review signature bytes should fail closed without revert.
        assertTrue(success, "malformed review signatures should not revert");
        assertEq(
            abi.decode(result, (bytes4)),
            SignatureUtils.ERC1271_INVALID_VALUE,
            "malformed review signatures should return invalid"
        );
    }

    /// @dev Verifies that duplicate or out-of-order reviewer signatures fail closed with invalid value.
    function test_validatePolicyBasedSignature_duplicateOrOutOfOrderReviewers_returnsInvalidValue() public {
        // Setup: configure manual group approvals and build duplicate reviewer signature bundle.
        policyStateHarness.setGuardian(guardianSigner);

        Policy memory policy = _buildSignaturePolicy(PolicyType.RequireManualApproval);
        policy.config.approval.approverType = ApproverType.Group;
        policy.config.approval.approverGroupId = DEFAULT_GROUP_ID;
        policy.config.approval.approvalThreshold = 2;

        policyStateHarness.setGroupStatus(DEFAULT_GROUP_ID, true);
        policyStateHarness.setGroupMemberStatus(DEFAULT_GROUP_ID, reviewer1, true);

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

        bytes memory guardianSignature = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });

        bytes memory signatureData = _buildPolicySignatureData({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature,
            reviewSignatures: abi.encodePacked(duplicateReviewSig, duplicateReviewSig),
            guardianSignature: guardianSignature,
            proofs: proofs
        });

        // Call: execute low-level wrapper call to assert no unexpected revert.
        (bool success, bytes memory result) = address(harness)
            .staticcall(
                abi.encodeCall(harness.validatePolicyBasedSignatureViaLibrary, (ACCOUNT, MESSAGE_HASH, signatureData))
            );

        // Verify: duplicate/out-of-order reviewer bundles should fail closed.
        assertTrue(success, "duplicate reviewer signatures should not revert");
        assertEq(
            abi.decode(result, (bytes4)),
            SignatureUtils.ERC1271_INVALID_VALUE,
            "duplicate reviewer signatures should return invalid"
        );
    }

    /// @dev Verifies that unauthorized reviewer signers fail closed with invalid value.
    function test_validatePolicyBasedSignature_unauthorizedReviewerSigner_returnsInvalidValue() public {
        // Setup: configure manual member-approver policy and sign review by a different reviewer.
        policyStateHarness.setGuardian(guardianSigner);

        Policy memory policy = _buildSignaturePolicy(PolicyType.RequireManualApproval);
        policy.config.approval.approverType = ApproverType.Member;
        policy.config.approval.approverMember = reviewer1;

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
        bytes memory unauthorizedReviewSig = _signReviewSignature({
            sigHarness: harness,
            privateKey: REVIEWER_PK_2,
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

        bytes memory signatureData = _buildPolicySignatureData({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature,
            reviewSignatures: unauthorizedReviewSig,
            guardianSignature: guardianSignature,
            proofs: proofs
        });

        // Call: execute low-level wrapper call to assert no unexpected revert.
        (bool success, bytes memory result) = address(harness)
            .staticcall(
                abi.encodeCall(harness.validatePolicyBasedSignatureViaLibrary, (ACCOUNT, MESSAGE_HASH, signatureData))
            );

        // Verify: unauthorized reviewers should fail closed with invalid value.
        assertTrue(success, "unauthorized reviewer payload should not revert");
        assertEq(
            abi.decode(result, (bytes4)),
            SignatureUtils.ERC1271_INVALID_VALUE,
            "unauthorized reviewer should return invalid"
        );
    }

    /// @dev Verifies that missing approver groups fail closed with invalid value.
    function test_validatePolicyBasedSignature_missingApproverGroup_returnsInvalidValue() public {
        // Setup: configure manual group-approver policy that points to a non-existent group.
        policyStateHarness.setGuardian(guardianSigner);

        Policy memory policy = _buildSignaturePolicy(PolicyType.RequireManualApproval);
        policy.config.approval.approverType = ApproverType.Group;
        policy.config.approval.approverGroupId = DEFAULT_GROUP_ID;
        policy.config.approval.approvalThreshold = 1;

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

        bytes memory signatureData = _buildPolicySignatureData({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature,
            reviewSignatures: reviewSignature,
            guardianSignature: guardianSignature,
            proofs: proofs
        });

        // Call: execute low-level wrapper call to assert no unexpected revert.
        (bool success, bytes memory result) = address(harness)
            .staticcall(
                abi.encodeCall(harness.validatePolicyBasedSignatureViaLibrary, (ACCOUNT, MESSAGE_HASH, signatureData))
            );

        // Verify: missing approver groups should fail closed with invalid value.
        assertTrue(success, "missing-group payload should not revert");
        assertEq(
            abi.decode(result, (bytes4)),
            SignatureUtils.ERC1271_INVALID_VALUE,
            "missing approver group should return invalid"
        );
    }

    /// @dev Verifies that valid policy signatures are stateless and repeatable before expiration.
    function test_validatePolicyBasedSignature_repeatedPreExpirationValidation_returnsStableMagic() public {
        // Setup: build a valid auto-approve fixture.
        PolicyValidationFixture memory fixture = _buildPolicyValidationFixture({
            approvalType: PolicyType.AutoApprove, expirationTimestamp: block.timestamp + 1 days
        });

        // Call: execute two identical validations with unchanged state.
        bytes4 first = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, fixture.signatureData);
        bytes4 second = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, fixture.signatureData);

        // Verify: repeated calls should remain valid and deterministic.
        assertEq(first, SignatureUtils.ERC1271_MAGIC_VALUE, "first validation should return magic");
        assertEq(second, SignatureUtils.ERC1271_MAGIC_VALUE, "second validation should return magic");
    }

    /**
     * @dev Builds a baseline-valid policy-validation fixture for the default account/hash constants.
     */
    function _buildPolicyValidationFixture(PolicyType approvalType, uint256 expirationTimestamp)
        internal
        returns (PolicyValidationFixture memory fixture)
    {
        fixture.policyId = DEFAULT_POLICY_ID;
        fixture.expirationTimestamp = expirationTimestamp;

        policyStateHarness.setGuardian(guardianSigner);

        fixture.policy = _buildSignaturePolicy(approvalType);
        fixture.proofs = _setSinglePolicyRootAndBuildProofs(fixture.policyId, fixture.policy);

        fixture.initiatorSignature = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: fixture.policyId,
            expirationTimestamp: expirationTimestamp
        });

        if (approvalType == PolicyType.RequireManualApproval) {
            fixture.reviewSignatures = _signReviewSignature({
                sigHarness: harness,
                privateKey: REVIEWER_PK_1,
                account: ACCOUNT,
                hash: MESSAGE_HASH,
                policyId: fixture.policyId,
                expirationTimestamp: expirationTimestamp,
                initiatorSignature: fixture.initiatorSignature
            });
        }

        fixture.guardianSignature = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: fixture.policyId,
            expirationTimestamp: expirationTimestamp,
            initiatorSignature: fixture.initiatorSignature
        });

        fixture.signatureData = _buildPolicySignatureData({
            policyId: fixture.policyId,
            expirationTimestamp: expirationTimestamp,
            initiatorSignature: fixture.initiatorSignature,
            reviewSignatures: fixture.reviewSignatures,
            guardianSignature: fixture.guardianSignature,
            proofs: fixture.proofs
        });
    }
}
