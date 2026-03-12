// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAccountTransaction} from "interfaces/organization/IOrganizationAccountTransaction.sol";
import {SignatureUtils} from "libraries/SignatureUtils.sol";
import {
    LibOrganizationAccountTransactionHarness
} from "test/organization/libraries/LibOrganizationAccountTransaction/LibOrganizationAccountTransactionHarness.sol";
import {
    LibOrganizationAccountTransactionTestBase
} from "test/organization/libraries/LibOrganizationAccountTransaction/LibOrganizationAccountTransactionTestBase.sol";
import {Policy, PolicyType, RateLimitType, TransactionType, ValidationProofs} from "types/PolicyTypes.sol";

/**
 * @dev Validation-path unit tests for approval/rejection entry points in `LibOrganizationAccountTransaction`.
 */
contract LibOrganizationAccountTransactionValidationTest is LibOrganizationAccountTransactionTestBase {
    /**
     * @dev Deploys additional ERC-1271 signer fixture.
     */
    function setUp() public override {
        super.setUp();
        policyStateHarness.setMemberStatus(address(validSigner1271), true);
    }

    /// @dev Verifies expired approval transactions revert `TransactionExpired`.
    function test_LOAT_VTAOR_1__LOAT_VTAOR_3__LOAT_AVTAOR_1_validateApproval_expired_revertsTransactionExpired()
        public
    {
        // Setup: build approval payload with expiration in the past.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        bytes memory data = abi.encodeWithSelector(bytes4(0x11111111), uint256(1));
        uint256 expiration = block.timestamp - 1;
        bytes memory initiatorSignature = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 1, expiration, DEFAULT_POLICY_ID, true
        );

        // Verify: approval path rejects expired transaction.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAccountTransaction.TransactionExpired.selector, expiration, block.timestamp
            )
        );
        // Call: validate approval.
        harness.validateTransactionApprovalOrRevertViaLibrary(
            ACCOUNT, DESTINATION, 0, data, 1, expiration, DEFAULT_POLICY_ID, initiatorSignature, bytes(""), proofs
        );
    }

    /// @dev Verifies approval expiration equal to block timestamp succeeds (strict `>` check).
    function test_LOACT_VTAORVTROR_9__LOAT_VTAOR_2__LOAT_AVTAOR_2_validateApproval_expirationEqualsTimestamp_succeeds()
        public
    {
        // Setup: build approval payload with expiration equal to current block timestamp.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        bytes memory data = abi.encodeWithSelector(bytes4(0x12121212), uint256(2));
        uint256 expiration = block.timestamp;
        bytes memory initiatorSignature = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 2, expiration, DEFAULT_POLICY_ID, true
        );

        // Call: validate approval at boundary timestamp.
        harness.validateTransactionApprovalOrRevertViaLibrary(
            ACCOUNT, DESTINATION, 0, data, 2, expiration, DEFAULT_POLICY_ID, initiatorSignature, bytes(""), proofs
        );
    }

    /// @dev Verifies empty initiator signature reverts `InsufficientSignaturesLength`.
    function test_LOAT_VTAOR_4__LOAT_AVTAOR_3_validateApproval_emptyInitiatorSignature_revertsInsufficientSignaturesLength()
        public
    {
        // Setup: valid proof payload with empty initiator signature.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        // Verify: empty initiator signature is rejected.
        vm.expectRevert(IOrganizationAccountTransaction.InsufficientSignaturesLength.selector);
        // Call: validate approval.
        harness.validateTransactionApprovalOrRevertViaLibrary(
            ACCOUNT,
            DESTINATION,
            0,
            bytes(""),
            3,
            block.timestamp + 1 days,
            DEFAULT_POLICY_ID,
            bytes(""),
            bytes(""),
            proofs
        );
    }

    /// @dev Verifies approval path uses `isApproval=true` for initiator hash binding.
    function test_LOACT_VTAORVTROR_2__LOAT_VTAOR_5_validateApproval_usesInitiatorHashWithApprovalFlagTrue() public {
        // Setup: sign with rejection hash (isApproval=false) then call approval flow.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        bytes memory data = abi.encodeWithSelector(bytes4(0x13131313), uint256(3));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory wrongSignature = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 4, expiration, DEFAULT_POLICY_ID, false
        );

        // Verify: wrong approval flag in signed hash causes validation failure.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAccountTransaction.PolicyDoesNotApply.selector, DEFAULT_POLICY_ID)
        );
        // Call: validate approval with mismatch signature.
        harness.validateTransactionApprovalOrRevertViaLibrary(
            ACCOUNT, DESTINATION, 0, data, 4, expiration, DEFAULT_POLICY_ID, wrongSignature, bytes(""), proofs
        );
    }

    /// @dev Verifies EOA initiator signature is recovered and accepted in approval flow.
    function test_LOACT_VTAORVTROR_1__LOAT_VTAOR_6__LOAT_VTAOR_10__LOAT_AVTAOR_8_validateApproval_eoaInitiatorSignature_succeeds()
        public
    {
        // Setup: valid auto-approve policy and EOA initiator signature.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        bytes memory data = abi.encodeWithSelector(bytes4(0x14141414), uint256(4));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 5, expiration, DEFAULT_POLICY_ID, true
        );

        // Call: validate approval with EOA signature.
        harness.validateTransactionApprovalOrRevertViaLibrary(
            ACCOUNT, DESTINATION, 0, data, 5, expiration, DEFAULT_POLICY_ID, initiatorSignature, bytes(""), proofs
        );
    }

    /// @dev Verifies ERC-1271 initiator signature is recovered and accepted in approval flow.
    function test_LOAT_VTAOR_7_validateApproval_erc1271InitiatorSignature_succeeds() public {
        // Setup: configure initiator policy to authorize ERC-1271 signer contract.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        policy.config.initiator.initiatorMember = address(validSigner1271);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        bytes memory data = abi.encodeWithSelector(bytes4(0x15151515), uint256(5));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory contractSignature = _buildContractSignature(address(validSigner1271), hex"CAFE");

        // Call: validate approval using ERC-1271 signature payload.
        harness.validateTransactionApprovalOrRevertViaLibrary(
            ACCOUNT, DESTINATION, 0, data, 6, expiration, DEFAULT_POLICY_ID, contractSignature, bytes(""), proofs
        );
    }

    /// @dev Verifies approval signatures valid on one organization fail on another organization.
    function test_LOACT_VTAORVTROR_7_validateApproval_crossOrganizationReplay_revertsPolicyDoesNotApply() public {
        // Setup: mirror the same policy root and member state on a second organization harness.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        LibOrganizationAccountTransactionHarness otherHarness = new LibOrganizationAccountTransactionHarness();
        otherHarness.setMemberStatus(initiator1, true);
        otherHarness.setMemberStatus(initiator2, true);
        otherHarness.setMemberStatus(reviewer1, true);
        otherHarness.setMemberStatus(reviewer2, true);
        otherHarness.setMemberStatus(reviewer3, true);
        otherHarness.setPoliciesRoot(_computePolicyLeaf(DEFAULT_POLICY_ID, policy));

        bytes memory data = abi.encodeWithSelector(bytes4(0x15151616), uint256(51));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 51, expiration, DEFAULT_POLICY_ID, true
        );

        // Verify: changing the organization address changes the EIP-712 domain and invalidates the replay.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAccountTransaction.PolicyDoesNotApply.selector, DEFAULT_POLICY_ID)
        );
        // Call: replay the approval signature bundle through the second organization harness.
        otherHarness.validateTransactionApprovalOrRevertViaLibrary(
            ACCOUNT, DESTINATION, 0, data, 51, expiration, DEFAULT_POLICY_ID, initiatorSignature, bytes(""), proofs
        );
    }

    /// @dev Verifies approval signatures valid on one chain fail after the chain id changes.
    function test_LOACT_VTAORVTROR_8_validateApproval_crossChainReplay_revertsPolicyDoesNotApply() public {
        // Setup: sign a valid auto-approve transaction on the current chain.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        bytes memory data = abi.encodeWithSelector(bytes4(0x15151717), uint256(52));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 52, expiration, DEFAULT_POLICY_ID, true
        );
        uint256 originalChainId = block.chainid;

        // Verify: changing the chain id changes the EIP-712 domain and invalidates the replay.
        vm.chainId(originalChainId + 1);
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAccountTransaction.PolicyDoesNotApply.selector, DEFAULT_POLICY_ID)
        );
        // Call: validate the signed payload after mutating the chain id.
        harness.validateTransactionApprovalOrRevertViaLibrary(
            ACCOUNT, DESTINATION, 0, data, 52, expiration, DEFAULT_POLICY_ID, initiatorSignature, bytes(""), proofs
        );
        vm.chainId(originalChainId);
    }

    /// @dev Verifies approval signatures are bound to the transaction salt.
    function test_LOACT_VTAORVTROR_11_validateApproval_saltMutation_revertsPolicyDoesNotApply() public {
        // Setup: sign one approval tuple, then replay it with a different salt under the same remaining fields.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        bytes memory data = abi.encodeWithSelector(bytes4(0x15151818), uint256(53));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 53, expiration, DEFAULT_POLICY_ID, true
        );

        // Verify: replaying the signature bundle with a different salt changes the initiator hash and fails auth.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAccountTransaction.PolicyDoesNotApply.selector, DEFAULT_POLICY_ID)
        );
        // Call: validate the payload with a mutated salt.
        harness.validateTransactionApprovalOrRevertViaLibrary(
            ACCOUNT, DESTINATION, 0, data, 54, expiration, DEFAULT_POLICY_ID, initiatorSignature, bytes(""), proofs
        );
    }

    /// @dev Verifies manual-approval validation uses `isApproval=true` review hash.
    function test_LOACT_VTAORVTROR_5__LOAT_VTAOR_11__LOAT_VMCOR_3_validateApproval_manualReviewUsesApprovalFlagTrue()
        public
    {
        // Setup: manual policy and initiator signature for approval flow.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.RequireManualApproval);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        bytes memory data = abi.encodeWithSelector(bytes4(0x16161616), uint256(6));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 7, expiration, DEFAULT_POLICY_ID, true
        );
        bytes memory wrongReviewSignature = _signReviewTx(
            address(harness),
            REVIEWER_PK_1,
            ACCOUNT,
            DESTINATION,
            0,
            data,
            7,
            expiration,
            DEFAULT_POLICY_ID,
            false,
            initiatorSignature
        );

        // Verify: rejection-hash review signature cannot satisfy approval flow.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.InsufficientApprovals.selector, 1, 0));
        // Call: validate manual approval with wrong review hash flag.
        harness.validateTransactionApprovalOrRevertViaLibrary(
            ACCOUNT,
            DESTINATION,
            0,
            data,
            7,
            expiration,
            DEFAULT_POLICY_ID,
            initiatorSignature,
            wrongReviewSignature,
            proofs
        );
    }

    /// @dev Verifies auto-approve rejection validation rejects approval-domain signatures.
    function test_LOACT_VAAROR_2__NMATL_RHB_7_validateAutoApproveRejection_rejectsApprovalDomainSignatureReplay()
        public
    {
        // Setup: configure an auto-approve policy and sign the transaction with `isApproval=true`.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        bytes memory data = abi.encodeWithSelector(bytes4(0x16161717), uint256(61));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory approvalDomainSignature = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 61, expiration, DEFAULT_POLICY_ID, true
        );

        // Verify: replaying the approval signature through the rejection helper fails domain separation checks.
        vm.expectRevert(IOrganizationAccountTransaction.TransactionRejectionNotAllowed.selector);
        // Call: validate an auto-approve rejection using the wrong-domain signature.
        harness.validateAutoApproveRejectionOrRevertViaLibrary(
            ACCOUNT, DESTINATION, 0, 61, expiration, DEFAULT_POLICY_ID, data, approvalDomainSignature, proofs
        );
    }

    /// @dev Verifies manual confirmation binds reviewer signatures to the exact initiator signature bytes.
    function test_LOACT_VTAORVTROR_6__NMATL_RHB_8__LOAT_AVTAOR_6_validateManualConfirmation_reviewerSignaturesBindInitiatorSignature()
        public
    {
        // Setup: configure a manual-approval policy and build two distinct initiator signatures for one tuple.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.RequireManualApproval);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        bytes memory data = abi.encodeWithSelector(bytes4(0x16161818), uint256(62));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory signedInitiatorSignature = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 62, expiration, DEFAULT_POLICY_ID, true
        );
        bytes memory mutatedInitiatorSignature = _signInitiatorTx(
            address(harness), INITIATOR_PK_2, ACCOUNT, DESTINATION, 0, data, 62, expiration, DEFAULT_POLICY_ID, true
        );
        bytes memory reviewSignature = _signReviewTx(
            address(harness),
            REVIEWER_PK_1,
            ACCOUNT,
            DESTINATION,
            0,
            data,
            62,
            expiration,
            DEFAULT_POLICY_ID,
            true,
            signedInitiatorSignature
        );

        // Verify: reusing review signatures against different initiator-signature bytes fails.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.InsufficientApprovals.selector, 1, 0));
        // Call: validate manual confirmation with a mismatched initiator signature binding.
        harness.validateManualConfirmationOrRevertViaLibrary(
            ACCOUNT,
            DESTINATION,
            0,
            62,
            expiration,
            DEFAULT_POLICY_ID,
            data,
            reviewSignature,
            mutatedInitiatorSignature,
            proofs,
            true
        );
    }

    /// @dev Verifies successful manual/auto approval paths both update rate-limit usage.
    function test_LOAT_VTAOR_13__LOAT_AVTAOR_10_validateApproval_rateLimitUpdatesAcrossPolicyTypes() public {
        // Setup: configure auto + manual policies with enabled rate-limit.
        bytes memory data = abi.encodeWithSelector(bytes4(0x17171717), uint256(7));
        uint256 expiration = block.timestamp + 1 days;

        Policy memory autoPolicy = _buildApprovalPolicy(TransactionType.ContractInteractions, PolicyType.AutoApprove);
        autoPolicy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        autoPolicy.config.rateLimit.timeIntervalHours = 1;
        autoPolicy.config.rateLimit.timeIntervalLimit = 1000;

        ValidationProofs memory autoProofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, autoPolicy);
        bytes memory autoInitiatorSig = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 8, expiration, DEFAULT_POLICY_ID, true
        );

        // Call: validate auto-approve transaction.
        harness.validateTransactionApprovalOrRevertViaLibrary(
            ACCOUNT, DESTINATION, 0, data, 8, expiration, DEFAULT_POLICY_ID, autoInitiatorSig, bytes(""), autoProofs
        );

        bytes32 autoUsageKey = _computeUsageKey(DEFAULT_POLICY_ID, autoPolicy, ACCOUNT, DESTINATION, initiator1);
        uint256 autoWindow = _computeTimeWindow(autoPolicy);
        assertEq(policyStateHarness.getPolicyUsage(autoUsageKey, autoWindow), 1, "auto approval should update usage");

        uint256 manualPolicyId = DEFAULT_POLICY_ID + 1;
        Policy memory manualPolicy =
            _buildApprovalPolicy(TransactionType.ContractInteractions, PolicyType.RequireManualApproval);
        manualPolicy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        manualPolicy.config.rateLimit.timeIntervalHours = 1;
        manualPolicy.config.rateLimit.timeIntervalLimit = 1000;
        ValidationProofs memory manualProofs = _setSinglePolicyRootAndBuildProofs(manualPolicyId, manualPolicy);

        bytes memory manualInitiatorSig = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 9, expiration, manualPolicyId, true
        );
        bytes memory reviewSig = _signReviewTx(
            address(harness),
            REVIEWER_PK_1,
            ACCOUNT,
            DESTINATION,
            0,
            data,
            9,
            expiration,
            manualPolicyId,
            true,
            manualInitiatorSig
        );

        // Call: validate manual-approval transaction.
        harness.validateTransactionApprovalOrRevertViaLibrary(
            ACCOUNT, DESTINATION, 0, data, 9, expiration, manualPolicyId, manualInitiatorSig, reviewSig, manualProofs
        );

        bytes32 manualUsageKey = _computeUsageKey(manualPolicyId, manualPolicy, ACCOUNT, DESTINATION, initiator1);
        uint256 manualWindow = _computeTimeWindow(manualPolicy);
        assertEq(
            policyStateHarness.getPolicyUsage(manualUsageKey, manualWindow), 1, "manual approval should update usage"
        );
    }

    /// @dev Verifies unknown approval policy enum values fail closed in approval flow.
    function test_LOAT_VTAOR_15_validateApproval_invalidPolicyTypeFailsClosed() public {
        // Setup: build valid approval call data, then mutate policyType enum to unknown value.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        bytes memory data = abi.encodeWithSelector(bytes4(0x18181818), uint256(8));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSig = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 10, expiration, DEFAULT_POLICY_ID, true
        );

        bytes memory callData = abi.encodeCall(
            harness.validateTransactionApprovalOrRevertViaLibrary,
            (ACCOUNT, DESTINATION, 0, data, 10, expiration, DEFAULT_POLICY_ID, initiatorSig, bytes(""), proofs)
        );
        _setPolicyTypeInValidationCalldata(callData, 2);

        // Call: execute malformed policy-type call via low-level dispatch.
        (bool success,) = address(harness).call(callData);
        // Verify: unknown enum value should fail closed.
        assertFalse(success, "invalid policy type must fail closed");
    }

    /// @dev Verifies non-empty malformed initiator signature reverts in approval flow.
    function test_LOAT_VTAOR_16__LOAT_AVTAOR_4_validateApproval_malformedInitiatorSignature_reverts() public {
        // Setup: valid policy proof and malformed non-empty signature bytes.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        // Verify: malformed signature should revert during signer recovery.
        vm.expectRevert(SignatureUtils.SignatureRecoveryFailed.selector);
        // Call: validate approval with malformed signature.
        harness.validateTransactionApprovalOrRevertViaLibrary(
            ACCOUNT,
            DESTINATION,
            0,
            abi.encodeWithSelector(bytes4(0x19191919), uint256(9)),
            11,
            block.timestamp + 1 days,
            DEFAULT_POLICY_ID,
            hex"01",
            bytes(""),
            proofs
        );
    }

    /// @dev Verifies expired rejection transactions revert `TransactionExpired`.
    function test_LOAT_VTROR_1__LOAT_VTROR_3__LOAT_AVTROR_1_validateRejection_expired_revertsTransactionExpired()
        public
    {
        // Setup: build rejection payload with expiration in the past.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        bytes memory data = abi.encodeWithSelector(bytes4(0x21212121), uint256(1));
        uint256 expiration = block.timestamp - 1;
        bytes memory initiatorSig = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 12, expiration, DEFAULT_POLICY_ID, true
        );
        bytes memory rejectionSig = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 12, expiration, DEFAULT_POLICY_ID, false
        );

        // Verify: rejection path enforces expiration guard.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAccountTransaction.TransactionExpired.selector, expiration, block.timestamp
            )
        );
        // Call: validate rejection.
        harness.validateTransactionRejectionOrRevertViaLibrary(
            ACCOUNT, DESTINATION, 0, data, 12, expiration, DEFAULT_POLICY_ID, initiatorSig, rejectionSig, proofs
        );
    }

    /// @dev Verifies rejection expiration equal to block timestamp succeeds (strict `>` check).
    function test_LOACT_VTAORVTROR_10__LOAT_VTROR_2_validateRejection_expirationEqualsTimestamp_succeeds() public {
        // Setup: build valid rejection payload at boundary timestamp.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        bytes memory data = abi.encodeWithSelector(bytes4(0x22222222), uint256(2));
        uint256 expiration = block.timestamp;
        bytes memory initiatorSig = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 13, expiration, DEFAULT_POLICY_ID, true
        );
        bytes memory rejectionSig = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 13, expiration, DEFAULT_POLICY_ID, false
        );

        // Call: validate rejection at boundary timestamp.
        harness.validateTransactionRejectionOrRevertViaLibrary(
            ACCOUNT, DESTINATION, 0, data, 13, expiration, DEFAULT_POLICY_ID, initiatorSig, rejectionSig, proofs
        );
    }

    /// @dev Verifies rejection flow requires non-empty initiator signature.
    function test_LOAT_VTROR_4_validateRejection_emptyInitiatorSignature_revertsInsufficientSignaturesLength() public {
        // Setup: valid policy proof and empty initiator signature.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        // Verify: empty initiator signature is rejected.
        vm.expectRevert(IOrganizationAccountTransaction.InsufficientSignaturesLength.selector);
        // Call: validate rejection.
        harness.validateTransactionRejectionOrRevertViaLibrary(
            ACCOUNT,
            DESTINATION,
            0,
            bytes(""),
            14,
            block.timestamp + 1 days,
            DEFAULT_POLICY_ID,
            bytes(""),
            bytes(""),
            proofs
        );
    }

    /// @dev Verifies rejection flow validates initiator signature against approval hash (`isApproval=true`).
    function test_LOACT_VTAORVTROR_3__LOAT_VTROR_5_validateRejection_initiatorHashUsesApprovalFlagTrue() public {
        // Setup: sign initiator with `isApproval=false` and call rejection flow.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        bytes memory data = abi.encodeWithSelector(bytes4(0x23232323), uint256(3));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory wrongInitiatorSig = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 15, expiration, DEFAULT_POLICY_ID, false
        );
        bytes memory rejectionSig = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 15, expiration, DEFAULT_POLICY_ID, false
        );

        // Verify: mismatch initiator hash flag causes failure.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAccountTransaction.PolicyDoesNotApply.selector, DEFAULT_POLICY_ID)
        );
        // Call: validate rejection.
        harness.validateTransactionRejectionOrRevertViaLibrary(
            ACCOUNT, DESTINATION, 0, data, 15, expiration, DEFAULT_POLICY_ID, wrongInitiatorSig, rejectionSig, proofs
        );
    }

    /// @dev Verifies EOA initiator signature is recovered and accepted in rejection flow.
    function test_LOAT_VTROR_6__LOAT_VTROR_9_validateRejection_eoaInitiatorSignature_succeeds() public {
        // Setup: valid auto-approve rejection payload with EOA initiator.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        bytes memory data = abi.encodeWithSelector(bytes4(0x24242424), uint256(4));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSig = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 16, expiration, DEFAULT_POLICY_ID, true
        );
        bytes memory rejectionSig = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 16, expiration, DEFAULT_POLICY_ID, false
        );

        // Call: validate rejection.
        harness.validateTransactionRejectionOrRevertViaLibrary(
            ACCOUNT, DESTINATION, 0, data, 16, expiration, DEFAULT_POLICY_ID, initiatorSig, rejectionSig, proofs
        );
    }

    /// @dev Verifies ERC-1271 initiator signature is recovered and accepted in rejection flow.
    function test_LOAT_VTROR_7_validateRejection_erc1271InitiatorSignature_succeeds() public {
        // Setup: configure policy to authorize ERC-1271 initiator and build signatures.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        policy.config.initiator.initiatorMember = address(validSigner1271);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        bytes memory data = abi.encodeWithSelector(bytes4(0x25252525), uint256(5));

        bytes memory initiatorSig = _buildContractSignature(address(validSigner1271), hex"ABCD");
        bytes memory rejectionSig = _buildContractSignature(address(validSigner1271), hex"BCDE");

        // Call: validate rejection with ERC-1271 signatures.
        harness.validateTransactionRejectionOrRevertViaLibrary(
            ACCOUNT,
            DESTINATION,
            0,
            data,
            17,
            block.timestamp + 1 days,
            DEFAULT_POLICY_ID,
            initiatorSig,
            rejectionSig,
            proofs
        );
    }

    /// @dev Verifies rejection reverts `PolicyDoesNotApply` when policy proof does not apply.
    function test_LOAT_VTROR_8_validateRejection_policyDoesNotApply_revertsPolicyDoesNotApply() public {
        // Setup: use empty proof so policy check fails.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _emptyProofsForPolicy(policy);
        bytes memory data = abi.encodeWithSelector(bytes4(0x26262626), uint256(6));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSig = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 18, expiration, DEFAULT_POLICY_ID, true
        );
        bytes memory rejectionSig = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 18, expiration, DEFAULT_POLICY_ID, false
        );

        // Verify: rejection fails when policy proof does not match root.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAccountTransaction.PolicyDoesNotApply.selector, DEFAULT_POLICY_ID)
        );
        // Call: validate rejection.
        harness.validateTransactionRejectionOrRevertViaLibrary(
            ACCOUNT, DESTINATION, 0, data, 18, expiration, DEFAULT_POLICY_ID, initiatorSig, rejectionSig, proofs
        );
    }

    // LOAT-AVTROR-3
    /// @dev Verifies rejection flow rejects an approval-domain signature replayed as the rejection authorization.
    function test_LOAT_AVTROR_3_validateRejection_replayedApprovalSignatureFailsRejectionDomainSeparation()
        public
    {
        // Setup: build a valid auto-approve rejection context, then reuse the approval-domain signature as the
        // rejection authorization.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        bytes memory data = abi.encodeWithSelector(bytes4(0x27262626), uint256(61));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSig = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 18_1, expiration, DEFAULT_POLICY_ID, true
        );

        // Verify: replaying an approval-domain signature as the rejection authorization must fail closed.
        vm.expectRevert(IOrganizationAccountTransaction.TransactionRejectionNotAllowed.selector);
        // Call: validate rejection while reusing the approval signature bytes for the rejection path.
        harness.validateTransactionRejectionOrRevertViaLibrary(
            ACCOUNT, DESTINATION, 0, data, 18_1, expiration, DEFAULT_POLICY_ID, initiatorSig, initiatorSig, proofs
        );
    }

    // LOAT-AVTROR-4
    /// @dev Verifies manual rejection uses `isApproval=false` review hash.
    function test_LOACT_VTAORVTROR_4__LOACT_VTAORVTROR_5__LOAT_VTROR_10__LOAT_VMCOR_4__LOAT_AVTROR_4_validateRejection_manualReviewUsesRejectionFlagFalse()
        public
    {
        // Setup: manual policy and initiator signature.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.RequireManualApproval);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        bytes memory data = abi.encodeWithSelector(bytes4(0x27272727), uint256(7));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSig = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 19, expiration, DEFAULT_POLICY_ID, true
        );
        bytes memory wrongReviewSig = _signReviewTx(
            address(harness),
            REVIEWER_PK_1,
            ACCOUNT,
            DESTINATION,
            0,
            data,
            19,
            expiration,
            DEFAULT_POLICY_ID,
            true,
            initiatorSig
        );

        // Verify: approval-hash review signature cannot satisfy rejection flow.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.InsufficientApprovals.selector, 1, 0));
        // Call: validate rejection.
        harness.validateTransactionRejectionOrRevertViaLibrary(
            ACCOUNT, DESTINATION, 0, data, 19, expiration, DEFAULT_POLICY_ID, initiatorSig, wrongReviewSig, proofs
        );
    }

    /// @dev Verifies rejection path is view-only and does not mutate rate-limit usage.
    function test_LOAT_VTROR_11__LOAT_AVTROR_5_validateRejection_isView_doesNotUpdateRateLimitUsage() public {
        // Setup: configure rate-limited policy and valid auto-rejection payload.
        Policy memory policy = _buildApprovalPolicy(TransactionType.ContractInteractions, PolicyType.AutoApprove);
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = 100;

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        bytes memory data = abi.encodeWithSelector(bytes4(0x28282828), uint256(8));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSig = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 20, expiration, DEFAULT_POLICY_ID, true
        );
        bytes memory rejectionSig = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 20, expiration, DEFAULT_POLICY_ID, false
        );
        bytes32 usageKey = _computeUsageKey(DEFAULT_POLICY_ID, policy, ACCOUNT, DESTINATION, initiator1);
        uint256 window = _computeTimeWindow(policy);
        policyStateHarness.setPolicyUsage(usageKey, window, 7);

        // Call: validate rejection.
        harness.validateTransactionRejectionOrRevertViaLibrary(
            ACCOUNT, DESTINATION, 0, data, 20, expiration, DEFAULT_POLICY_ID, initiatorSig, rejectionSig, proofs
        );

        // Verify: rejection flow does not mutate usage storage.
        assertEq(policyStateHarness.getPolicyUsage(usageKey, window), 7, "rejection path must remain view-only");
    }

    /// @dev Verifies unknown approval policy enum values fail closed in rejection flow.
    function test_LOAT_VTROR_12_validateRejection_invalidPolicyTypeFailsClosed() public {
        // Setup: build valid rejection calldata, then mutate policyType enum to unknown value.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        bytes memory data = abi.encodeWithSelector(bytes4(0x29292929), uint256(9));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSig = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 21, expiration, DEFAULT_POLICY_ID, true
        );
        bytes memory rejectionSig = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 21, expiration, DEFAULT_POLICY_ID, false
        );

        bytes memory callData = abi.encodeCall(
            harness.validateTransactionRejectionOrRevertViaLibrary,
            (ACCOUNT, DESTINATION, 0, data, 21, expiration, DEFAULT_POLICY_ID, initiatorSig, rejectionSig, proofs)
        );
        _setPolicyTypeInValidationCalldata(callData, 2);

        // Call: execute malformed enum call.
        (bool success,) = address(harness).call(callData);
        // Verify: unknown enum value should fail closed.
        assertFalse(success, "invalid policy type must fail closed in rejection flow");
    }

    /// @dev Verifies malformed initiator signature reverts in rejection flow.
    function test_LOAT_VTROR_13_validateRejection_malformedInitiatorSignature_reverts() public {
        // Setup: valid proof payload with malformed initiator signature.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        bytes memory data = abi.encodeWithSelector(bytes4(0x30303030), uint256(10));

        // Verify: malformed initiator signature should revert signer recovery.
        vm.expectRevert(SignatureUtils.SignatureRecoveryFailed.selector);
        // Call: validate rejection with malformed signature.
        harness.validateTransactionRejectionOrRevertViaLibrary(
            ACCOUNT, DESTINATION, 0, data, 22, block.timestamp + 1 days, DEFAULT_POLICY_ID, hex"01", hex"02", proofs
        );
    }

    // Helpers

    function _setPolicyTypeInValidationCalldata(bytes memory callData, uint256 rawValue) internal pure {
        uint256 proofsOffset = _readWord(callData, 4 + 9 * 32);
        _setWord(callData, 4 + proofsOffset + 4 * 32, rawValue);
    }
}
