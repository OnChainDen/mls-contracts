// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {BatchedTransaction} from "../../../../src/safe-module/BatchedTransaction.sol";
import {SafeExecutorModule} from "../../../../src/safe-module/SafeExecutorModule.sol";
import {SignatureUtils} from "libraries/SignatureUtils.sol";
import {MockERC1271ValidSigner} from "test/helpers/MockERC1271Signers.sol";
import {MockGuardianSafe} from "test/helpers/MockGuardianSafe.sol";
import {
    LibOrganizationAccountSignatureTestBase
} from "test/organization/libraries/LibOrganizationAccountSignature/LibOrganizationAccountSignatureTestBase.sol";
import {ApproverType, Policy, PolicyType, ValidationProofs} from "types/PolicyTypes.sol";

/**
 * @dev Fuzz tests for `LibOrganizationAccountSignature` behavior.
 */
contract LibOrganizationAccountSignatureFuzzTest is LibOrganizationAccountSignatureTestBase {
    uint256 internal constant AUTHORIZED_EXECUTOR_PK = 0xA11CE;

    /// @dev Verifies that random message hashes validate under a fully valid policy-signature fixture.
    function testFuzz_AS_FUZ_1_isValidSignature_randomHashesWithValidPolicySignature_returnsMagic(bytes32 randomMessageHash)
        public
    {
        // Setup: configure valid auto-approve fixture bound to fuzzed message hash.
        policyStateHarness.setGuardian(guardianSigner);

        Policy memory policy = _buildSignaturePolicy(PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        uint256 expiration = block.timestamp + 1 days;

        bytes memory initiatorSignature = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            hash: randomMessageHash,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration
        });
        bytes memory guardianSignature = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: randomMessageHash,
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

        // Call: execute `isValidSignatureViaLibrary` with fuzzed message hash.
        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, randomMessageHash, signature);

        // Verify: valid fixture should remain valid across random message hashes.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "valid policy fixture should return magic");
    }

    /// @dev Verifies that random unsupported type prefixes always return ERC-1271 invalid value.
    function testFuzz_AS_FUZ_2_isValidSignature_randomUnsupportedTypePrefixes_returnInvalid(
        uint8 typePrefix,
        bytes calldata payload
    ) public {
        // Setup: constrain fuzzed prefix away from supported values `0x00` and `0x01`.
        vm.assume(typePrefix != 0x00 && typePrefix != 0x01);

        bytes memory signature = abi.encodePacked(typePrefix, payload);

        // Call: execute `isValidSignatureViaLibrary` with unsupported type prefix.
        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);

        // Verify: unsupported prefixes should fail closed.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "unsupported type prefixes should be invalid");
    }

    /// @dev Verifies expiration behavior: future/equal timestamps pass, strictly past timestamps fail.
    function testFuzz_AS_FUZ_3_validatePolicyBasedSignature_randomExpirationTimestamp_futurePassPastFail(uint256 expirationTimestamp)
        public
    {
        // Setup: configure valid auto-approve fixture bound to fuzzed expiration timestamp.
        policyStateHarness.setGuardian(guardianSigner);

        Policy memory policy = _buildSignaturePolicy(PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        bytes memory initiatorSignature = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expirationTimestamp
        });
        bytes memory guardianSignature = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expirationTimestamp,
            initiatorSignature: initiatorSignature
        });

        bytes memory signatureData = _buildPolicySignatureData({
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expirationTimestamp,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            guardianSignature: guardianSignature,
            proofs: proofs
        });

        // Call: execute `validatePolicyBasedSignatureViaLibrary` with fuzzed expiration timestamp.
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signatureData);

        // Verify: strict `block.timestamp > expiration` semantics should hold.
        bytes4 expected = expirationTimestamp >= block.timestamp
            ? SignatureUtils.ERC1271_MAGIC_VALUE
            : SignatureUtils.ERC1271_INVALID_VALUE;
        assertEq(actual, expected, "expiration boundary behavior mismatch");
    }

    /// @dev Verifies that random policy IDs validate when matched with corresponding valid roots/proofs.
    function testFuzz_AS_FUZ_4_isValidSignature_randomPolicyIdsWithValidProofs_returnsMagic(uint256 policyIdRaw)
        public
    {
        // Setup: bound policy id to a non-zero range and build valid fixture around it.
        uint256 policyId = bound(policyIdRaw, 1, type(uint96).max);
        policyStateHarness.setGuardian(guardianSigner);

        Policy memory policy = _buildSignaturePolicy(PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(policyId, policy);
        uint256 expiration = block.timestamp + 1 days;

        bytes memory initiatorSignature = _signInitiatorSignature({
            sigHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: policyId,
            expirationTimestamp: expiration
        });
        bytes memory guardianSignature = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: policyId,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });

        bytes memory signature = _buildPolicySignature({
            policyId: policyId,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            guardianSignature: guardianSignature,
            proofs: proofs
        });

        // Call: execute `isValidSignatureViaLibrary` with fuzzed policy id fixture.
        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);

        // Verify: valid proof/root pair should authorize fuzzed policy id.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "valid policy proof fixture should return magic");
    }

    /// @dev Verifies that random guardian EOA keys are accepted when signer matches configured guardian.
    function testFuzz_AS_FUZ_5_isValidGuardianSignature_randomGuardianEOAKeyMatchingSigner_returnsTrue(uint256 guardianPkRaw)
        public
    {
        // Setup: derive bounded guardian private key and configure matching guardian address.
        uint256 guardianPk = bound(guardianPkRaw, 1, SECP256K1_CURVE_ORDER - 1);
        address guardian = vm.addr(guardianPk);
        policyStateHarness.setGuardian(guardian);

        bytes memory guardianSignature = _signHash(guardianPk, MESSAGE_HASH);

        // Call: execute `isValidGuardianSignatureViaLibrary` for matching guardian signer.
        bool actual = harness.isValidGuardianSignatureViaLibrary(guardianSignature, MESSAGE_HASH);

        // Verify: matching guardian EOAs should validate.
        assertTrue(actual, "matching guardian EOA should validate");
    }

    /// @dev Verifies that reviewer signature counts below threshold always fail manual approvals.
    function testFuzz_AS_FUZ_6_validatePolicyBasedSignature_reviewSignerCountsBelowThreshold_returnInvalid(uint8 signerCountRaw)
        public
    {
        // Setup: bound signer count below threshold and build manual group-approval fixture.
        uint256 signerCount = bound(uint256(signerCountRaw), 0, 2);
        policyStateHarness.setGuardian(guardianSigner);

        Policy memory policy = _buildSignaturePolicy(PolicyType.RequireManualApproval);
        policy.config.approval.approverType = ApproverType.Group;
        policy.config.approval.approverGroupId = DEFAULT_GROUP_ID;
        policy.config.approval.approvalThreshold = 3;

        policyStateHarness.setGroupStatus(DEFAULT_GROUP_ID, true);
        policyStateHarness.setGroupMemberStatus(DEFAULT_GROUP_ID, reviewer1, true);
        policyStateHarness.setGroupMemberStatus(DEFAULT_GROUP_ID, reviewer2, true);
        policyStateHarness.setGroupMemberStatus(DEFAULT_GROUP_ID, reviewer3, true);

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

        address[] memory signers = new address[](signerCount);
        bytes[] memory signatures = new bytes[](signerCount);

        if (signerCount > 0) {
            signers[0] = reviewer1;
            signatures[0] = _signReviewSignature({
                sigHarness: harness,
                privateKey: REVIEWER_PK_1,
                account: ACCOUNT,
                hash: MESSAGE_HASH,
                policyId: DEFAULT_POLICY_ID,
                expirationTimestamp: expiration,
                initiatorSignature: initiatorSignature
            });
        }
        if (signerCount > 1) {
            signers[1] = reviewer2;
            signatures[1] = _signReviewSignature({
                sigHarness: harness,
                privateKey: REVIEWER_PK_2,
                account: ACCOUNT,
                hash: MESSAGE_HASH,
                policyId: DEFAULT_POLICY_ID,
                expirationTimestamp: expiration,
                initiatorSignature: initiatorSignature
            });
        }

        bytes memory reviewSignatures = _sortAndConcatSignatures(signers, signatures);
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
            reviewSignatures: reviewSignatures,
            guardianSignature: guardianSignature,
            proofs: proofs
        });

        // Call: execute `validatePolicyBasedSignatureViaLibrary` with below-threshold reviewer bundle.
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signatureData);

        // Verify: below-threshold reviewer counts should always fail.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "below-threshold reviewer count should be invalid");
    }

    /// @dev Verifies random recovery signers: matching signer passes, non-matching signer fails.
    function testFuzz_AS_FUZ_7_validateRecoverySignature_randomRecoverySigner_matchPassMismatchFail(
        uint256 recoveryPkRaw,
        uint256 wrongPkRaw
    ) public {
        // Setup: derive distinct bounded private keys and configure recovery signer.
        uint256 recoveryPk = bound(recoveryPkRaw, 1, SECP256K1_CURVE_ORDER - 1);
        uint256 wrongPk = bound(wrongPkRaw, 1, SECP256K1_CURVE_ORDER - 1);
        vm.assume(recoveryPk != wrongPk);

        address recoverySigner = vm.addr(recoveryPk);
        _setTxRecoveryState(recoverySigner, true);

        bytes memory goodSignature = _signHash(recoveryPk, MESSAGE_HASH);
        bytes memory badSignature = _signHash(wrongPk, MESSAGE_HASH);

        // Call: execute recovery validation for matching and mismatching signatures.
        bytes4 good = harness.validateRecoverySignatureViaLibrary(MESSAGE_HASH, goodSignature);
        bytes4 bad = harness.validateRecoverySignatureViaLibrary(MESSAGE_HASH, badSignature);

        // Verify: matching recovery signer should pass; mismatching signer should fail.
        assertEq(good, SignatureUtils.ERC1271_MAGIC_VALUE, "matching recovery signer should return magic");
        assertEq(bad, SignatureUtils.ERC1271_INVALID_VALUE, "wrong recovery signer should return invalid");
    }

    /// @dev Verifies that different initiator signatures produce different review hashes.
    function testFuzz_AS_FUZ_8_getReviewSignatureHash_differentInitiatorSignatures_returnDifferentHashes(
        uint256 initiatorPkARaw,
        uint256 initiatorPkBRaw
    ) public view {
        // Setup: derive two distinct bounded private keys.
        uint256 initiatorPkA = bound(initiatorPkARaw, 1, SECP256K1_CURVE_ORDER - 1);
        uint256 initiatorPkB = bound(initiatorPkBRaw, 1, SECP256K1_CURVE_ORDER - 1);
        vm.assume(initiatorPkA != initiatorPkB);

        uint256 expiration = block.timestamp + 1 days;
        bytes32 initiatorHash =
            harness.getInitiatorSignatureHashViaLibrary(ACCOUNT, MESSAGE_HASH, DEFAULT_POLICY_ID, expiration);

        bytes memory initiatorSigA = _signHash(initiatorPkA, initiatorHash);
        bytes memory initiatorSigB = _signHash(initiatorPkB, initiatorHash);

        // Call: compute review hashes for both initiator signatures.
        bytes32 reviewHashA = harness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSigA
        });
        bytes32 reviewHashB = harness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSigB
        });

        // Verify: distinct initiator signatures should produce distinct review hashes.
        assertTrue(reviewHashA != reviewHashB, "different initiator signatures should change review hash");
    }

    /// @dev Verifies random account behavior for `anySourceAccount` versus specific-source policies.
    function testFuzz_AS_FUZ_9_isERC1271SignatureAllowedByPolicy_randomAccounts_anySourceVsSpecificSource(
        address accountA,
        address accountB
    ) public {
        // Setup: bound account inputs and build baseline signature policy fixture.
        vm.assume(accountA != address(0));
        vm.assume(accountB != address(0));
        vm.assume(accountA != accountB);

        Policy memory policy = _buildSignaturePolicy(PolicyType.AutoApprove);

        // Case A: any-source policy should allow both accounts.
        policy.config.anySourceAccount = true;
        ValidationProofs memory anySourceProofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        // Call: evaluate both accounts under any-source policy.
        bool anySourceA = harness.isERC1271SignatureAllowedByPolicyViaLibrary(
            accountA, initiator1, DEFAULT_POLICY_ID, anySourceProofs
        );
        bool anySourceB = harness.isERC1271SignatureAllowedByPolicyViaLibrary(
            accountB, initiator1, DEFAULT_POLICY_ID, anySourceProofs
        );

        // Verify: any-source policy should allow both accounts.
        assertTrue(anySourceA, "any-source policy should allow accountA");
        assertTrue(anySourceB, "any-source policy should allow accountB");

        // Case B: specific-source policy should allow only the configured account.
        policy.config.anySourceAccount = false;
        policy.roots.sourceAccountsRoot = _computeAddressLeaf(accountA);
        ValidationProofs memory specificSourceProofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        // Call: evaluate both accounts under specific-source policy.
        bool specificA = harness.isERC1271SignatureAllowedByPolicyViaLibrary(
            accountA, initiator1, DEFAULT_POLICY_ID, specificSourceProofs
        );
        bool specificB = harness.isERC1271SignatureAllowedByPolicyViaLibrary(
            accountB, initiator1, DEFAULT_POLICY_ID, specificSourceProofs
        );

        // Verify: specific-source policy should only allow the configured account.
        assertTrue(specificA, "specific-source policy should allow configured account");
        assertFalse(specificB, "specific-source policy should reject non-configured account");
    }

    /// @dev Verifies that changing message hash changes both initiator and review hashes.
    function testFuzz_AS_FUZ_10_hashBuilders_messageHashMutation_changesInitiatorAndReviewHashes(
        bytes32 hashA,
        bytes32 hashB
    ) public view {
        // Setup: ensure fuzzed message hashes are distinct.
        vm.assume(hashA != hashB);
        uint256 expiration = block.timestamp + 1 days;

        // Call: compute initiator/review hashes for each message hash variant.
        bytes32 initiatorHashA =
            harness.getInitiatorSignatureHashViaLibrary(ACCOUNT, hashA, DEFAULT_POLICY_ID, expiration);
        bytes memory initiatorSigA = _signHash(INITIATOR_PK_1, initiatorHashA);
        bytes32 reviewHashA = harness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: hashA,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSigA
        });

        bytes32 initiatorHashB =
            harness.getInitiatorSignatureHashViaLibrary(ACCOUNT, hashB, DEFAULT_POLICY_ID, expiration);
        bytes memory initiatorSigB = _signHash(INITIATOR_PK_1, initiatorHashB);
        bytes32 reviewHashB = harness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: hashB,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSigB
        });

        // Verify: changing message hash should change both derived hashes.
        assertTrue(initiatorHashA != initiatorHashB, "initiator hash should change with message hash");
        assertTrue(reviewHashA != reviewHashB, "review hash should change with message hash");
    }

    /// @dev Verifies that authorization outcome depends on policy authorization, not signature encoding mode.
    function testFuzz_AS_FUZ_12_validatePolicyBasedSignature_authorizedSignerMixes_dependOnAuthorizationNotEncoding(
        bool initiatorAsContract,
        bool reviewerAsContract,
        bool reviewerAuthorized
    ) public {
        // Setup: configure manual-member approval policy with fuzzed initiator/reviewer encoding choices.
        policyStateHarness.setGuardian(guardianSigner);

        Policy memory policy = _buildSignaturePolicy(PolicyType.RequireManualApproval);
        policy.config.approval.approverType = ApproverType.Member;

        uint256 expiration = block.timestamp + 1 days;

        address initiatorSigner = initiator1;
        bytes memory initiatorSignature;

        if (initiatorAsContract) {
            MockERC1271ValidSigner initiatorContract = new MockERC1271ValidSigner();
            initiatorSigner = address(initiatorContract);
            policyStateHarness.setMemberStatus(initiatorSigner, true);
            initiatorSignature = _buildContractSignature(initiatorSigner, hex"1111");
        } else {
            initiatorSignature = _signInitiatorSignature({
                sigHarness: harness,
                privateKey: INITIATOR_PK_1,
                account: ACCOUNT,
                hash: MESSAGE_HASH,
                policyId: DEFAULT_POLICY_ID,
                expirationTimestamp: expiration
            });
        }

        policy.config.initiator.initiatorMember = initiatorSigner;

        address reviewerSigner;
        bytes memory reviewSignature;
        if (reviewerAsContract) {
            MockERC1271ValidSigner reviewerContract = new MockERC1271ValidSigner();
            reviewerSigner = address(reviewerContract);
            policyStateHarness.setMemberStatus(reviewerSigner, true);
            reviewSignature = _buildContractSignature(reviewerSigner, hex"2222");
        } else {
            reviewerSigner = reviewerAuthorized ? reviewer1 : reviewer2;
            reviewSignature = _signReviewSignature({
                sigHarness: harness,
                privateKey: reviewerAuthorized ? REVIEWER_PK_1 : REVIEWER_PK_2,
                account: ACCOUNT,
                hash: MESSAGE_HASH,
                policyId: DEFAULT_POLICY_ID,
                expirationTimestamp: expiration,
                initiatorSignature: initiatorSignature
            });
        }

        policy.config.approval.approverMember = reviewerAuthorized ? reviewerSigner : reviewer1;

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

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

        // Call: execute `validatePolicyBasedSignatureViaLibrary` for fuzzed signer encoding mix.
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signatureData);

        // Verify: authorization outcome should follow policy authorization, not signature encoding mode.
        bytes4 expected = reviewerAuthorized ? SignatureUtils.ERC1271_MAGIC_VALUE : SignatureUtils.ERC1271_INVALID_VALUE;
        assertEq(actual, expected, "authorization outcome should depend on policy authorization");
    }

    /// @dev Verifies module-signature acceptance always follows the guardian Safe's current enabled state.
    /// @param enabledMask Bitmask whose low bits drive the enabled/disabled state applied at each step.
    /// @param stepCountRaw Fuzzed number of enablement transitions to evaluate.
    function testFuzz_SMI_FUZ_7_isValidGuardianSignature_moduleAcceptanceMatchesEnabledState(
        uint256 enabledMask,
        uint8 stepCountRaw
    ) public {
        // Setup: deploy a guardian Safe with one executor module and prepare a valid module-backed signature.
        MockGuardianSafe guardianSafe = new MockGuardianSafe();
        SafeExecutorModule module = _deployGuardianModule(address(guardianSafe), AUTHORIZED_EXECUTOR_PK);
        bytes memory guardianSignature = _buildModuleGuardianSignature(module, AUTHORIZED_EXECUTOR_PK, MESSAGE_HASH);
        uint256 stepCount = bound(stepCountRaw, 1, 16);
        policyStateHarness.setGuardian(address(guardianSafe));

        // Call: replay the fuzzed enable/disable sequence and validate after each transition.
        for (uint256 i = 0; i < stepCount; i++) {
            bool enabled = ((enabledMask >> i) & 1) == 1;
            guardianSafe.setModuleEnabled(address(module), enabled);

            bool actual = harness.isValidGuardianSignatureViaLibrary(guardianSignature, MESSAGE_HASH);

            // Verify: acceptance matches the guardian Safe's current enabled set exactly.
            assertEq(actual, enabled, "module-signature acceptance should track current enablement");
        }
    }

    /// @dev Verifies only correctly signed authorized-executor module payloads validate through the guardian path.
    /// @param caseSelector Fuzzed selector for valid, wrong-signer, wrong-hash, or malformed-inner-signature cases.
    /// @param alternateSignerPkRaw Fuzzed seed for a non-authorized signer key.
    /// @param wrongHash Fuzzed alternate hash for wrong-hash module signatures.
    /// @param malformedInnerSignature Arbitrary malformed inner-signature bytes.
    function testFuzz_SMI_FUZ_8_isValidGuardianSignature_onlyAuthorizedExecutorInnerSignatureValid(
        uint8 caseSelector,
        uint256 alternateSignerPkRaw,
        bytes32 wrongHash,
        bytes calldata malformedInnerSignature
    ) public {
        // Setup: deploy an enabled guardian module and pick one fuzzed inner-signature scenario.
        MockGuardianSafe guardianSafe = new MockGuardianSafe();
        SafeExecutorModule module = _deployGuardianModule(address(guardianSafe), AUTHORIZED_EXECUTOR_PK);
        guardianSafe.setModuleEnabled(address(module), true);
        policyStateHarness.setGuardian(address(guardianSafe));

        caseSelector = uint8(bound(caseSelector, 0, 3));
        bytes memory innerSignature;
        bool expected;

        if (caseSelector == 0) {
            innerSignature = _signHash(AUTHORIZED_EXECUTOR_PK, MESSAGE_HASH);
            expected = true;
        } else if (caseSelector == 1) {
            uint256 alternateSignerPk = bound(alternateSignerPkRaw, 1, SECP256K1_CURVE_ORDER - 1);
            vm.assume(alternateSignerPk != AUTHORIZED_EXECUTOR_PK);
            innerSignature = _signHash(alternateSignerPk, MESSAGE_HASH);
            expected = false;
        } else if (caseSelector == 2) {
            vm.assume(wrongHash != MESSAGE_HASH);
            innerSignature = _signHash(AUTHORIZED_EXECUTOR_PK, wrongHash);
            expected = false;
        } else {
            vm.assume(malformedInnerSignature.length != 65);
            innerSignature = malformedInnerSignature;
            expected = false;
        }

        bytes memory guardianSignature = _buildContractSignature(address(module), innerSignature);

        // Call: validate the fuzzed module inner-signature variant.
        bool actual = harness.isValidGuardianSignatureViaLibrary(guardianSignature, MESSAGE_HASH);

        // Verify: only exact authorized-executor signatures over the validated hash are accepted.
        assertEq(actual, expected, "guardian module validation should accept only authorized exact-hash signatures");
    }

    /**
     * @dev Computes Merkle leaf for an address using policy tree address-leaf rules.
     */
    function _computeAddressLeaf(address account) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(account))));
    }

    /**
     * @dev Deploys a Safe executor module for guardian-signature fuzz tests.
     * @param safe Safe-compatible guardian address that owns module enablement.
     * @param executorPk Private key whose address becomes the module's authorized executor.
     * @return module Newly deployed `SafeExecutorModule`.
     */
    function _deployGuardianModule(address safe, uint256 executorPk) internal returns (SafeExecutorModule module) {
        BatchedTransaction batchedTransaction = new BatchedTransaction();
        module = new SafeExecutorModule(safe, vm.addr(executorPk), address(batchedTransaction));
    }

    /**
     * @dev Builds a module-backed guardian signature for fuzz tests.
     * @param module Safe executor module that validates the inner signature.
     * @param executorPk Private key used to sign the module's inner payload.
     * @param messageHash Review hash being signed by the executor.
     * @return guardianSignature Nested ERC-1271 contract signature for guardian validation.
     */
    function _buildModuleGuardianSignature(SafeExecutorModule module, uint256 executorPk, bytes32 messageHash)
        internal
        view
        returns (bytes memory guardianSignature)
    {
        guardianSignature = _buildContractSignature(address(module), _signHash(executorPk, messageHash));
    }
}
