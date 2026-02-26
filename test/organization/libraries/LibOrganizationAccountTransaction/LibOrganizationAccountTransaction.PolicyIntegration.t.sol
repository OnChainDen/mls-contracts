// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOrganizationAccountTransaction} from "interfaces/organization/IOrganizationAccountTransaction.sol";

import {
    LibOrganizationAccountTransactionHarness
} from "test/organization/libraries/LibOrganizationAccountTransaction/LibOrganizationAccountTransactionHarness.sol";
import {
    LibOrganizationAccountTransactionSuiteBase
} from "test/organization/libraries/LibOrganizationAccountTransaction/LibOrganizationAccountTransactionSuiteBase.sol";
import {
    ApproverType,
    Policy,
    PolicyType,
    RateLimitScope,
    RateLimitType,
    TransactionType,
    ValidationProofs
} from "types/PolicyTypes.sol";

/**
 * @dev Policy-coupled integration tests for `LibOrganizationAccountTransaction`.
 */
contract LibOrganizationAccountTransactionPolicyIntegrationTest is LibOrganizationAccountTransactionSuiteBase {
    uint256 internal constant DEFAULT_POLICY_ID = 77;

    address internal constant ACCOUNT = address(0xA1101);
    address internal constant DESTINATION = address(0xB2202);
    address internal constant TOKEN = address(0xC3303);
    address internal constant RECIPIENT = address(0xD4404);

    function setUp() public override {
        super.setUp();

        // Shared members used by initiator/reviewer policy paths.
        policyStateHarness.setMemberStatus(initiator1, true);
        policyStateHarness.setMemberStatus(initiator2, true);
        policyStateHarness.setMemberStatus(reviewer1, true);
        policyStateHarness.setMemberStatus(reviewer2, true);
    }

    /// @dev Verifies that policy does not apply reverts policy does not apply.
    function test_LOAT_1_policyDoesNotApply_revertsPolicyDoesNotApply() public {
        // Setup: assemble inputs expected to hit the guarded failure path for policy does not apply reverts policy does not apply.
        Policy memory policy = _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.AutoApprove});
        ValidationProofs memory proofs = _emptyProofsForPolicy(policy);

        uint256 expiration = block.timestamp + 1 days;
        bytes memory data = abi.encodeWithSelector(bytes4(0x12345678), uint256(1));
        bytes memory initiatorSignature = _signInitiatorTx({
            txHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 1,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAccountTransaction.PolicyDoesNotApply.selector, DEFAULT_POLICY_ID)
        );
        // Call: invoke `validateTransactionApprovalOrRevertViaLibrary` with the failing payload to exercise the revert branch.
        harness.validateTransactionApprovalOrRevertViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 1,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });
    }

    /// @dev Verifies that policy proof tampering reverts policy does not apply.
    function test_LOAT_2_policyProofTampering_revertsPolicyDoesNotApply() public {
        // Setup: assemble inputs expected to hit the guarded failure path for policy proof tampering reverts policy does not apply.
        Policy memory policy = _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.AutoApprove});
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        proofs.policyProof = new bytes32[](1);
        proofs.policyProof[0] = keccak256("tampered-proof");

        uint256 expiration = block.timestamp + 1 days;
        bytes memory data = abi.encodeWithSelector(bytes4(0x12345678), uint256(2));
        bytes memory initiatorSignature = _signInitiatorTx({
            txHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 2,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAccountTransaction.PolicyDoesNotApply.selector, DEFAULT_POLICY_ID)
        );
        // Call: invoke `validateTransactionApprovalOrRevertViaLibrary` with the failing payload to exercise the revert branch.
        harness.validateTransactionApprovalOrRevertViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 2,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });
    }

    /// @dev Verifies that signature policy cannot authorize account transactions.
    function test_LOAT_3_signaturePolicyCannotAuthorizeAccountTransactions() public {
        // Setup: assemble inputs expected to hit the guarded failure path for signature policy cannot authorize account transactions.
        Policy memory policy =
            _buildApprovalPolicy({txType: TransactionType.Signatures, approvalType: PolicyType.AutoApprove});
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        uint256 expiration = block.timestamp + 1 days;
        bytes memory data = abi.encodeWithSelector(bytes4(0x11223344), uint256(3));
        bytes memory initiatorSignature = _signInitiatorTx({
            txHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 3,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAccountTransaction.PolicyDoesNotApply.selector, DEFAULT_POLICY_ID)
        );
        // Call: invoke `validateTransactionApprovalOrRevertViaLibrary` with the failing payload to exercise the revert branch.
        harness.validateTransactionApprovalOrRevertViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 3,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });
    }

    /// @dev Verifies that manual approval without reviewers reverts insufficient approvals.
    function test_LOAT_4_manualApprovalWithoutReviewers_revertsInsufficientApprovals() public {
        // Setup: assemble inputs expected to hit the guarded failure path for manual approval without reviewers reverts insufficient approvals.
        Policy memory policy =
            _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.RequireManualApproval});
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        uint256 expiration = block.timestamp + 1 days;
        bytes memory data = abi.encodeWithSelector(bytes4(0xAABBCCDD), uint256(4));
        bytes memory initiatorSignature = _signInitiatorTx({
            txHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 4,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.InsufficientApprovals.selector, 1, 0));
        // Call: invoke `validateTransactionApprovalOrRevertViaLibrary` with the failing payload to exercise the revert branch.
        harness.validateTransactionApprovalOrRevertViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 4,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });
    }

    /// @dev Verifies that manual approval with valid threshold succeeds.
    function test_LOAT_5_manualApprovalWithValidThreshold_succeeds() public {
        // Setup: configure a valid fixture for manual approval with valid threshold succeeds.
        Policy memory policy =
            _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.RequireManualApproval});
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        uint256 expiration = block.timestamp + 1 days;
        bytes memory data = abi.encodeWithSelector(bytes4(0x01020304), uint256(5));
        bytes memory initiatorSignature = _signInitiatorTx({
            txHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 5,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });
        bytes memory reviewSignature = _signReviewTx({
            txHarness: harness,
            privateKey: REVIEWER_PK_1,
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 5,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true,
            initiatorSignature: initiatorSignature
        });

        // Call: execute `validateTransactionApprovalOrRevertViaLibrary` with the happy-path payload.
        harness.validateTransactionApprovalOrRevertViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 5,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: reviewSignature,
            proofs: proofs
        });
    }

    /// @dev Verifies that auto approve ignores reviewer signatures.
    function test_LOAT_6_autoApproveIgnoresReviewerSignatures() public {
        // Setup: configure a valid fixture for auto approve ignores reviewer signatures.
        Policy memory policy = _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.AutoApprove});
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        uint256 expiration = block.timestamp + 1 days;
        bytes memory data = abi.encodeWithSelector(bytes4(0x11121314), uint256(6));
        bytes memory initiatorSignature = _signInitiatorTx({
            txHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 6,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        // Call: execute `validateTransactionApprovalOrRevertViaLibrary` with the happy-path payload.
        harness.validateTransactionApprovalOrRevertViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 6,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: hex"deadbeef",
            proofs: proofs
        });
    }

    /// @dev Verifies that rate limit exceeded reverts rate limit exceeded.
    function test_LOAT_7_rateLimitExceeded_revertsRateLimitExceeded() public {
        // Setup: assemble inputs expected to hit the guarded failure path for rate limit exceeded reverts rate limit exceeded.
        uint256 amount = 101;

        Policy memory policy =
            _buildApprovalPolicy({txType: TransactionType.TokenTransfers, approvalType: PolicyType.AutoApprove});
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = 100;

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        bytes memory data = _encodeERC20Transfer(RECIPIENT, amount);
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorTx({
            txHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            to: TOKEN,
            value: 0,
            data: data,
            salt: 7,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAccountTransaction.RateLimitExceeded.selector, DEFAULT_POLICY_ID)
        );
        // Call: invoke `validateTransactionApprovalOrRevertViaLibrary` with the failing payload to exercise the revert branch.
        harness.validateTransactionApprovalOrRevertViaLibrary({
            account: ACCOUNT,
            to: TOKEN,
            value: 0,
            data: data,
            salt: 7,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });
    }

    /// @dev Verifies that token transfer rate limit usage tracks transfer amount.
    function test_LOAT_8_tokenTransferRateLimitUsageTracksTransferAmount() public {
        // Setup: configure a valid fixture for token transfer rate limit usage tracks transfer amount.
        uint256 amount = 42;

        Policy memory policy =
            _buildApprovalPolicy({txType: TransactionType.TokenTransfers, approvalType: PolicyType.AutoApprove});
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = 1000;

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        bytes memory data = _encodeERC20Transfer(RECIPIENT, amount);
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorTx({
            txHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            to: TOKEN,
            value: 0,
            data: data,
            salt: 8,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        // Call: execute `validateTransactionApprovalOrRevertViaLibrary` with the happy-path payload.
        harness.validateTransactionApprovalOrRevertViaLibrary({
            account: ACCOUNT,
            to: TOKEN,
            value: 0,
            data: data,
            salt: 8,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        bytes32 usageKey = _computeUsageKey(DEFAULT_POLICY_ID, policy, ACCOUNT, RECIPIENT, initiator1);
        uint256 window = _computeTimeWindow(policy);
        // Verify: assert the expected success result and state updates.
        assertEq(policyStateHarness.getPolicyUsage(usageKey, window), amount, "usage should equal transfer amount");
    }

    /// @dev Verifies that non token rate limit usage increments by one.
    function test_LOAT_9_nonTokenRateLimitUsageIncrementsByOne() public {
        // Setup: configure a valid fixture for non token rate limit usage increments by one.
        Policy memory policy =
            _buildApprovalPolicy({txType: TransactionType.ContractInteractions, approvalType: PolicyType.AutoApprove});
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = 1000;

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        bytes memory data = abi.encodeWithSelector(bytes4(0xDEADBEEF), uint256(9));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorTx({
            txHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 9,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        // Call: execute `validateTransactionApprovalOrRevertViaLibrary` with the happy-path payload.
        harness.validateTransactionApprovalOrRevertViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 9,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        bytes32 usageKey = _computeUsageKey(DEFAULT_POLICY_ID, policy, ACCOUNT, DESTINATION, initiator1);
        uint256 window = _computeTimeWindow(policy);
        // Verify: assert the expected success result and state updates.
        assertEq(policyStateHarness.getPolicyUsage(usageKey, window), 1, "non-token usage should increment by one");
    }

    /// @dev Verifies that rate limit key uses erc20 recipient as destination.
    function test_LOAT_10_rateLimitKeyUsesERC20RecipientAsDestination() public {
        // Setup: configure a valid fixture for rate limit key uses erc20 recipient as destination.
        uint256 amount = 11;

        Policy memory policy =
            _buildApprovalPolicy({txType: TransactionType.TokenTransfers, approvalType: PolicyType.AutoApprove});
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = 1000;
        policy.config.rateLimit.destinationScope = RateLimitScope.PerEntity;

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        bytes memory data = _encodeERC20Transfer(RECIPIENT, amount);
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorTx({
            txHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            to: TOKEN,
            value: 0,
            data: data,
            salt: 10,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        // Call: execute `validateTransactionApprovalOrRevertViaLibrary` with the happy-path payload.
        harness.validateTransactionApprovalOrRevertViaLibrary({
            account: ACCOUNT,
            to: TOKEN,
            value: 0,
            data: data,
            salt: 10,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        bytes32 recipientKey = _computeUsageKey(DEFAULT_POLICY_ID, policy, ACCOUNT, RECIPIENT, initiator1);
        bytes32 tokenKey = _computeUsageKey(DEFAULT_POLICY_ID, policy, ACCOUNT, TOKEN, initiator1);
        uint256 window = _computeTimeWindow(policy);

        // Verify: assert the expected success result and state updates.
        assertEq(policyStateHarness.getPolicyUsage(recipientKey, window), amount, "recipient key should be charged");
        assertEq(policyStateHarness.getPolicyUsage(tokenKey, window), 0, "token-contract key should remain untouched");
    }

    /// @dev Verifies that auto reject requires authorized initiator signature.
    function test_LOAT_11_autoRejectRequiresAuthorizedInitiatorSignature() public {
        // Setup: assemble inputs expected to hit the guarded failure path for auto reject requires authorized initiator signature.
        Policy memory policy = _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.AutoApprove});
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        bytes memory data = abi.encodeWithSelector(bytes4(0xFAFAFAFA), uint256(11));
        uint256 expiration = block.timestamp + 1 days;

        bytes memory initiatorSignature = _signInitiatorTx({
            txHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 11,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        // Rejection signature is from reviewer, not from an authorized initiator.
        bytes memory rejectionSignature = _signInitiatorTx({
            txHarness: harness,
            privateKey: REVIEWER_PK_1,
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 11,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: false
        });

        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert(IOrganizationAccountTransaction.TransactionRejectionNotAllowed.selector);
        // Call: invoke `validateTransactionRejectionOrRevertViaLibrary` with the failing payload to exercise the revert branch.
        harness.validateTransactionRejectionOrRevertViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 11,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: rejectionSignature,
            proofs: proofs
        });
    }

    /// @dev Verifies that manual reject without threshold approvals reverts insufficient approvals.
    function test_LOAT_12_manualRejectWithoutThresholdApprovals_revertsInsufficientApprovals() public {
        // Setup: assemble inputs expected to hit the guarded failure path for manual reject without threshold approvals reverts insufficient approvals.
        Policy memory policy =
            _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.RequireManualApproval});
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        bytes memory data = abi.encodeWithSelector(bytes4(0x0B0B0B0B), uint256(12));
        uint256 expiration = block.timestamp + 1 days;

        bytes memory initiatorSignature = _signInitiatorTx({
            txHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 12,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.InsufficientApprovals.selector, 1, 0));
        // Call: invoke `validateTransactionRejectionOrRevertViaLibrary` with the failing payload to exercise the revert branch.
        harness.validateTransactionRejectionOrRevertViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 12,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });
    }

    /// @dev Verifies that approval review signatures cannot replay as rejection.
    function test_LOAT_13_approvalReviewSignaturesCannotReplayAsRejection() public {
        // Setup: assemble inputs expected to hit the guarded failure path for approval review signatures cannot replay as rejection.
        Policy memory policy =
            _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.RequireManualApproval});
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        bytes memory data = abi.encodeWithSelector(bytes4(0xC0FFEE00), uint256(13));
        uint256 expiration = block.timestamp + 1 days;

        bytes memory initiatorSignature = _signInitiatorTx({
            txHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 13,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        // Approval review hash (isApproval=true) should not authorize rejection path (isApproval=false).
        bytes memory approvalReviewSignature = _signReviewTx({
            txHarness: harness,
            privateKey: REVIEWER_PK_1,
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 13,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true,
            initiatorSignature: initiatorSignature
        });

        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert();
        // Call: invoke `validateTransactionRejectionOrRevertViaLibrary` with the failing payload to exercise the revert branch.
        harness.validateTransactionRejectionOrRevertViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 13,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: approvalReviewSignature,
            proofs: proofs
        });
    }

    /// @dev Verifies that hash builders are deterministic and field bound.
    function test_LOAT_14_hashBuildersAreDeterministicAndFieldBound() public {
        // Setup: configure a valid fixture for hash builders are deterministic and field bound.
        uint256 expiration = block.timestamp + 1 days;
        bytes memory data = abi.encodeWithSelector(bytes4(0xCAFED00D), uint256(14));

        // Call: execute `computeInitiatorHashFromParamsViaLibrary` with the happy-path payload.
        bytes32 baseInitiatorHashA = harness.computeInitiatorHashFromParamsViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 1,
            salt: 14,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            data: data,
            isApproval: true
        });
        bytes32 baseInitiatorHashB = harness.computeInitiatorHashFromParamsViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 1,
            salt: 14,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            data: data,
            isApproval: true
        });
        // Verify: assert the expected success result and state updates.
        assertEq(baseInitiatorHashA, baseInitiatorHashB, "initiator hash must be deterministic");

        assertTrue(
            baseInitiatorHashA
                != harness.computeInitiatorHashFromParamsViaLibrary({
                    account: address(uint160(ACCOUNT) + 1),
                    to: DESTINATION,
                    value: 1,
                    salt: 14,
                    expirationTimestamp: expiration,
                    policyId: DEFAULT_POLICY_ID,
                    data: data,
                    isApproval: true
                }),
            "account must be bound"
        );
        assertTrue(
            baseInitiatorHashA
                != harness.computeInitiatorHashFromParamsViaLibrary({
                    account: ACCOUNT,
                    to: address(uint160(DESTINATION) + 1),
                    value: 1,
                    salt: 14,
                    expirationTimestamp: expiration,
                    policyId: DEFAULT_POLICY_ID,
                    data: data,
                    isApproval: true
                }),
            "to must be bound"
        );
        assertTrue(
            baseInitiatorHashA
                != harness.computeInitiatorHashFromParamsViaLibrary({
                    account: ACCOUNT,
                    to: DESTINATION,
                    value: 2,
                    salt: 14,
                    expirationTimestamp: expiration,
                    policyId: DEFAULT_POLICY_ID,
                    data: data,
                    isApproval: true
                }),
            "value must be bound"
        );
        assertTrue(
            baseInitiatorHashA
                != harness.computeInitiatorHashFromParamsViaLibrary({
                    account: ACCOUNT,
                    to: DESTINATION,
                    value: 1,
                    salt: 15,
                    expirationTimestamp: expiration,
                    policyId: DEFAULT_POLICY_ID,
                    data: data,
                    isApproval: true
                }),
            "salt must be bound"
        );
        assertTrue(
            baseInitiatorHashA
                != harness.computeInitiatorHashFromParamsViaLibrary({
                    account: ACCOUNT,
                    to: DESTINATION,
                    value: 1,
                    salt: 14,
                    expirationTimestamp: expiration + 1,
                    policyId: DEFAULT_POLICY_ID,
                    data: data,
                    isApproval: true
                }),
            "expiration must be bound"
        );
        assertTrue(
            baseInitiatorHashA
                != harness.computeInitiatorHashFromParamsViaLibrary({
                    account: ACCOUNT,
                    to: DESTINATION,
                    value: 1,
                    salt: 14,
                    expirationTimestamp: expiration,
                    policyId: DEFAULT_POLICY_ID + 1,
                    data: data,
                    isApproval: true
                }),
            "policyId must be bound"
        );
        assertTrue(
            baseInitiatorHashA
                != harness.computeInitiatorHashFromParamsViaLibrary({
                    account: ACCOUNT,
                    to: DESTINATION,
                    value: 1,
                    salt: 14,
                    expirationTimestamp: expiration,
                    policyId: DEFAULT_POLICY_ID,
                    data: abi.encodeWithSelector(bytes4(0xCAFED00E), uint256(14)),
                    isApproval: true
                }),
            "data must be bound"
        );
        assertTrue(
            baseInitiatorHashA
                != harness.computeInitiatorHashFromParamsViaLibrary({
                    account: ACCOUNT,
                    to: DESTINATION,
                    value: 1,
                    salt: 14,
                    expirationTimestamp: expiration,
                    policyId: DEFAULT_POLICY_ID,
                    data: data,
                    isApproval: false
                }),
            "isApproval must be bound"
        );

        uint256 originalChainId = block.chainid;
        vm.chainId(originalChainId + 1);
        bytes32 chainChangedHash = harness.computeInitiatorHashFromParamsViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 1,
            salt: 14,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            data: data,
            isApproval: true
        });
        vm.chainId(originalChainId);
        assertTrue(baseInitiatorHashA != chainChangedHash, "chainId must be bound");

        bytes memory initiatorSignature = _signHash(INITIATOR_PK_1, baseInitiatorHashA);
        bytes32 baseReviewHashA = harness.computeReviewHashFromParamsViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 1,
            salt: 14,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            data: data,
            isApproval: true,
            initiatorSignature: initiatorSignature
        });
        bytes32 baseReviewHashB = harness.computeReviewHashFromParamsViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 1,
            salt: 14,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            data: data,
            isApproval: true,
            initiatorSignature: initiatorSignature
        });
        assertEq(baseReviewHashA, baseReviewHashB, "review hash must be deterministic");

        bytes memory differentInitiatorSig = _signHash(INITIATOR_PK_2, baseInitiatorHashA);
        bytes32 changedReviewHash = harness.computeReviewHashFromParamsViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 1,
            salt: 14,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            data: data,
            isApproval: true,
            initiatorSignature: differentInitiatorSig
        });
        assertTrue(baseReviewHashA != changedReviewHash, "review hash must bind initiator signature bytes");
    }

    /// @dev Verifies that desired any policy token transfers use count based rate usage.
    function test_LOAT_15_desired_anyPolicyTokenTransfersUseCountBasedRateUsage() public {
        // Setup: configure a valid fixture for desired any policy token transfers use count based rate usage.
        uint256 amount = 500;

        Policy memory policy = _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.AutoApprove});
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = 1000;

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        bytes memory data = _encodeERC20Transfer(RECIPIENT, amount);
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorTx({
            txHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            to: TOKEN,
            value: 0,
            data: data,
            salt: 15,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        // Call: execute `validateTransactionApprovalOrRevertViaLibrary` with the happy-path payload.
        harness.validateTransactionApprovalOrRevertViaLibrary({
            account: ACCOUNT,
            to: TOKEN,
            value: 0,
            data: data,
            salt: 15,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        bytes32 usageKey = _computeUsageKey(DEFAULT_POLICY_ID, policy, ACCOUNT, RECIPIENT, initiator1);
        uint256 window = _computeTimeWindow(policy);
        // Verify: assert the expected success result and state updates.
        assertEq(policyStateHarness.getPolicyUsage(usageKey, window), 1, "usage should be count-based for txType Any");
    }

    /// @dev Verifies that policy does not apply does not mutate rate usage.
    function test_LOAT_16_policyDoesNotApply_doesNotMutateRateUsage() public {
        // Setup: assemble inputs expected to hit the guarded failure path for policy does not apply does not mutate rate usage.
        Policy memory policy = _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.AutoApprove});
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = 1000;
        policy.config.rateLimit.destinationScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.sourceScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.initiatorScope = RateLimitScope.PerEntity;

        // Intentionally keep root unset and use empty proof => PolicyDoesNotApply before rate-limit update.
        ValidationProofs memory proofs = _emptyProofsForPolicy(policy);

        bytes memory data = abi.encodeWithSelector(bytes4(0x16161616), uint256(16));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorTx({
            txHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 16,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        bytes32 usageKey = _computeUsageKey(DEFAULT_POLICY_ID, policy, ACCOUNT, DESTINATION, initiator1);
        uint256 window = _computeTimeWindow(policy);
        policyStateHarness.setPolicyUsage(usageKey, window, 9);

        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAccountTransaction.PolicyDoesNotApply.selector, DEFAULT_POLICY_ID)
        );
        // Call: invoke `validateTransactionApprovalOrRevertViaLibrary` with the failing payload to exercise the revert branch.
        harness.validateTransactionApprovalOrRevertViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 16,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        assertEq(
            policyStateHarness.getPolicyUsage(usageKey, window), 9, "usage must remain unchanged on pre-check failure"
        );
    }

    /// @dev Verifies that insufficient approvals does not mutate rate usage.
    function test_LOAT_17_insufficientApprovals_doesNotMutateRateUsage() public {
        // Setup: assemble inputs expected to hit the guarded failure path for insufficient approvals does not mutate rate usage.
        Policy memory policy =
            _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.RequireManualApproval});
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = 1000;
        policy.config.rateLimit.destinationScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.sourceScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.initiatorScope = RateLimitScope.PerEntity;

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        bytes memory data = abi.encodeWithSelector(bytes4(0x17171717), uint256(17));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorTx({
            txHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 17,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        bytes32 usageKey = _computeUsageKey(DEFAULT_POLICY_ID, policy, ACCOUNT, DESTINATION, initiator1);
        uint256 window = _computeTimeWindow(policy);
        policyStateHarness.setPolicyUsage(usageKey, window, 7);

        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.InsufficientApprovals.selector, 1, 0));
        // Call: invoke `validateTransactionApprovalOrRevertViaLibrary` with the failing payload to exercise the revert branch.
        harness.validateTransactionApprovalOrRevertViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 17,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        assertEq(
            policyStateHarness.getPolicyUsage(usageKey, window),
            7,
            "usage must remain unchanged on manual-check failure"
        );
    }

    /// @dev Verifies that root transition guard clear root rejects old proofs.
    function test_LOAT_18_rootTransitionGuard_clearRootRejectsOldProofs() public {
        // Setup: assemble inputs expected to hit the guarded failure path for root transition guard clear root rejects old proofs.
        Policy memory policy = _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.AutoApprove});
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        bytes memory data = abi.encodeWithSelector(bytes4(0x18181818), uint256(18));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorTx({
            txHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 18,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        // Under R1: succeeds.
        // Call: invoke `validateTransactionApprovalOrRevertViaLibrary` with the failing payload to exercise the revert branch.
        harness.validateTransactionApprovalOrRevertViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 18,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        // Clear root.
        policyStateHarness.setPoliciesRoot(bytes32(0));

        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAccountTransaction.PolicyDoesNotApply.selector, DEFAULT_POLICY_ID)
        );
        harness.validateTransactionApprovalOrRevertViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 18,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });
    }

    /// @dev Verifies that branch comparison auto approve succeeds manual without reviews reverts.
    function test_LOAT_19_branchComparison_autoApproveSucceeds_manualWithoutReviewsReverts() public {
        // Setup: assemble inputs expected to hit the guarded failure path for branch comparison auto approve succeeds manual without reviews reverts.
        bytes memory data = abi.encodeWithSelector(bytes4(0x19191919), uint256(19));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorTx({
            txHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 19,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        Policy memory autoPolicy =
            _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.AutoApprove});
        ValidationProofs memory autoProofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, autoPolicy);

        // Call: invoke `validateTransactionApprovalOrRevertViaLibrary` with the failing payload to exercise the revert branch.
        harness.validateTransactionApprovalOrRevertViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 19,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: autoProofs
        });

        Policy memory manualPolicy =
            _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.RequireManualApproval});
        ValidationProofs memory manualProofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, manualPolicy);

        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.InsufficientApprovals.selector, 1, 0));
        harness.validateTransactionApprovalOrRevertViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 19,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: manualProofs
        });
    }

    /// @dev Verifies that desired invalid approval policy type must fail closed.
    function test_LOAT_20_desired_invalidApprovalPolicyTypeMustFailClosed() public {
        // Setup: assemble inputs expected to hit the guarded failure path for desired invalid approval policy type must fail closed.
        Policy memory policy = _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.AutoApprove});
        _unsafeSetApprovalPolicyTypeRaw(policy, 2);

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        bytes memory data = abi.encodeWithSelector(bytes4(0x20202020), uint256(20));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorTx({
            txHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 20,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert();
        // Call: invoke `validateTransactionApprovalOrRevertViaLibrary` with the failing payload to exercise the revert branch.
        harness.validateTransactionApprovalOrRevertViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 20,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });
    }

    /// @dev Verifies that branch comparison manual with reviews and auto with same payload both succeed.
    function test_LOAT_21_branchComparison_manualWithReviewsAndAutoWithSamePayloadBothSucceed() public {
        // Setup: configure a valid fixture for branch comparison manual with reviews and auto with same payload both succeed.
        bytes memory data = abi.encodeWithSelector(bytes4(0x21212121), uint256(21));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorTx({
            txHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 21,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });
        bytes memory reviewSignature = _signReviewTx({
            txHarness: harness,
            privateKey: REVIEWER_PK_1,
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 21,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true,
            initiatorSignature: initiatorSignature
        });

        Policy memory manualPolicy =
            _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.RequireManualApproval});
        ValidationProofs memory manualProofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, manualPolicy);

        // Call: execute `validateTransactionApprovalOrRevertViaLibrary` with the happy-path payload.
        harness.validateTransactionApprovalOrRevertViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 21,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: reviewSignature,
            proofs: manualProofs
        });

        Policy memory autoPolicy =
            _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.AutoApprove});
        ValidationProofs memory autoProofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, autoPolicy);

        harness.validateTransactionApprovalOrRevertViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 21,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: reviewSignature,
            proofs: autoProofs
        });
    }

    /// @dev Verifies that rejection branch comparison auto succeeds manual insufficient for same payload.
    function test_LOAT_22_rejectionBranchComparison_autoSucceeds_manualInsufficientForSamePayload() public {
        // Setup: assemble inputs expected to hit the guarded failure path for rejection branch comparison auto succeeds manual insufficient for same payload.
        bytes memory data = abi.encodeWithSelector(bytes4(0x22222222), uint256(22));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorTx({
            txHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 22,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        bytes memory rejectionByInitiator = _signInitiatorTx({
            txHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 22,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: false
        });

        // Manual policy: group threshold=2. One valid signer should yield InsufficientApprovals.
        Policy memory manualPolicy =
            _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.RequireManualApproval});
        manualPolicy.config.approval.approverType = ApproverType.Group;
        manualPolicy.config.approval.approverGroupId = 922;
        manualPolicy.config.approval.approvalThreshold = 2;

        policyStateHarness.setGroupStatus(922, true);
        policyStateHarness.setGroupMemberStatus(922, initiator1, true);

        Policy memory autoPolicy = manualPolicy;
        autoPolicy.config.approval.policyType = PolicyType.AutoApprove;

        ValidationProofs memory autoProofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, autoPolicy);
        // Call: invoke `validateTransactionRejectionOrRevertViaLibrary` with the failing payload to exercise the revert branch.
        harness.validateTransactionRejectionOrRevertViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 22,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: rejectionByInitiator,
            proofs: autoProofs
        });

        ValidationProofs memory manualProofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, manualPolicy);
        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.InsufficientApprovals.selector, 2, 0));
        harness.validateTransactionRejectionOrRevertViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 22,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: rejectionByInitiator,
            proofs: manualProofs
        });
    }

    /// @dev Verifies that rejection branch comparison manual succeeds auto rejects same reviewer payload.
    function test_LOAT_23_rejectionBranchComparison_manualSucceeds_autoRejectsSameReviewerPayload() public {
        // Setup: assemble inputs expected to hit the guarded failure path for rejection branch comparison manual succeeds auto rejects same reviewer payload.
        bytes memory data = abi.encodeWithSelector(bytes4(0x23232323), uint256(23));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorTx({
            txHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 23,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });
        bytes memory reviewerRejectionSignature = _signReviewTx({
            txHarness: harness,
            privateKey: REVIEWER_PK_1,
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 23,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: false,
            initiatorSignature: initiatorSignature
        });

        Policy memory manualPolicy =
            _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.RequireManualApproval});
        ValidationProofs memory manualProofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, manualPolicy);
        // Call: invoke `validateTransactionRejectionOrRevertViaLibrary` with the failing payload to exercise the revert branch.
        harness.validateTransactionRejectionOrRevertViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 23,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: reviewerRejectionSignature,
            proofs: manualProofs
        });

        Policy memory autoPolicy = manualPolicy;
        autoPolicy.config.approval.policyType = PolicyType.AutoApprove;
        ValidationProofs memory autoProofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, autoPolicy);

        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert(IOrganizationAccountTransaction.TransactionRejectionNotAllowed.selector);
        harness.validateTransactionRejectionOrRevertViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 23,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: reviewerRejectionSignature,
            proofs: autoProofs
        });
    }

    /// @dev Verifies that cross chain replay initiator signature fails.
    function test_LOAT_24_crossChainReplayInitiatorSignatureFails() public {
        // Setup: assemble inputs expected to hit the guarded failure path for cross chain replay initiator signature fails.
        Policy memory policy = _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.AutoApprove});
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        bytes memory data = abi.encodeWithSelector(bytes4(0x24242424), uint256(24));
        uint256 expiration = block.timestamp + 1 days;

        vm.chainId(1);
        bytes memory initiatorSignatureChainA = _signInitiatorTx({
            txHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 24,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        vm.chainId(31_337);
        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAccountTransaction.PolicyDoesNotApply.selector, DEFAULT_POLICY_ID)
        );
        // Call: invoke `validateTransactionApprovalOrRevertViaLibrary` with the failing payload to exercise the revert branch.
        harness.validateTransactionApprovalOrRevertViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 24,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignatureChainA,
            reviewSignatures: bytes(""),
            proofs: proofs
        });
    }

    /// @dev Verifies that cross chain replay reviewer signatures fail with valid chain b initiator.
    function test_LOAT_25_crossChainReplayReviewerSignaturesFailWithValidChainBInitiator() public {
        // Setup: assemble inputs expected to hit the guarded failure path for cross chain replay reviewer signatures fail with valid chain b initiator.
        Policy memory policy =
            _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.RequireManualApproval});
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        bytes memory data = abi.encodeWithSelector(bytes4(0x25252525), uint256(25));
        uint256 expiration = block.timestamp + 1 days;

        vm.chainId(31_337);
        bytes memory initiatorSignatureChainB = _signInitiatorTx({
            txHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 25,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        vm.chainId(1);
        bytes memory reviewerSignatureChainA = _signReviewTx({
            txHarness: harness,
            privateKey: REVIEWER_PK_1,
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 25,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true,
            initiatorSignature: initiatorSignatureChainB
        });

        vm.chainId(31_337);
        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert();
        // Call: invoke `validateTransactionApprovalOrRevertViaLibrary` with the failing payload to exercise the revert branch.
        harness.validateTransactionApprovalOrRevertViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 25,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignatureChainB,
            reviewSignatures: reviewerSignatureChainA,
            proofs: proofs
        });
    }

    /// @dev Verifies that desired invalid rate limit type must fail closed.
    function test_LOAT_26_desired_invalidRateLimitTypeMustFailClosed() public {
        // Setup: assemble inputs expected to hit the guarded failure path for desired invalid rate limit type must fail closed.
        Policy memory policy =
            _buildApprovalPolicy({txType: TransactionType.TokenTransfers, approvalType: PolicyType.AutoApprove});
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = 1;
        _unsafeSetRateLimitTypeRaw(policy, 2);

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        bytes memory data = _encodeERC20Transfer(RECIPIENT, 1000);
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorTx({
            txHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            to: TOKEN,
            value: 0,
            data: data,
            salt: 26,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert();
        // Call: invoke `validateTransactionApprovalOrRevertViaLibrary` with the failing payload to exercise the revert branch.
        harness.validateTransactionApprovalOrRevertViaLibrary({
            account: ACCOUNT,
            to: TOKEN,
            value: 0,
            data: data,
            salt: 26,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });
    }

    /// @dev Verifies that cross organization replay initiator signature fails.
    function test_LOAT_27_crossOrganizationReplayInitiatorSignatureFails() public {
        // Setup: assemble inputs expected to hit the guarded failure path for cross organization replay initiator signature fails.
        LibOrganizationAccountTransactionHarness orgB = new LibOrganizationAccountTransactionHarness();

        // Seed shared org state.
        _seedMembers(address(orgB));

        Policy memory policy = _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.AutoApprove});
        bytes32 root = _computePolicyLeaf(DEFAULT_POLICY_ID, policy);
        policyStateHarness.setPoliciesRoot(root);
        orgB.setPoliciesRoot(root);

        ValidationProofs memory proofs = _emptyProofsForPolicy(policy);
        bytes memory data = abi.encodeWithSelector(bytes4(0x27272727), uint256(27));
        uint256 expiration = block.timestamp + 1 days;

        bytes memory initiatorSignatureOrgA = _signInitiatorTx({
            txHarness: harness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 27,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAccountTransaction.PolicyDoesNotApply.selector, DEFAULT_POLICY_ID)
        );
        orgB.validateTransactionApprovalOrRevertViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 27,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignatureOrgA,
            reviewSignatures: bytes(""),
            proofs: proofs
        });
    }

    /// @dev Verifies that cross organization replay reviewer signatures fail with valid org b initiator.
    function test_LOAT_28_crossOrganizationReplayReviewerSignaturesFailWithValidOrgBInitiator() public {
        // Setup: assemble inputs expected to hit the guarded failure path for cross organization replay reviewer signatures fail with valid org b initiator.
        LibOrganizationAccountTransactionHarness orgB = new LibOrganizationAccountTransactionHarness();

        // Seed shared org state.
        _seedMembers(address(orgB));

        Policy memory policy =
            _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.RequireManualApproval});
        bytes32 root = _computePolicyLeaf(DEFAULT_POLICY_ID, policy);
        policyStateHarness.setPoliciesRoot(root);
        orgB.setPoliciesRoot(root);

        ValidationProofs memory proofs = _emptyProofsForPolicy(policy);
        bytes memory data = abi.encodeWithSelector(bytes4(0x28282828), uint256(28));
        uint256 expiration = block.timestamp + 1 days;

        bytes memory initiatorSignatureOrgB = _signInitiatorTx({
            txHarness: orgB,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 28,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        bytes memory reviewerSignatureOrgA = _signReviewTx({
            txHarness: harness,
            privateKey: REVIEWER_PK_1,
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 28,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true,
            initiatorSignature: initiatorSignatureOrgB
        });

        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert();
        orgB.validateTransactionApprovalOrRevertViaLibrary({
            account: ACCOUNT,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 28,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignatureOrgB,
            reviewSignatures: reviewerSignatureOrgA,
            proofs: proofs
        });
    }

    // Helpers

    function _buildApprovalPolicy(TransactionType txType, PolicyType approvalType)
        internal
        view
        returns (Policy memory policy)
    {
        policy = _buildBasePolicy();
        policy.config.transactionType = txType;
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

    // solhint-disable-next-line func-name-mixedcase
    function _signInitiatorTx(
        LibOrganizationAccountTransactionHarness txHarness,
        uint256 privateKey,
        address account,
        address to,
        uint256 value,
        bytes memory data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bool isApproval
    ) internal view returns (bytes memory) {
        bytes32 hash = txHarness.computeInitiatorHashFromParamsViaLibrary({
            account: account,
            to: to,
            value: value,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            policyId: policyId,
            data: data,
            isApproval: isApproval
        });
        return _signHash(privateKey, hash);
    }

    // solhint-disable-next-line func-name-mixedcase
    function _signReviewTx(
        LibOrganizationAccountTransactionHarness txHarness,
        uint256 privateKey,
        address account,
        address to,
        uint256 value,
        bytes memory data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bool isApproval,
        bytes memory initiatorSignature
    ) internal view returns (bytes memory) {
        bytes32 hash = txHarness.computeReviewHashFromParamsViaLibrary({
            account: account,
            to: to,
            value: value,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            policyId: policyId,
            data: data,
            isApproval: isApproval,
            initiatorSignature: initiatorSignature
        });
        return _signHash(privateKey, hash);
    }

    function _computeTimeWindow(Policy memory policy) internal view returns (uint256) {
        if (policy.config.rateLimit.timeIntervalHours == 0) {
            return 0;
        }
        return block.timestamp / (uint256(policy.config.rateLimit.timeIntervalHours) * 3600);
    }

    function _computeUsageKey(
        uint256 policyId,
        Policy memory policy,
        address account,
        address destination,
        address initiator
    ) internal pure returns (bytes32) {
        address scopedAccount = policy.config.rateLimit.sourceScope == RateLimitScope.PerEntity ? account : address(0);
        address scopedDestination =
            policy.config.rateLimit.destinationScope == RateLimitScope.PerEntity ? destination : address(0);
        address scopedInitiator =
            policy.config.rateLimit.initiatorScope == RateLimitScope.PerEntity ? initiator : address(0);

        return keccak256(abi.encode(policyId, scopedAccount, scopedDestination, scopedInitiator));
    }

    function _unsafeSetApprovalPolicyTypeRaw(Policy memory policy, uint256 rawValue) internal pure {
        // `Policy.config.approval.policyType` is at offset 0x80 in the in-memory `Policy` struct.
        assembly {
            mstore(add(policy, 0x80), rawValue)
        }
    }

    function _unsafeSetRateLimitTypeRaw(Policy memory policy, uint256 rawValue) internal pure {
        // `Policy.config.rateLimit.limitType` is at offset 0x220 in the in-memory `Policy` struct.
        assembly {
            mstore(add(policy, 0x220), rawValue)
        }
    }

    function _seedMembers(address target) internal {
        LibOrganizationAccountTransactionHarness targetHarness = LibOrganizationAccountTransactionHarness(target);
        targetHarness.setMemberStatus(initiator1, true);
        targetHarness.setMemberStatus(initiator2, true);
        targetHarness.setMemberStatus(reviewer1, true);
        targetHarness.setMemberStatus(reviewer2, true);
    }
}
