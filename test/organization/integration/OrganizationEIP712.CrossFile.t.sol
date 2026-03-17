// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAccountTransaction} from "interfaces/organization/IOrganizationAccountTransaction.sol";
import {SignatureUtils} from "libraries/SignatureUtils.sol";
import {
    LibOrganizationAccountSignatureTestBase
} from "test/organization/libraries/LibOrganizationAccountSignature/LibOrganizationAccountSignatureTestBase.sol";
import {
    LibOrganizationAccountTransactionHarness
} from "test/organization/libraries/LibOrganizationAccountTransaction/LibOrganizationAccountTransactionHarness.sol";
import {
    LibOrganizationAdminHarness
} from "test/organization/libraries/LibOrganizationAdmin/LibOrganizationAdminHarness.sol";
import {OrganizationPolicyStateHarness} from "test/organization/shared/OrganizationPolicyStateHarness.sol";
import {OperationType} from "types/CommonTypes.sol";
import {ApproverType, Policy, PolicyType, TransactionType, ValidationProofs} from "types/PolicyTypes.sol";

/**
 * @dev Cross-file integration tests for EIP-712 message-type isolation across admin, transaction, and ERC-1271
 *      authorization flows.
 */
contract OrganizationEIP712CrossFileTest is LibOrganizationAccountSignatureTestBase {
    uint256 internal constant TX_POLICY_ID = 771;
    uint256 internal constant SIG_POLICY_ID = 881;

    address internal constant TX_ACCOUNT = address(0xA1101);
    address internal constant TX_DESTINATION = address(0xB2202);

    LibOrganizationAdminHarness internal adminHarness;
    LibOrganizationAccountTransactionHarness internal txHarness;

    /**
     * @dev Deploys the extra admin and account-transaction harnesses used by cross-file isolation tests.
     */
    function setUp() public override {
        super.setUp();

        adminHarness = new LibOrganizationAdminHarness();
        txHarness = new LibOrganizationAccountTransactionHarness();

        _seedPolicyMembers(address(txHarness));
    }

    /// @dev Verifies `AdminOperation` signatures cannot authorize the `InitiateAccountTransaction` approval flow.
    function test_E712_MTI_1_validateTransactionApproval_rejectsAdminOperationSignatureReplay() public {
        // Setup: configure a valid admin signer on the admin harness and a transaction policy that authorizes only the
        // transaction initiator fixture.
        _configureAdminHarness(admin1);

        Policy memory txPolicy = _buildTxPolicy(PolicyType.AutoApprove, initiator1, reviewer1);
        ValidationProofs memory txProofs =
            _setSinglePolicyRootAndBuildProofsForHarness(txHarness, TX_POLICY_ID, txPolicy);

        bytes memory txData = abi.encodeWithSelector(bytes4(0x11111111), uint256(1));
        // casting string literal to bytes32 is safe because "cross-file-admin-op" fits within 32 bytes
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory adminOperationData = abi.encode(bytes32("cross-file-admin-op"), uint256(7));
        uint256 expiration = block.timestamp + 1 days;
        bytes32 adminOperationHash = adminHarness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: adminOperationData,
            salt: 1,
            expirationTimestamp: expiration,
            isApproval: true
        });
        bytes memory adminSignature = _signHash(ADMIN_PK_1, adminOperationHash);

        // Verify: replaying the admin-domain signature through transaction approval fails policy authorization.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAccountTransaction.PolicyDoesNotApply.selector, TX_POLICY_ID)
        );
        // Call: validate the account-transaction approval flow with the wrong-domain signature bytes.
        txHarness.validateTransactionApprovalOrRevertViaLibrary(
            TX_ACCOUNT, TX_DESTINATION, 0, txData, 1, expiration, TX_POLICY_ID, adminSignature, bytes(""), txProofs
        );
    }

    /// @dev Verifies `InitiateAccountTransaction` signatures cannot authorize the `ReviewAccountTransaction` flow.
    function test_E712_MTI_2_validateTransactionApproval_rejectsInitiatorSignatureReplayAsReviewSignature() public {
        // Setup: configure a manual-approval transaction policy with one authorized reviewer.
        Policy memory txPolicy = _buildTxPolicy(PolicyType.RequireManualApproval, initiator1, reviewer1);
        ValidationProofs memory txProofs =
            _setSinglePolicyRootAndBuildProofsForHarness(txHarness, TX_POLICY_ID, txPolicy);

        bytes memory txData = abi.encodeWithSelector(bytes4(0x22222222), uint256(2));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature =
            _signTxInitiator(TX_ACCOUNT, TX_DESTINATION, 0, txData, 2, expiration, TX_POLICY_ID, true);

        // Verify: replaying the initiator signature as a reviewer approval fails the review-hash threshold check.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.InsufficientApprovals.selector, 1, 0));
        // Call: validate the manual approval flow while reusing the initiator signature as the review signature.
        txHarness.validateTransactionApprovalOrRevertViaLibrary(
            TX_ACCOUNT,
            TX_DESTINATION,
            0,
            txData,
            2,
            expiration,
            TX_POLICY_ID,
            initiatorSignature,
            initiatorSignature,
            txProofs
        );
    }

    /// @dev Verifies `InitiateSignatureValidation` signatures cannot authorize the `ReviewSignatureValidation` flow.
    function test_E712_MTI_3_validatePolicyBasedSignature_rejectsInitiatorSignatureReplayAsReviewSignature() public {
        // Setup: configure a manual-approval signature policy with a valid guardian signature over the review hash.
        policyStateHarness.setGuardian(guardianSigner);
        bytes4 actual;
        {
            Policy memory sigPolicy = _buildSignaturePolicy(PolicyType.RequireManualApproval);
            ValidationProofs memory sigProofs = _setSinglePolicyRootAndBuildProofs(SIG_POLICY_ID, sigPolicy);

            uint256 expiration = block.timestamp + 1 days;
            bytes memory initiatorSignature = _signInitiatorSignature({
                sigHarness: harness,
                privateKey: INITIATOR_PK_1,
                account: ACCOUNT,
                hash: MESSAGE_HASH,
                policyId: SIG_POLICY_ID,
                expirationTimestamp: expiration
            });
            bytes memory guardianSignature = _signGuardianReviewHash({
                sigHarness: harness,
                privateKey: GUARDIAN_PK,
                account: ACCOUNT,
                hash: MESSAGE_HASH,
                policyId: SIG_POLICY_ID,
                expirationTimestamp: expiration,
                initiatorSignature: initiatorSignature
            });
            bytes memory signatureData = _buildPolicySignatureData({
                policyId: SIG_POLICY_ID,
                expirationTimestamp: expiration,
                initiatorSignature: initiatorSignature,
                reviewSignatures: initiatorSignature,
                guardianSignature: guardianSignature,
                proofs: sigProofs
            });

            // Call: validate the ERC-1271 policy payload while replaying the initiator signature in the review slot.
            actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signatureData);
        }

        // Verify: the wrong-domain review signature fails closed with ERC-1271 invalid value.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "initiator signature should not authorize review flow");
    }

    /// @dev Verifies account-transaction and ERC-1271 signatures cannot be replayed across each other's flows.
    function test_E712_MTI_4_crossFlowReplay_rejectsTransactionAndPolicySignaturesAcrossFlows() public {
        // Setup: configure valid transaction and signature policies on their respective harnesses.
        ValidationProofs memory txProofs;
        policyStateHarness.setGuardian(guardianSigner);
        bytes memory txData = abi.encodeWithSelector(bytes4(0x33333333), uint256(3));
        uint256 txExpiration = block.timestamp + 1 days;
        bytes memory policyInitiatorSignature;
        bytes4 policyReplayResult;

        {
            Policy memory txPolicy = _buildTxPolicy(PolicyType.AutoApprove, initiator1, reviewer1);
            txProofs = _setSinglePolicyRootAndBuildProofsForHarness(txHarness, TX_POLICY_ID, txPolicy);
        }

        {
            Policy memory sigPolicy = _buildSignaturePolicy(PolicyType.AutoApprove);
            ValidationProofs memory sigProofs = _setSinglePolicyRootAndBuildProofs(SIG_POLICY_ID, sigPolicy);

            bytes memory transactionSignature =
                _signTxInitiator(TX_ACCOUNT, TX_DESTINATION, 0, txData, 3, txExpiration, TX_POLICY_ID, true);

            uint256 sigExpiration = block.timestamp + 2 days;
            policyInitiatorSignature = _signInitiatorSignature({
                sigHarness: harness,
                privateKey: INITIATOR_PK_1,
                account: ACCOUNT,
                hash: MESSAGE_HASH,
                policyId: SIG_POLICY_ID,
                expirationTimestamp: sigExpiration
            });
            bytes memory guardianSignature = _signGuardianReviewHash({
                sigHarness: harness,
                privateKey: GUARDIAN_PK,
                account: ACCOUNT,
                hash: MESSAGE_HASH,
                policyId: SIG_POLICY_ID,
                expirationTimestamp: sigExpiration,
                initiatorSignature: transactionSignature
            });
            bytes memory policySignatureData = _buildPolicySignatureData({
                policyId: SIG_POLICY_ID,
                expirationTimestamp: sigExpiration,
                initiatorSignature: transactionSignature,
                reviewSignatures: bytes(""),
                guardianSignature: guardianSignature,
                proofs: sigProofs
            });

            // Call: replay the transaction signature through the ERC-1271 policy flow.
            policyReplayResult =
                harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, policySignatureData);
        }

        // Verify: the transaction-domain signature is rejected by the ERC-1271 policy flow.
        assertEq(
            policyReplayResult,
            SignatureUtils.ERC1271_INVALID_VALUE,
            "transaction signature should not authorize ERC-1271 policy flow"
        );

        // Verify: replaying the signature-validation initiator signature through transaction approval fails policy
        // authorization.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAccountTransaction.PolicyDoesNotApply.selector, TX_POLICY_ID)
        );
        // Call: validate the account-transaction approval flow with an ERC-1271 initiator signature.
        txHarness.validateTransactionApprovalOrRevertViaLibrary(
            TX_ACCOUNT,
            TX_DESTINATION,
            0,
            txData,
            4,
            txExpiration,
            TX_POLICY_ID,
            policyInitiatorSignature,
            bytes(""),
            txProofs
        );
    }

    /// @dev Verifies the system-defined message-type hashes remain distinct for the same seeded inputs.
    function test_E712_MTI_5_messageTypeHashesRemainDistinctForSameSeededInputs() public {
        // Setup: derive one deterministic admin hash, transaction initiator/review hash pair, and signature
        // initiator/review hash pair over aligned seeded inputs.
        _configureAdminHarness(admin1);
        bytes32[] memory hashes = new bytes32[](5);
        {
            // casting string literal to bytes32 is safe because "cross-file-admin-seed" fits within 32 bytes
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes memory adminOperationData = abi.encode(bytes32("cross-file-admin-seed"), uint256(4));
            uint256 expiration = block.timestamp + 1 days;
            hashes[0] = adminHarness.getAdminOperationHash({
                operationType: OperationType.ModifyPolicies,
                operationData: adminOperationData,
                salt: 5,
                expirationTimestamp: expiration,
                isApproval: true
            });
        }
        {
            bytes memory txData = abi.encodeWithSelector(bytes4(0x44444444), uint256(4));
            uint256 expiration = block.timestamp + 1 days;
            bytes memory txInitiatorSignature =
                _signTxInitiator(TX_ACCOUNT, TX_DESTINATION, 0, txData, 5, expiration, TX_POLICY_ID, true);
            hashes[1] = txHarness.computeInitiatorHashFromParamsViaLibrary(
                TX_ACCOUNT, TX_DESTINATION, 0, 5, expiration, TX_POLICY_ID, txData, true
            );
            hashes[2] = txHarness.computeReviewHashFromParamsViaLibrary(
                TX_ACCOUNT, TX_DESTINATION, 0, 5, expiration, TX_POLICY_ID, txData, true, txInitiatorSignature
            );
        }
        {
            uint256 expiration = block.timestamp + 1 days;
            bytes memory sigInitiatorSignature = _signInitiatorSignature({
                sigHarness: harness,
                privateKey: INITIATOR_PK_1,
                account: ACCOUNT,
                hash: MESSAGE_HASH,
                policyId: SIG_POLICY_ID,
                expirationTimestamp: expiration
            });
            hashes[3] = harness.getInitiatorSignatureHashViaLibrary(ACCOUNT, MESSAGE_HASH, SIG_POLICY_ID, expiration);
            hashes[4] = harness.getReviewSignatureHashViaLibrary({
                account: ACCOUNT,
                hash: MESSAGE_HASH,
                policyId: SIG_POLICY_ID,
                expirationTimestamp: expiration,
                initiatorSignature: sigInitiatorSignature
            });
        }

        // Verify: all system-defined message hashes remain distinct because each typehash and field layout is unique.
        _assertDistinctHashes(hashes);
    }

    /// @dev Verifies recovery and policy type-prefixed signatures cannot authorize each other's validation routes.
    function test_E712_MTI_6__LOAS_AISO_1__LOAS_AISO_2_isValidSignature_rejectsRecoveryAndPolicyFlowPrefixReplay()
        public
    {
        // Setup: configure valid recovery and valid policy-signature fixtures.
        _setTxRecoveryState(guardianSigner, true);
        bytes memory recoverySignature = _buildRecoverySignature(_signHash(GUARDIAN_PK, MESSAGE_HASH));

        policyStateHarness.setGuardian(guardianSigner);
        (bytes memory policySignature,,,,,) =
            _buildValidPolicySignature(PolicyType.AutoApprove, SIG_POLICY_ID, block.timestamp + 1 days);

        bytes memory forcedRecoverySignature = bytes.concat(policySignature);
        forcedRecoverySignature[0] = bytes1(uint8(0x00));

        bytes memory forcedPolicySignature = bytes.concat(recoverySignature);
        forcedPolicySignature[0] = bytes1(uint8(0x01));

        // Call: execute the valid recovery path, the valid policy path, and both cross-prefix replay attempts.
        bytes4 validRecoveryResult = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, recoverySignature);
        bytes4 validPolicyResult = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, policySignature);
        bytes4 policyAsRecoveryResult =
            harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, forcedRecoverySignature);

        // Verify: only the correctly prefixed payloads authorize their intended validation route.
        assertEq(validRecoveryResult, SignatureUtils.ERC1271_MAGIC_VALUE, "recovery payload should validate");
        assertEq(validPolicyResult, SignatureUtils.ERC1271_MAGIC_VALUE, "policy payload should validate");
        assertEq(
            policyAsRecoveryResult,
            SignatureUtils.ERC1271_INVALID_VALUE,
            "policy payload should not authorize recovery flow"
        );

        // Verify: recovery data forced through the policy path reverts with empty data because the payload is too
        // short for the policy `abi.decode` shape.
        vm.expectRevert(bytes(""));
        harness.isValidSignatureUnsafe(ACCOUNT, MESSAGE_HASH, forcedPolicySignature);
    }

    /// @dev Verifies fuzzed initiator-signature byte mutations always alter both transaction and ERC-1271 review
    /// hashes.
    function testFuzz_E712_FUZ_4_reviewHashes_randomInitiatorSignatureBytesAlwaysChangeHashes(
        bytes calldata initiatorSignatureA,
        bytes calldata initiatorSignatureB
    ) public view {
        // Setup: constrain the fuzzed initiator-signature payloads to distinct byte hashes over one shared seed.
        vm.assume(keccak256(initiatorSignatureA) != keccak256(initiatorSignatureB));
        bytes memory txData = abi.encodeWithSelector(bytes4(0x55555555), uint256(55));
        uint256 expiration = block.timestamp + 1 days;

        // Call: derive both transaction and ERC-1271 review hashes for the two initiator-signature variants.
        bytes32 txReviewHashA = txHarness.computeReviewHashFromParamsViaLibrary(
            TX_ACCOUNT, TX_DESTINATION, 0, 55, expiration, TX_POLICY_ID, txData, true, initiatorSignatureA
        );
        bytes32 txReviewHashB = txHarness.computeReviewHashFromParamsViaLibrary(
            TX_ACCOUNT, TX_DESTINATION, 0, 55, expiration, TX_POLICY_ID, txData, true, initiatorSignatureB
        );
        bytes32 sigReviewHashA = harness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: SIG_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignatureA
        });
        bytes32 sigReviewHashB = harness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: SIG_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignatureB
        });

        // Verify: both helpers bind `keccak256(initiatorSignature)`, so changing the bytes must change the review hash.
        assertTrue(txReviewHashA != txReviewHashB, "transaction review hash should change with initiator signature");
        assertTrue(sigReviewHashA != sigReviewHashB, "signature review hash should change with initiator signature");
    }

    /// @dev Verifies fuzzed cross-flow replay attempts over wrong message-type hashes are always rejected.
    function testFuzz_E712_FUZ_5_crossFlowReplayAttempts_wrongMessageTypeHashesAreAlwaysRejected(
        uint8 caseSelectorRaw,
        uint256 saltRaw,
        bytes32 seedHash
    ) public {
        // Setup: pick one replay scenario and derive one shared fuzzed salt / payload seed.
        uint8 caseSelector = uint8(bound(caseSelectorRaw, 0, 3));
        uint256 salt = bound(saltRaw, 1, type(uint96).max);
        uint256 expiration = block.timestamp + 1 days;
        bytes memory txData = abi.encode(seedHash, salt);

        if (caseSelector == 0) {
            _configureAdminHarness(admin1);

            Policy memory txPolicy = _buildTxPolicy(PolicyType.AutoApprove, initiator1, reviewer1);
            ValidationProofs memory txProofs =
                _setSinglePolicyRootAndBuildProofsForHarness(txHarness, TX_POLICY_ID, txPolicy);

            bytes32 adminOperationHash = adminHarness.getAdminOperationHash({
                operationType: OperationType.ModifyAdmins,
                // forge-lint: disable-next-line(unsafe-typecast)
                operationData: abi.encode(seedHash, salt, bytes32("admin")),
                salt: salt,
                expirationTimestamp: expiration,
                isApproval: true
            });
            bytes memory adminSignature = _signHash(ADMIN_PK_1, adminOperationHash);

            // Verify: an admin-operation signature must never authorize transaction initiation.
            vm.expectRevert(
                abi.encodeWithSelector(IOrganizationAccountTransaction.PolicyDoesNotApply.selector, TX_POLICY_ID)
            );
            // Call: replay the wrong-domain admin signature through transaction approval.
            txHarness.validateTransactionApprovalOrRevertViaLibrary(
                TX_ACCOUNT,
                TX_DESTINATION,
                0,
                txData,
                salt,
                expiration,
                TX_POLICY_ID,
                adminSignature,
                bytes(""),
                txProofs
            );
            return;
        }

        if (caseSelector == 1) {
            Policy memory txPolicy = _buildTxPolicy(PolicyType.RequireManualApproval, initiator1, reviewer1);
            ValidationProofs memory txProofs =
                _setSinglePolicyRootAndBuildProofsForHarness(txHarness, TX_POLICY_ID, txPolicy);
            bytes memory initiatorSignature =
                _signTxInitiator(TX_ACCOUNT, TX_DESTINATION, 0, txData, salt, expiration, TX_POLICY_ID, true);

            // Verify: an initiator-hash signature must never satisfy the review-hash approval path.
            vm.expectRevert(
                abi.encodeWithSelector(IOrganizationAccountTransaction.InsufficientApprovals.selector, 1, 0)
            );
            // Call: replay the initiator signature in the review-signatures slot.
            txHarness.validateTransactionApprovalOrRevertViaLibrary(
                TX_ACCOUNT,
                TX_DESTINATION,
                0,
                txData,
                salt,
                expiration,
                TX_POLICY_ID,
                initiatorSignature,
                initiatorSignature,
                txProofs
            );
            return;
        }

        policyStateHarness.setGuardian(guardianSigner);

        if (caseSelector == 2) {
            Policy memory manualSigPolicy = _buildSignaturePolicy(PolicyType.RequireManualApproval);
            ValidationProofs memory manualSigProofs = _setSinglePolicyRootAndBuildProofs(SIG_POLICY_ID, manualSigPolicy);
            bytes memory initiatorSignature = _signInitiatorSignature({
                sigHarness: harness,
                privateKey: INITIATOR_PK_1,
                account: ACCOUNT,
                hash: seedHash,
                policyId: SIG_POLICY_ID,
                expirationTimestamp: expiration
            });
            bytes memory manualGuardianSignature = _signGuardianReviewHash({
                sigHarness: harness,
                privateKey: GUARDIAN_PK,
                account: ACCOUNT,
                hash: seedHash,
                policyId: SIG_POLICY_ID,
                expirationTimestamp: expiration,
                initiatorSignature: initiatorSignature
            });
            bytes memory manualSignatureData = _buildPolicySignatureData({
                policyId: SIG_POLICY_ID,
                expirationTimestamp: expiration,
                initiatorSignature: initiatorSignature,
                reviewSignatures: initiatorSignature,
                guardianSignature: manualGuardianSignature,
                proofs: manualSigProofs
            });

            // Call: replay the signature initiator payload through the manual-review slot.
            bytes4 manualResult = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, seedHash, manualSignatureData);

            // Verify: a signature-validation initiator signature must not authorize the review hash path.
            assertEq(
                manualResult,
                SignatureUtils.ERC1271_INVALID_VALUE,
                "initiator signature should not authorize review flow"
            );
            return;
        }

        Policy memory sigPolicy = _buildSignaturePolicy(PolicyType.AutoApprove);
        ValidationProofs memory sigProofs = _setSinglePolicyRootAndBuildProofs(SIG_POLICY_ID, sigPolicy);
        bytes memory txInitiatorSignature =
            _signTxInitiator(TX_ACCOUNT, TX_DESTINATION, 0, txData, salt, expiration, TX_POLICY_ID, true);
        bytes memory guardianSignature = _signGuardianReviewHash({
            sigHarness: harness,
            privateKey: GUARDIAN_PK,
            account: ACCOUNT,
            hash: seedHash,
            policyId: SIG_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: txInitiatorSignature
        });
        bytes memory signatureData = _buildPolicySignatureData({
            policyId: SIG_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: txInitiatorSignature,
            reviewSignatures: bytes(""),
            guardianSignature: guardianSignature,
            proofs: sigProofs
        });

        // Call: replay the account-transaction initiator signature through ERC-1271 policy validation.
        bytes4 actual = harness.validatePolicyBasedSignatureViaLibrary(ACCOUNT, seedHash, signatureData);

        // Verify: a transaction-domain signature must not authorize the ERC-1271 policy flow.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "transaction signature should not authorize policy flow");
    }

    /**
     * @dev Builds a transaction policy for cross-file replay tests.
     * @param approvalType Approval mode required by the policy.
     * @param initiator Authorized initiator address.
     * @param approver Authorized reviewer address.
     * @return policy Transaction policy configured for the requested initiator/approver pair.
     */
    function _buildTxPolicy(PolicyType approvalType, address initiator, address approver)
        internal
        view
        returns (Policy memory policy)
    {
        policy = _buildBasePolicy();
        policy.config.transactionType = TransactionType.Any;
        policy.config.approval.policyType = approvalType;
        policy.config.initiator.anyInitiator = false;
        policy.config.initiator.initiatorType = ApproverType.Member;
        policy.config.initiator.initiatorMember = initiator;
        policy.config.approval.approverType = ApproverType.Member;
        policy.config.approval.approverMember = approver;
        policy.config.approval.approvalThreshold = 1;
    }

    /**
     * @dev Seeds deterministic member fixtures onto another policy-capable harness.
     * @param target Address of the harness that should mirror the shared member fixture.
     */
    function _seedPolicyMembers(address target) internal {
        // Mirror the initiator/reviewer fixture onto the cross-file transaction harness.
        OrganizationPolicyStateHarness targetHarness = OrganizationPolicyStateHarness(target);
        targetHarness.setMemberStatus(initiator1, true);
        targetHarness.setMemberStatus(initiator2, true);
        targetHarness.setMemberStatus(reviewer1, true);
        targetHarness.setMemberStatus(reviewer2, true);
        targetHarness.setMemberStatus(reviewer3, true);
    }

    /**
     * @dev Configures a one-admin authorization fixture on the dedicated admin harness.
     * @param admin Authorized admin signer.
     */
    function _configureAdminHarness(address admin) internal {
        adminHarness.setMemberStatus(admin, true);
        adminHarness.setAdminStatus(admin, true);
        adminHarness.setAdminCount(1);
        adminHarness.setVotingThreshold(1);
    }

    /**
     * @dev Installs a single-policy root on a specific harness and returns the matching empty-proof payload.
     * @param target Harness whose policy root should be updated.
     * @param policyId Policy identifier used to derive the Merkle leaf.
     * @param policy Policy payload stored at the derived root.
     * @return proofs Empty-proof validation payload for the installed single-policy root.
     */
    function _setSinglePolicyRootAndBuildProofsForHarness(
        OrganizationPolicyStateHarness target,
        uint256 policyId,
        Policy memory policy
    ) internal returns (ValidationProofs memory proofs) {
        bytes32[] memory empty = new bytes32[](0);

        // A single-leaf policy tree uses the policy leaf directly as the root.
        target.setPoliciesRoot(_computePolicyLeaf(policyId, policy));
        proofs = ValidationProofs({
            policy: policy,
            policyProof: empty,
            sourceAccountProof: empty,
            destinationProof: empty,
            functionProof: empty,
            constraints: bytes("")
        });
    }

    /**
     * @dev Signs a transaction-approval or rejection initiator hash on the dedicated transaction harness.
     * @param account Source account bound into the transaction hash.
     * @param to Destination bound into the transaction hash.
     * @param value ETH value bound into the transaction hash.
     * @param data Calldata bound into the transaction hash.
     * @param salt Salt bound into the transaction hash.
     * @param expirationTimestamp Expiration bound into the transaction hash.
     * @param policyId Policy identifier bound into the transaction hash.
     * @param isApproval Whether to derive the approval or rejection initiator hash.
     * @return signature ECDSA signature over the derived transaction initiator hash.
     */
    function _signTxInitiator(
        address account,
        address to,
        uint256 value,
        bytes memory data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bool isApproval
    ) internal view returns (bytes memory signature) {
        bytes32 txHash = txHarness.computeInitiatorHashFromParamsViaLibrary(
            account, to, value, salt, expirationTimestamp, policyId, data, isApproval
        );

        signature = _signHash(INITIATOR_PK_1, txHash);
    }

    /**
     * @dev Asserts that every hash in a set differs from every other hash in the set.
     * @param hashes Array of hashes expected to be pairwise distinct.
     */
    function _assertDistinctHashes(bytes32[] memory hashes) internal pure {
        // Compare each hash against every later hash to prove pairwise uniqueness.
        for (uint256 i = 0; i < hashes.length; ++i) {
            for (uint256 j = i + 1; j < hashes.length; ++j) {
                assertTrue(hashes[i] != hashes[j], "message-type hashes should remain pairwise distinct");
            }
        }
    }
}
