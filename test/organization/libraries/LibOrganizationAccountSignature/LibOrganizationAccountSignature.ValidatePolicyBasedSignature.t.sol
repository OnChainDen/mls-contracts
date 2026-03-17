// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {BatchedTransaction} from "../../../../src/safe-module/BatchedTransaction.sol";
import {SafeExecutorModule} from "../../../../src/safe-module/SafeExecutorModule.sol";
import {SignatureUtils} from "libraries/SignatureUtils.sol";
import {MockERC1271ValidSigner} from "test/helpers/MockERC1271Signers.sol";
import {MockGuardianSafe} from "test/helpers/MockGuardianSafe.sol";
import {
    LibOrganizationAccountSignatureHarness
} from "test/organization/libraries/LibOrganizationAccountSignature/LibOrganizationAccountSignatureHarness.sol";
import {
    LibOrganizationAccountSignatureTestBase
} from "test/organization/libraries/LibOrganizationAccountSignature/LibOrganizationAccountSignatureTestBase.sol";
import {ApproverType, Policy, PolicyType, TransactionType, ValidationProofs} from "types/PolicyTypes.sol";

/**
 * @dev Unit tests for `LibOrganizationAccountSignature._validatePolicyBasedSignature`.
 */
contract LibOrganizationAccountSignatureValidatePolicyBasedSignatureTest is LibOrganizationAccountSignatureTestBase {
    uint256 internal constant AUTHORIZED_EXECUTOR_PK = 0xA11CE;
    uint256 internal constant OTHER_EXECUTOR_PK = 0xB0B;

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

    /// @dev Verifies missing or malformed guardian signature bytes return ERC-1271 invalid value.
    function test_validatePolicyBasedSignature_missingOrMalformedGuardianSignature_returnsInvalidValue() public {
        // Setup: build a valid auto-approve fixture, then replace guardian signatures with empty and malformed bytes.
        PolicyValidationFixture memory fixture = _buildPolicyValidationFixture({
            approvalType: PolicyType.AutoApprove, expirationTimestamp: block.timestamp + 1 days
        });

        bytes memory emptyGuardianPayload = _buildPolicySignatureData({
            policyId: fixture.policyId,
            expirationTimestamp: fixture.expirationTimestamp,
            initiatorSignature: fixture.initiatorSignature,
            reviewSignatures: fixture.reviewSignatures,
            guardianSignature: bytes(""),
            proofs: fixture.proofs
        });
        bytes memory malformedGuardianPayload = _buildPolicySignatureData({
            policyId: fixture.policyId,
            expirationTimestamp: fixture.expirationTimestamp,
            initiatorSignature: fixture.initiatorSignature,
            reviewSignatures: fixture.reviewSignatures,
            guardianSignature: hex"1b",
            proofs: fixture.proofs
        });

        // Call: execute validation for both malformed guardian-signature variants.
        bytes4 emptyResult = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, emptyGuardianPayload);
        bytes4 malformedResult =
            harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, malformedGuardianPayload);

        // Verify: guardian-signature decoding failures should fail closed.
        assertEq(emptyResult, SignatureUtils.ERC1271_INVALID_VALUE, "empty guardian signature should be invalid");
        assertEq(
            malformedResult, SignatureUtils.ERC1271_INVALID_VALUE, "malformed guardian signature should be invalid"
        );
    }

    /// @dev Verifies guardian signatures must be over the review hash, not the initiator hash.
    function test_validatePolicyBasedSignature_guardianSignatureOverInitiatorHash_returnsInvalidValue() public {
        // Setup: build a valid auto-approve fixture, then replace the guardian signature with one over the initiator
        // hash.
        PolicyValidationFixture memory fixture = _buildPolicyValidationFixture({
            approvalType: PolicyType.AutoApprove, expirationTimestamp: block.timestamp + 1 days
        });
        bytes32 initiatorHash = harness.getInitiatorSignatureHashViaLibrary(
            ACCOUNT, MESSAGE_HASH, fixture.policyId, fixture.expirationTimestamp
        );
        fixture.guardianSignature = _signHash(GUARDIAN_PK, initiatorHash);
        fixture.signatureData = _buildPolicySignatureData({
            policyId: fixture.policyId,
            expirationTimestamp: fixture.expirationTimestamp,
            initiatorSignature: fixture.initiatorSignature,
            reviewSignatures: fixture.reviewSignatures,
            guardianSignature: fixture.guardianSignature,
            proofs: fixture.proofs
        });

        // Call: execute validation with the guardian signature bound to the wrong message type hash.
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, fixture.signatureData);

        // Verify: guardian signatures over the initiator hash must be rejected.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "guardian signature must bind the review hash");
    }

    /// @dev Verifies manual reviewer signatures must be over the review hash, not the initiator hash.
    function test_validatePolicyBasedSignature_manualReviewerSignatureOverInitiatorHash_returnsInvalidValue() public {
        // Setup: build a valid manual-approval fixture, then replace the reviewer signature with one over the
        // initiator hash.
        PolicyValidationFixture memory fixture = _buildPolicyValidationFixture({
            approvalType: PolicyType.RequireManualApproval, expirationTimestamp: block.timestamp + 1 days
        });
        bytes32 initiatorHash = harness.getInitiatorSignatureHashViaLibrary(
            ACCOUNT, MESSAGE_HASH, fixture.policyId, fixture.expirationTimestamp
        );
        fixture.reviewSignatures = _signHash(REVIEWER_PK_1, initiatorHash);
        fixture.signatureData = _buildPolicySignatureData({
            policyId: fixture.policyId,
            expirationTimestamp: fixture.expirationTimestamp,
            initiatorSignature: fixture.initiatorSignature,
            reviewSignatures: fixture.reviewSignatures,
            guardianSignature: fixture.guardianSignature,
            proofs: fixture.proofs
        });

        // Call: execute validation with a reviewer signature bound to the wrong message type hash.
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, fixture.signatureData);

        // Verify: manual reviewer signatures over the initiator hash must be rejected.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "manual reviewer signature must bind the review hash");
    }

    /// @dev Verifies mutating the initiator signature invalidates both guardian and reviewer signatures via hash
    // binding.
    function test_validatePolicyBasedSignature_mutatedInitiatorSignature_invalidatesHashBoundSignatures() public {
        uint256 policyId = DEFAULT_POLICY_ID;
        uint256 expirationTimestamp = block.timestamp + 1 days;

        // --- Guardian invalidation (AutoApprove) ---
        // Setup: build a valid auto-approve fixture with `anyInitiator = true` so both signers are authorized.
        // Only guardian is checked (no reviewers), isolating the guardian hash-binding path.
        {
            policyStateHarness.setGuardian(guardianSigner);
            Policy memory autoPolicy = _buildSignaturePolicy(PolicyType.AutoApprove);
            autoPolicy.config.initiator.anyInitiator = true;
            ValidationProofs memory autoProofs = _setSinglePolicyRootAndBuildProofs(policyId, autoPolicy);

            bytes memory originalInitiatorSig = _signInitiatorSignature({
                sigHarness: harness,
                privateKey: INITIATOR_PK_1,
                account: ACCOUNT,
                hash: MESSAGE_HASH,
                policyId: policyId,
                expirationTimestamp: expirationTimestamp
            });

            bytes memory guardianSig = _signGuardianReviewHash({
                sigHarness: harness,
                privateKey: GUARDIAN_PK,
                account: ACCOUNT,
                hash: MESSAGE_HASH,
                policyId: policyId,
                expirationTimestamp: expirationTimestamp,
                initiatorSignature: originalInitiatorSig
            });

            bytes memory validPayload = _buildPolicySignatureData({
                policyId: policyId,
                expirationTimestamp: expirationTimestamp,
                initiatorSignature: originalInitiatorSig,
                reviewSignatures: new bytes(0),
                guardianSignature: guardianSig,
                proofs: autoProofs
            });
            assertEq(
                harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, validPayload),
                SignatureUtils.ERC1271_MAGIC_VALUE,
                "sanity: auto-approve baseline should be valid"
            );

            // Call: swap in a different (authorized) initiator signature without re-signing guardian.
            bytes memory mutatedInitiatorSig = _signInitiatorSignature({
                sigHarness: harness,
                privateKey: INITIATOR_PK_2,
                account: ACCOUNT,
                hash: MESSAGE_HASH,
                policyId: policyId,
                expirationTimestamp: expirationTimestamp
            });

            bytes memory mutatedPayload = _buildPolicySignatureData({
                policyId: policyId,
                expirationTimestamp: expirationTimestamp,
                initiatorSignature: mutatedInitiatorSig,
                reviewSignatures: new bytes(0),
                guardianSignature: guardianSig,
                proofs: autoProofs
            });

            // Verify: guardian signature is invalidated because the review hash changed with the initiator signature.
            assertEq(
                harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, mutatedPayload),
                SignatureUtils.ERC1271_INVALID_VALUE,
                "guardian should be invalidated when initiator signature mutates"
            );
        }

        // --- Reviewer invalidation (RequireManualApproval) ---
        // Setup: build a manual-approval fixture, mutate the initiator, re-sign the guardian over the new review hash,
        // but keep the original reviewer signatures to isolate the reviewer hash-binding path.
        {
            policyStateHarness.setGuardian(guardianSigner);
            Policy memory manualPolicy = _buildSignaturePolicy(PolicyType.RequireManualApproval);
            manualPolicy.config.initiator.anyInitiator = true;
            ValidationProofs memory manualProofs = _setSinglePolicyRootAndBuildProofs(policyId, manualPolicy);

            bytes memory originalInitiatorSig = _signInitiatorSignature({
                sigHarness: harness,
                privateKey: INITIATOR_PK_1,
                account: ACCOUNT,
                hash: MESSAGE_HASH,
                policyId: policyId,
                expirationTimestamp: expirationTimestamp
            });

            bytes memory reviewerSig = _signReviewSignature({
                sigHarness: harness,
                privateKey: REVIEWER_PK_1,
                account: ACCOUNT,
                hash: MESSAGE_HASH,
                policyId: policyId,
                expirationTimestamp: expirationTimestamp,
                initiatorSignature: originalInitiatorSig
            });

            bytes memory guardianSig = _signGuardianReviewHash({
                sigHarness: harness,
                privateKey: GUARDIAN_PK,
                account: ACCOUNT,
                hash: MESSAGE_HASH,
                policyId: policyId,
                expirationTimestamp: expirationTimestamp,
                initiatorSignature: originalInitiatorSig
            });

            bytes memory validPayload = _buildPolicySignatureData({
                policyId: policyId,
                expirationTimestamp: expirationTimestamp,
                initiatorSignature: originalInitiatorSig,
                reviewSignatures: reviewerSig,
                guardianSignature: guardianSig,
                proofs: manualProofs
            });
            assertEq(
                harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, validPayload),
                SignatureUtils.ERC1271_MAGIC_VALUE,
                "sanity: manual-approval baseline should be valid"
            );

            // Call: swap in a different (authorized) initiator signature and re-sign the guardian over the new review
            // hash, but keep the original (now stale) reviewer signatures.
            bytes memory mutatedInitiatorSig = _signInitiatorSignature({
                sigHarness: harness,
                privateKey: INITIATOR_PK_2,
                account: ACCOUNT,
                hash: MESSAGE_HASH,
                policyId: policyId,
                expirationTimestamp: expirationTimestamp
            });

            bytes memory reBoundGuardianSig = _signGuardianReviewHash({
                sigHarness: harness,
                privateKey: GUARDIAN_PK,
                account: ACCOUNT,
                hash: MESSAGE_HASH,
                policyId: policyId,
                expirationTimestamp: expirationTimestamp,
                initiatorSignature: mutatedInitiatorSig
            });

            bytes memory mutatedPayload = _buildPolicySignatureData({
                policyId: policyId,
                expirationTimestamp: expirationTimestamp,
                initiatorSignature: mutatedInitiatorSig,
                reviewSignatures: reviewerSig,
                guardianSignature: reBoundGuardianSig,
                proofs: manualProofs
            });

            // Verify: reviewer signatures are invalidated because the review hash changed with the initiator signature.
            assertEq(
                harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, mutatedPayload),
                SignatureUtils.ERC1271_INVALID_VALUE,
                "reviewer should be invalidated when initiator signature mutates"
            );
        }
    }

    /// @dev Verifies mutating signed fields (account, hash, policyId, expirationTimestamp) invalidates authorization.
    function test_validatePolicyBasedSignature_mutatedSignedFields_returnInvalidValue() public {
        // Setup: build a valid manual-approval fixture with all signatures bound to one set of signed fields.
        PolicyValidationFixture memory fixture = _buildPolicyValidationFixture({
            approvalType: PolicyType.RequireManualApproval, expirationTimestamp: block.timestamp + 1 days
        });

        bytes memory mutatedPolicyIdPayload = _buildPolicySignatureData({
            policyId: fixture.policyId + 1,
            expirationTimestamp: fixture.expirationTimestamp,
            initiatorSignature: fixture.initiatorSignature,
            reviewSignatures: fixture.reviewSignatures,
            guardianSignature: fixture.guardianSignature,
            proofs: fixture.proofs
        });

        bytes memory mutatedExpirationPayload = _buildPolicySignatureData({
            policyId: fixture.policyId,
            expirationTimestamp: fixture.expirationTimestamp + 1,
            initiatorSignature: fixture.initiatorSignature,
            reviewSignatures: fixture.reviewSignatures,
            guardianSignature: fixture.guardianSignature,
            proofs: fixture.proofs
        });

        // Call: validate the original payload against mutated account/hash parameters, and mutated field payloads.
        bytes4 mutatedAccountResult =
            harness.validatePolicyBasedSignatureViaLibrary(OTHER_ACCOUNT, MESSAGE_HASH, fixture.signatureData);
        bytes4 mutatedHashResult =
            harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, OTHER_MESSAGE_HASH, fixture.signatureData);
        bytes4 mutatedPolicyIdResult =
            harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, mutatedPolicyIdPayload);
        bytes4 mutatedExpirationResult =
            harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, mutatedExpirationPayload);

        // Verify: any mutation of a signed field invalidates authorization.
        assertEq(mutatedAccountResult, SignatureUtils.ERC1271_INVALID_VALUE, "account mutation should be invalid");
        assertEq(mutatedHashResult, SignatureUtils.ERC1271_INVALID_VALUE, "message-hash mutation should be invalid");
        assertEq(mutatedPolicyIdResult, SignatureUtils.ERC1271_INVALID_VALUE, "policy-id mutation should be invalid");
        assertEq(mutatedExpirationResult, SignatureUtils.ERC1271_INVALID_VALUE, "expiration mutation should be invalid");
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

    /// @dev Verifies policy-proof and source-account-proof mismatches return ERC-1271 invalid value.
    function test_validatePolicyBasedSignature_policyOrSourceAccountMismatch_returnsInvalidValue() public {
        // Setup: build one fixture with a tampered policy proof and one with a mismatched source-account proof.
        PolicyValidationFixture memory policyProofFixture = _buildPolicyValidationFixture({
            approvalType: PolicyType.AutoApprove, expirationTimestamp: block.timestamp + 1 days
        });
        policyProofFixture.proofs.policyProof = new bytes32[](1);
        policyProofFixture.proofs.policyProof[0] = keccak256("tampered-proof");
        bytes memory policyProofPayload = _buildPolicySignatureData({
            policyId: policyProofFixture.policyId,
            expirationTimestamp: policyProofFixture.expirationTimestamp,
            initiatorSignature: policyProofFixture.initiatorSignature,
            reviewSignatures: policyProofFixture.reviewSignatures,
            guardianSignature: policyProofFixture.guardianSignature,
            proofs: policyProofFixture.proofs
        });

        policyStateHarness.setGuardian(guardianSigner);
        Policy memory sourceRestrictedPolicy = _buildSignaturePolicy(PolicyType.AutoApprove);
        ValidationProofs memory sourceMismatchProofs = _buildSpecificSourceProofs(sourceRestrictedPolicy, ACCOUNT);
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: OTHER_ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration
        });
        bytes memory guardianSignature = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: OTHER_ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });
        bytes memory sourceProofPayload = _buildPolicySignatureData({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            guardianSignature: guardianSignature,
            proofs: sourceMismatchProofs
        });

        // Call: validate both proof-mismatch variants.
        bytes4 policyProofResult =
            harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, policyProofPayload);
        bytes4 sourceProofResult =
            harness.validatePolicyBasedSignatureViaLibrary(OTHER_ACCOUNT, MESSAGE_HASH, sourceProofPayload);

        // Verify: both proof mismatches should fail closed.
        assertEq(policyProofResult, SignatureUtils.ERC1271_INVALID_VALUE, "policy-proof mismatch should be invalid");
        assertEq(
            sourceProofResult, SignatureUtils.ERC1271_INVALID_VALUE, "source-account-proof mismatch should be invalid"
        );
    }

    /// @dev Verifies non-signature policies return ERC-1271 invalid value through policy validation.
    function test_validatePolicyBasedSignature_nonSignaturePolicy_returnsInvalidValue() public {
        // Setup: build a policy-proof fixture whose transaction type is not `Signatures`.
        policyStateHarness.setGuardian(guardianSigner);

        Policy memory policy = _buildBasePolicy();
        policy.config.transactionType = TransactionType.TokenTransfers;
        policy.config.initiator.anyInitiator = false;
        policy.config.initiator.initiatorType = ApproverType.Member;
        policy.config.initiator.initiatorMember = initiator1;

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
        bytes memory signatureData = _buildPolicySignatureData({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            guardianSignature: guardianSignature,
            proofs: proofs
        });

        // Call: validate the non-signature policy payload.
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signatureData);

        // Verify: policies for other transaction classes must not authorize ERC-1271 validation.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "non-signature policy should be invalid");
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

    /// @dev Verifies auto-approve policies ignore reviewer signature bytes when initiator and guardian signatures are
    /// valid.
    function test_validatePolicyBasedSignature_autoApproveIgnoresReviewSignatureBytes_returnsMagicValue() public {
        // Setup: build a valid auto-approve fixture, then inject arbitrary reviewer bytes.
        PolicyValidationFixture memory fixture = _buildPolicyValidationFixture({
            approvalType: PolicyType.AutoApprove, expirationTimestamp: block.timestamp + 1 days
        });
        fixture.reviewSignatures = hex"1b00ff";
        fixture.signatureData = _buildPolicySignatureData({
            policyId: fixture.policyId,
            expirationTimestamp: fixture.expirationTimestamp,
            initiatorSignature: fixture.initiatorSignature,
            reviewSignatures: fixture.reviewSignatures,
            guardianSignature: fixture.guardianSignature,
            proofs: fixture.proofs
        });

        // Call: execute validation with irrelevant reviewer bytes on the auto-approve path.
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, fixture.signatureData);

        // Verify: auto-approve policies require only the initiator and guardian signatures.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "auto-approve should ignore reviewer signature bytes");
    }

    /// @dev Verifies policy-based signatures valid on one organization fail on another organization.
    function test_validatePolicyBasedSignature_crossOrganizationReplay_returnsInvalidValue() public {
        // Setup: build a valid auto-approve fixture and mirror the same signer/policy state on another harness.
        PolicyValidationFixture memory fixture = _buildPolicyValidationFixture({
            approvalType: PolicyType.AutoApprove, expirationTimestamp: block.timestamp + 1 days
        });
        LibOrganizationAccountSignatureHarness otherHarness = new LibOrganizationAccountSignatureHarness();
        _seedMembers(address(otherHarness));
        otherHarness.setGuardian(guardianSigner);
        otherHarness.setPoliciesRoot(_computePolicyLeaf(fixture.policyId, fixture.policy));

        // Call: replay the valid signature data through the second organization harness.
        bytes4 actual =
            otherHarness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, fixture.signatureData);

        // Verify: the organization address is part of the EIP-712 domain, so cross-org replay must fail.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "cross-organization replay should be invalid");
    }

    /// @dev Verifies policy-based signatures valid on one chain fail after the chain id changes.
    function test_validatePolicyBasedSignature_crossChainReplay_returnsInvalidValue() public {
        // Setup: build a valid auto-approve fixture on the current chain.
        PolicyValidationFixture memory fixture = _buildPolicyValidationFixture({
            approvalType: PolicyType.AutoApprove, expirationTimestamp: block.timestamp + 1 days
        });
        uint256 originalChainId = block.chainid;

        // Call: replay the same signature data after mutating the chain id.
        vm.chainId(originalChainId + 1);
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, fixture.signatureData);
        vm.chainId(originalChainId);

        // Verify: the chain id is part of the EIP-712 domain, so cross-chain replay must fail.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "cross-chain replay should be invalid");
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

    /// @dev Verifies that strictly out-of-order reviewer signatures fail closed with invalid value.
    function test_validatePolicyBasedSignature_outOfOrderReviewers_returnsInvalidValue() public {
        // Setup: configure manual group approvals and build two valid reviewer signatures.
        policyStateHarness.setGuardian(guardianSigner);

        Policy memory policy = _buildSignaturePolicy(PolicyType.RequireManualApproval);
        policy.config.approval.approverType = ApproverType.Group;
        policy.config.approval.approverGroupId = DEFAULT_GROUP_ID;
        policy.config.approval.approvalThreshold = 2;

        policyStateHarness.setGroupStatus(DEFAULT_GROUP_ID, true);
        policyStateHarness.setGroupMemberStatus(DEFAULT_GROUP_ID, reviewer1, true);
        policyStateHarness.setGroupMemberStatus(DEFAULT_GROUP_ID, reviewer2, true);

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
        bytes memory reviewSignature1 = _signReviewSignature({
            sigHarness: harness,
            privateKey: REVIEWER_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });
        bytes memory reviewSignature2 = _signReviewSignature({
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

        bytes[] memory outOfOrderSignatures = new bytes[](2);
        if (uint160(reviewer1) < uint160(reviewer2)) {
            outOfOrderSignatures[0] = reviewSignature2;
            outOfOrderSignatures[1] = reviewSignature1;
        } else {
            outOfOrderSignatures[0] = reviewSignature1;
            outOfOrderSignatures[1] = reviewSignature2;
        }

        bytes memory signatureData = _buildPolicySignatureData({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature,
            reviewSignatures: _concatSignatures(outOfOrderSignatures),
            guardianSignature: guardianSignature,
            proofs: proofs
        });

        // Call: execute low-level wrapper call to assert no unexpected revert.
        (bool success, bytes memory result) = address(harness)
            .staticcall(
                abi.encodeCall(harness.validatePolicyBasedSignatureViaLibrary, (ACCOUNT, MESSAGE_HASH, signatureData))
            );

        // Verify: out-of-order reviewer bundles should fail closed.
        assertTrue(success, "out-of-order reviewer signatures should not revert");
        assertEq(
            abi.decode(result, (bytes4)),
            SignatureUtils.ERC1271_INVALID_VALUE,
            "out-of-order reviewer signatures should return invalid"
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

    /// @dev Verifies `_validatePolicyBasedSignature` accepts enabled module guardian signatures for auto-approve.
    function test_validatePolicyBasedSignature_enabledModuleGuardianAutoApprove_returnsMagicValue() public {
        // Setup: build an auto-approve fixture and replace the guardian with an enabled SafeExecutorModule.
        (PolicyValidationFixture memory fixture,) = _buildModuleGuardianFixture({
            approvalType: PolicyType.AutoApprove,
            expirationTimestamp: block.timestamp + 1 days,
            enableModule: true,
            moduleExecutorPk: AUTHORIZED_EXECUTOR_PK,
            innerSignerPk: AUTHORIZED_EXECUTOR_PK
        });

        // Call: validate the policy signature through the enabled module guardian path.
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, fixture.signatureData);

        // Verify: initiator plus enabled module guardian is sufficient for auto-approve.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "enabled module guardian should return magic");
    }

    /// @dev Verifies `_validatePolicyBasedSignature` rejects disabled module guardian signatures.
    function test_validatePolicyBasedSignature_disabledModuleGuardian_returnsInvalidValue() public {
        // Setup: build an auto-approve fixture with a disabled SafeExecutorModule guardian.
        (PolicyValidationFixture memory fixture,) = _buildModuleGuardianFixture({
            approvalType: PolicyType.AutoApprove,
            expirationTimestamp: block.timestamp + 1 days,
            enableModule: false,
            moduleExecutorPk: AUTHORIZED_EXECUTOR_PK,
            innerSignerPk: AUTHORIZED_EXECUTOR_PK
        });

        // Call: validate the policy signature while the module is disabled on the guardian Safe.
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, fixture.signatureData);

        // Verify: disabled modules fail closed even when the inner signature is correct.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "disabled module guardian should be invalid");
    }

    /// @dev Verifies manual approval still requires review signatures when guardian approval comes from a module.
    function test_validatePolicyBasedSignature_manualApprovalModuleGuardianStillNeedsReviews_returnsInvalidValue()
        public
    {
        // Setup: build a manual-approval fixture with an enabled module guardian and remove review signatures.
        (PolicyValidationFixture memory fixture,) = _buildModuleGuardianFixture({
            approvalType: PolicyType.RequireManualApproval,
            expirationTimestamp: block.timestamp + 1 days,
            enableModule: true,
            moduleExecutorPk: AUTHORIZED_EXECUTOR_PK,
            innerSignerPk: AUTHORIZED_EXECUTOR_PK
        });
        fixture.reviewSignatures = bytes("");
        fixture.signatureData = _buildPolicySignatureData({
            policyId: fixture.policyId,
            expirationTimestamp: fixture.expirationTimestamp,
            initiatorSignature: fixture.initiatorSignature,
            reviewSignatures: fixture.reviewSignatures,
            guardianSignature: fixture.guardianSignature,
            proofs: fixture.proofs
        });

        // Call: validate the manual-approval payload without any reviewer approvals.
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, fixture.signatureData);

        // Verify: the module guardian does not bypass manual reviewer requirements.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "manual approvals still require review signatures");
    }

    /// @dev Verifies invalid review signatures are rejected even when guardian approval comes from a module.
    function test_validatePolicyBasedSignature_manualApprovalModuleGuardianInvalidReviews_returnsInvalidValue() public {
        // Setup: build a manual-approval fixture with an enabled module guardian and swap in a wrong review hash.
        (PolicyValidationFixture memory fixture,) = _buildModuleGuardianFixture({
            approvalType: PolicyType.RequireManualApproval,
            expirationTimestamp: block.timestamp + 1 days,
            enableModule: true,
            moduleExecutorPk: AUTHORIZED_EXECUTOR_PK,
            innerSignerPk: AUTHORIZED_EXECUTOR_PK
        });
        fixture.reviewSignatures = _signReviewSignature({
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
            reviewSignatures: fixture.reviewSignatures,
            guardianSignature: fixture.guardianSignature,
            proofs: fixture.proofs
        });

        // Call: validate the manual-approval payload with an invalid reviewer signature bundle.
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, fixture.signatureData);

        // Verify: invalid reviewer signatures still cause rejection on the module guardian path.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "invalid review signatures should be rejected");
    }

    /// @dev Verifies module guardian signatures are bound to the initiator signature bytes.
    function test_validatePolicyBasedSignature_moduleGuardianSignatureBoundToInitiatorSignature_returnsInvalidValue()
        public
    {
        // Setup: build a valid module-guardian fixture, then swap in a different initiator signature without
        // re-signing.
        (PolicyValidationFixture memory fixture,) = _buildModuleGuardianFixture({
            approvalType: PolicyType.AutoApprove,
            expirationTimestamp: block.timestamp + 1 days,
            enableModule: true,
            moduleExecutorPk: AUTHORIZED_EXECUTOR_PK,
            innerSignerPk: AUTHORIZED_EXECUTOR_PK
        });
        bytes memory differentInitiatorSignature = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_2,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: fixture.policyId,
            expirationTimestamp: fixture.expirationTimestamp
        });
        fixture.initiatorSignature = differentInitiatorSignature;
        fixture.signatureData = _buildPolicySignatureData({
            policyId: fixture.policyId,
            expirationTimestamp: fixture.expirationTimestamp,
            initiatorSignature: fixture.initiatorSignature,
            reviewSignatures: fixture.reviewSignatures,
            guardianSignature: fixture.guardianSignature,
            proofs: fixture.proofs
        });

        // Call: validate the payload with a stale guardian module signature bound to the old initiator signature.
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, fixture.signatureData);

        // Verify: changing initiator signature bytes invalidates the guardian module signature.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "guardian module signature should bind initiator bytes");
    }

    /// @dev Verifies module guardian signatures over the wrong message hash are rejected.
    function test_validatePolicyBasedSignature_moduleGuardianWrongMessageHash_returnsInvalidValue() public {
        // Setup: build a valid module-guardian fixture and then replace the guardian signature with one over another
        // hash.
        (PolicyValidationFixture memory fixture, SafeExecutorModule module) = _buildModuleGuardianFixture({
            approvalType: PolicyType.AutoApprove,
            expirationTimestamp: block.timestamp + 1 days,
            enableModule: true,
            moduleExecutorPk: AUTHORIZED_EXECUTOR_PK,
            innerSignerPk: AUTHORIZED_EXECUTOR_PK
        });
        bytes memory wrongGuardianInnerSignature = _signReviewSignature({
            sigHarness: harness,
            privateKey: AUTHORIZED_EXECUTOR_PK,
            account: ACCOUNT,
            hash: OTHER_MESSAGE_HASH,
            policyId: fixture.policyId,
            expirationTimestamp: fixture.expirationTimestamp,
            initiatorSignature: fixture.initiatorSignature
        });
        fixture.guardianSignature = _buildContractSignature(address(module), wrongGuardianInnerSignature);
        fixture.signatureData = _buildPolicySignatureData({
            policyId: fixture.policyId,
            expirationTimestamp: fixture.expirationTimestamp,
            initiatorSignature: fixture.initiatorSignature,
            reviewSignatures: fixture.reviewSignatures,
            guardianSignature: fixture.guardianSignature,
            proofs: fixture.proofs
        });

        // Call: validate the payload whose module guardian signed a different review hash.
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, fixture.signatureData);

        // Verify: guardian module signatures must match the exact message hash under review.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "wrong-message guardian module signature should fail");
    }

    /// @dev Verifies unauthorized initiators still fail on the module guardian path.
    function test_validatePolicyBasedSignature_unauthorizedInitiatorWithModuleGuardian_returnsInvalidValue() public {
        // Setup: build an enabled-module fixture, then replace the initiator with an unauthorized signer and re-sign.
        (PolicyValidationFixture memory fixture, SafeExecutorModule module) = _buildModuleGuardianFixture({
            approvalType: PolicyType.AutoApprove,
            expirationTimestamp: block.timestamp + 1 days,
            enableModule: true,
            moduleExecutorPk: AUTHORIZED_EXECUTOR_PK,
            innerSignerPk: AUTHORIZED_EXECUTOR_PK
        });
        bytes memory unauthorizedInitiatorSignature = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_2,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: fixture.policyId,
            expirationTimestamp: fixture.expirationTimestamp
        });
        bytes memory guardianInnerSignature = _signReviewSignature({
            sigHarness: harness,
            privateKey: AUTHORIZED_EXECUTOR_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: fixture.policyId,
            expirationTimestamp: fixture.expirationTimestamp,
            initiatorSignature: unauthorizedInitiatorSignature
        });
        fixture.initiatorSignature = unauthorizedInitiatorSignature;
        fixture.guardianSignature = _buildContractSignature(address(module), guardianInnerSignature);
        fixture.signatureData = _buildPolicySignatureData({
            policyId: fixture.policyId,
            expirationTimestamp: fixture.expirationTimestamp,
            initiatorSignature: fixture.initiatorSignature,
            reviewSignatures: fixture.reviewSignatures,
            guardianSignature: fixture.guardianSignature,
            proofs: fixture.proofs
        });

        // Call: validate the payload with an unauthorized initiator and a valid module guardian signature.
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, fixture.signatureData);

        // Verify: policy authorization still gates the module guardian path.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "unauthorized initiator should remain invalid");
    }

    /// @dev Verifies the exact-expiration boundary is accepted on the module guardian path.
    function test_validatePolicyBasedSignature_expirationAtTimestampWithModuleGuardian_returnsMagicValue() public {
        // Setup: build an enabled-module auto-approve fixture with `expirationTimestamp == block.timestamp`.
        (PolicyValidationFixture memory fixture,) = _buildModuleGuardianFixture({
            approvalType: PolicyType.AutoApprove,
            expirationTimestamp: block.timestamp,
            enableModule: true,
            moduleExecutorPk: AUTHORIZED_EXECUTOR_PK,
            innerSignerPk: AUTHORIZED_EXECUTOR_PK
        });

        // Call: validate the payload at the strict expiry boundary.
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, fixture.signatureData);

        // Verify: exact equality with `block.timestamp` is still accepted.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "expiration boundary should remain valid");
    }

    /// @dev Verifies auto-approve ignores reviewer payload bytes even on the module guardian path.
    function test_validatePolicyBasedSignature_autoApproveIgnoresReviewSignaturesWithModuleGuardian_returnsMagicValue()
        public
    {
        // Setup: build an enabled-module auto-approve fixture and inject irrelevant reviewer bytes.
        (PolicyValidationFixture memory fixture,) = _buildModuleGuardianFixture({
            approvalType: PolicyType.AutoApprove,
            expirationTimestamp: block.timestamp + 1 days,
            enableModule: true,
            moduleExecutorPk: AUTHORIZED_EXECUTOR_PK,
            innerSignerPk: AUTHORIZED_EXECUTOR_PK
        });
        fixture.reviewSignatures = hex"1b00ff";
        fixture.signatureData = _buildPolicySignatureData({
            policyId: fixture.policyId,
            expirationTimestamp: fixture.expirationTimestamp,
            initiatorSignature: fixture.initiatorSignature,
            reviewSignatures: fixture.reviewSignatures,
            guardianSignature: fixture.guardianSignature,
            proofs: fixture.proofs
        });

        // Call: validate the auto-approve payload with ignored reviewer bytes populated.
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, fixture.signatureData);

        // Verify: auto-approve continues to depend only on the initiator and guardian module signatures.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "auto-approve should ignore review signatures");
    }

    /**
     * @dev Builds a baseline-valid policy-validation fixture that uses a `SafeExecutorModule` guardian.
     * @param approvalType Policy approval mode under test.
     * @param expirationTimestamp Expiration timestamp bound into the signatures.
     * @param enableModule Whether the guardian Safe should enable the deployed module.
     * @param moduleExecutorPk Private key configured as the module's authorized executor.
     * @param innerSignerPk Private key used to sign the inner guardian payload.
     * @return fixture Updated fixture using the module guardian path.
     * @return module Deployed module that validated the guardian signature.
     */
    function _buildModuleGuardianFixture(
        PolicyType approvalType,
        uint256 expirationTimestamp,
        bool enableModule,
        uint256 moduleExecutorPk,
        uint256 innerSignerPk
    ) internal returns (PolicyValidationFixture memory fixture, SafeExecutorModule module) {
        fixture = _buildPolicyValidationFixture(approvalType, expirationTimestamp);

        MockGuardianSafe guardianSafe = new MockGuardianSafe();
        module =
            new SafeExecutorModule(address(guardianSafe), vm.addr(moduleExecutorPk), address(new BatchedTransaction()));
        guardianSafe.setModuleEnabled(address(module), enableModule);
        policyStateHarness.setGuardian(address(guardianSafe));

        bytes memory guardianInnerSignature = _signReviewSignature({
            sigHarness: harness,
            privateKey: innerSignerPk,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: fixture.policyId,
            expirationTimestamp: fixture.expirationTimestamp,
            initiatorSignature: fixture.initiatorSignature
        });

        fixture.guardianSignature = _buildContractSignature(address(module), guardianInnerSignature);
        fixture.signatureData = _buildPolicySignatureData({
            policyId: fixture.policyId,
            expirationTimestamp: fixture.expirationTimestamp,
            initiatorSignature: fixture.initiatorSignature,
            reviewSignatures: fixture.reviewSignatures,
            guardianSignature: fixture.guardianSignature,
            proofs: fixture.proofs
        });
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
