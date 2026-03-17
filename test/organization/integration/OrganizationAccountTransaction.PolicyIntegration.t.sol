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
contract OrganizationAccountTransactionPolicyIntegrationTest is LibOrganizationAccountTransactionSuiteBase {
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
    function test_LOAT_VTAOR_8_policyDoesNotApply_revertsPolicyDoesNotApply() public {
        // Setup: assemble inputs expected to hit the guarded failure path for policy does not apply reverts policy does
        // not apply.
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
        // Call: invoke `validateTransactionApprovalOrRevertViaLibrary` with the failing payload to exercise the revert
        // branch.
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
    function test_LOAT_AVTAOR_5_policyProofTampering_revertsPolicyDoesNotApply() public {
        // Setup: assemble inputs expected to hit the guarded failure path for policy proof tampering reverts policy
        // does not apply.
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
        // Call: invoke `validateTransactionApprovalOrRevertViaLibrary` with the failing payload to exercise the revert
        // branch.
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
    function test_LOAT_VTAOR_9__POL_INV_4_signaturePolicyCannotAuthorizeAccountTransactions() public {
        // Setup: assemble inputs expected to hit the guarded failure path for signature policy cannot authorize account
        // transactions.
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
        // Call: invoke `validateTransactionApprovalOrRevertViaLibrary` with the failing payload to exercise the revert
        // branch.
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
    function test_LOAT_AVTAOR_9_manualApprovalWithoutReviewers_revertsInsufficientApprovals() public {
        // Setup: assemble inputs expected to hit the guarded failure path for manual approval without reviewers reverts
        // insufficient approvals.
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
        // Call: invoke `validateTransactionApprovalOrRevertViaLibrary` with the failing payload to exercise the revert
        // branch.
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
    function test_manualApprovalWithValidThreshold_succeeds() public {
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
    function test_autoApproveIgnoresReviewerSignatures() public {
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
    function test_rateLimitExceeded_revertsRateLimitExceeded() public {
        // Setup: assemble inputs expected to hit the guarded failure path for rate limit exceeded reverts rate limit
        // exceeded.
        Policy memory policy =
            _buildApprovalPolicy({txType: TransactionType.TokenTransfers, approvalType: PolicyType.AutoApprove});
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = 100;

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        bytes memory data = _encodeERC20Transfer(RECIPIENT, 101);
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signDefaultInitiatorTx(harness, TOKEN, data, 7, expiration, true);

        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAccountTransaction.RateLimitExceeded.selector, DEFAULT_POLICY_ID)
        );
        // Call: invoke `validateTransactionApprovalOrRevertViaLibrary` with the failing payload to exercise the revert
        // branch.
        _validateApproval(harness, TOKEN, data, 7, expiration, initiatorSignature, bytes(""), proofs);
    }

    /// @dev Verifies that token transfer rate limit usage tracks transfer amount.
    function test_TXRL_INV_5_tokenTransferRateLimitUsageTracksTransferAmount() public {
        // Setup: configure a valid fixture for token transfer rate limit usage tracks transfer amount.
        Policy memory policy =
            _buildApprovalPolicy({txType: TransactionType.TokenTransfers, approvalType: PolicyType.AutoApprove});
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = 1000;

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        bytes memory data = _encodeERC20Transfer(RECIPIENT, 42);
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signDefaultInitiatorTx(harness, TOKEN, data, 8, expiration, true);

        // Call: execute `validateTransactionApprovalOrRevertViaLibrary` with the happy-path payload.
        _validateApproval(harness, TOKEN, data, 8, expiration, initiatorSignature, bytes(""), proofs);

        bytes32 usageKey = _computeUsageKey(DEFAULT_POLICY_ID, policy, ACCOUNT, RECIPIENT, initiator1);
        uint256 window = _computeTimeWindow(policy);
        // Verify: assert the expected success result and state updates.
        assertEq(policyStateHarness.getPolicyUsage(usageKey, window), 42, "usage should equal transfer amount");
    }

    /// @dev Verifies that non token rate limit usage increments by one.
    function test_TXRL_INV_5_nonTokenRateLimitUsageIncrementsByOne() public {
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
    function test_TXRL_INV_11_rateLimitKeyUsesERC20RecipientAsDestination() public {
        // Setup: configure a valid fixture for rate limit key uses erc20 recipient as destination.
        Policy memory policy =
            _buildApprovalPolicy({txType: TransactionType.TokenTransfers, approvalType: PolicyType.AutoApprove});
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = 1000;
        policy.config.rateLimit.destinationScope = RateLimitScope.PerEntity;

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        bytes memory data = _encodeERC20Transfer(RECIPIENT, 11);
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signDefaultInitiatorTx(harness, TOKEN, data, 10, expiration, true);

        // Call: execute `validateTransactionApprovalOrRevertViaLibrary` with the happy-path payload.
        _validateApproval(harness, TOKEN, data, 10, expiration, initiatorSignature, bytes(""), proofs);

        bytes32 recipientKey = _computeUsageKey(DEFAULT_POLICY_ID, policy, ACCOUNT, RECIPIENT, initiator1);
        bytes32 tokenKey = _computeUsageKey(DEFAULT_POLICY_ID, policy, ACCOUNT, TOKEN, initiator1);
        uint256 window = _computeTimeWindow(policy);

        // Verify: assert the expected success result and state updates.
        assertEq(policyStateHarness.getPolicyUsage(recipientKey, window), 11, "recipient key should be charged");
        assertEq(policyStateHarness.getPolicyUsage(tokenKey, window), 0, "token-contract key should remain untouched");
    }

    /// @dev Verifies that auto reject requires authorized initiator signature.
    function test_LOAT_VAAROR_4__OAT_RAT_1_autoRejectRequiresAuthorizedInitiatorSignature() public {
        // Setup: assemble inputs expected to hit the guarded failure path for auto reject requires authorized initiator
        // signature.
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
        // Call: invoke `validateTransactionRejectionOrRevertViaLibrary` with the failing payload to exercise the revert
        // branch.
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
    function test_OAT_RAT_2_manualRejectWithoutThresholdApprovals_revertsInsufficientApprovals() public {
        // Setup: assemble inputs expected to hit the guarded failure path for manual reject without threshold approvals
        // reverts insufficient approvals.
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
        // Call: invoke `validateTransactionRejectionOrRevertViaLibrary` with the failing payload to exercise the revert
        // branch.
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
    function test_LOAT_VAAROR_7_approvalReviewSignaturesCannotReplayAsRejection() public {
        // Setup: assemble inputs expected to hit the guarded failure path for approval review signatures cannot replay
        // as rejection.
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
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.InsufficientApprovals.selector, 1, 0));
        // Call: invoke `validateTransactionRejectionOrRevertViaLibrary` with the failing payload to exercise the revert
        // branch.
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
    function test_LOAT_CIHFP_5__LOAT_CIHFP_6__LOAT_CIHFP_7__LOAT_CIHFP_8__LOAT_CIHFP_9__LOAT_CIHFP_10__OAT_PH_1_hashBuildersAreDeterministicAndFieldBound()
        public
    {
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

        _assertInitiatorHashFieldBindings(baseInitiatorHashA, data, expiration);
        _assertInitiatorHashChainBinding(baseInitiatorHashA, data, expiration);
        _assertReviewHashBindings(baseInitiatorHashA, data, expiration);
    }

    /// @dev Verifies that desired any policy token transfers use count based rate usage.
    function test_desired_anyPolicyTokenTransfersUseCountBasedRateUsage() public {
        // Setup: configure a valid fixture for desired any policy token transfers use count based rate usage.
        Policy memory policy = _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.AutoApprove});
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = 1000;

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        bytes memory data = _encodeERC20Transfer(RECIPIENT, 500);
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signDefaultInitiatorTx(harness, TOKEN, data, 15, expiration, true);

        // Call: execute `validateTransactionApprovalOrRevertViaLibrary` with the happy-path payload.
        _validateApproval(harness, TOKEN, data, 15, expiration, initiatorSignature, bytes(""), proofs);

        bytes32 usageKey = _computeUsageKey(DEFAULT_POLICY_ID, policy, ACCOUNT, RECIPIENT, initiator1);
        uint256 window = _computeTimeWindow(policy);
        // Verify: assert the expected success result and state updates.
        assertEq(policyStateHarness.getPolicyUsage(usageKey, window), 1, "usage should be count-based for txType Any");
    }

    /// @dev Verifies that any-policy token transfer cannot bypass rate limit and exceeded call keeps usage unchanged.
    function test_anyPolicyTokenTransferCannotBypassRateLimitAndExceededCallKeepsUsageUnchanged() public {
        // Setup: configure a one-per-window Any policy and use a zero-amount transfer that would bypass if usage were
        // token-amount-based.
        ValidationProofs memory proofs;
        bytes32 usageKey;
        uint256 window;
        {
            Policy memory policy =
                _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.AutoApprove});
            policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
            policy.config.rateLimit.timeIntervalHours = 1;
            policy.config.rateLimit.timeIntervalLimit = 1;
            policy.config.rateLimit.destinationScope = RateLimitScope.PerEntity;
            policy.config.rateLimit.sourceScope = RateLimitScope.PerEntity;
            policy.config.rateLimit.initiatorScope = RateLimitScope.PerEntity;

            proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
            usageKey = _computeUsageKey(DEFAULT_POLICY_ID, policy, ACCOUNT, RECIPIENT, initiator1);
            window = _computeTimeWindow(policy);
        }

        // Call: execute a first successful transfer, then attempt a second transfer in the same window.
        {
            bytes memory data = _encodeERC20Transfer(RECIPIENT, 0);
            uint256 expiration = block.timestamp + 1 days;
            bytes memory firstInitiatorSignature =
                _signDefaultInitiatorTx(harness, TOKEN, data, 29, expiration, true);
            _validateApproval(
                harness, TOKEN, data, 29, expiration, firstInitiatorSignature, bytes(""), proofs
            );
        }

        // Verify: first call consumes exactly one unit under Any transaction type.
        assertEq(policyStateHarness.getPolicyUsage(usageKey, window), 1, "first Any token transfer should consume one");

        {
            bytes memory data = _encodeERC20Transfer(RECIPIENT, 0);
            uint256 expiration = block.timestamp + 1 days;
            bytes memory secondInitiatorSignature =
                _signDefaultInitiatorTx(harness, TOKEN, data, 30, expiration, true);

            vm.expectRevert(
                abi.encodeWithSelector(IOrganizationAccountTransaction.RateLimitExceeded.selector, DEFAULT_POLICY_ID)
            );
            _validateApproval(
                harness, TOKEN, data, 30, expiration, secondInitiatorSignature, bytes(""), proofs
            );
        }

        // Verify: exceeded call does not mutate stored usage.
        assertEq(policyStateHarness.getPolicyUsage(usageKey, window), 1, "exceeded transfer must not mutate usage");
    }

    /// @dev Verifies that any-policy contract interaction cannot bypass rate limit and exceeded call keeps usage
    /// unchanged.
    function test_anyPolicyContractInteractionCannotBypassRateLimitAndExceededCallKeepsUsageUnchanged() public {
        // Setup: configure a one-per-window Any policy for non-token calls where usage should stay count-based.
        ValidationProofs memory proofs;
        bytes32 usageKey;
        uint256 window;
        {
            Policy memory policy =
                _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.AutoApprove});
            policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
            policy.config.rateLimit.timeIntervalHours = 1;
            policy.config.rateLimit.timeIntervalLimit = 1;
            policy.config.rateLimit.destinationScope = RateLimitScope.PerEntity;
            policy.config.rateLimit.sourceScope = RateLimitScope.PerEntity;
            policy.config.rateLimit.initiatorScope = RateLimitScope.PerEntity;

            proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
            usageKey = _computeUsageKey(DEFAULT_POLICY_ID, policy, ACCOUNT, DESTINATION, initiator1);
            window = _computeTimeWindow(policy);
        }

        // Call: execute a first successful interaction, then attempt a second interaction in the same window.
        {
            bytes memory data = abi.encodeWithSelector(bytes4(0x31313131), uint256(31));
            uint256 expiration = block.timestamp + 1 days;
            bytes memory firstInitiatorSignature =
                _signDefaultInitiatorTx(harness, DESTINATION, data, 31, expiration, true);
            _validateApproval(
                harness, DESTINATION, data, 31, expiration, firstInitiatorSignature, bytes(""), proofs
            );
        }

        // Verify: first call consumes one usage unit.
        assertEq(policyStateHarness.getPolicyUsage(usageKey, window), 1, "first Any contract call should consume one");

        {
            bytes memory data = abi.encodeWithSelector(bytes4(0x31313131), uint256(31));
            uint256 expiration = block.timestamp + 1 days;
            bytes memory secondInitiatorSignature =
                _signDefaultInitiatorTx(harness, DESTINATION, data, 32, expiration, true);

            vm.expectRevert(
                abi.encodeWithSelector(IOrganizationAccountTransaction.RateLimitExceeded.selector, DEFAULT_POLICY_ID)
            );
            _validateApproval(
                harness, DESTINATION, data, 32, expiration, secondInitiatorSignature, bytes(""), proofs
            );
        }

        // Verify: exceeded call does not mutate stored usage.
        assertEq(policyStateHarness.getPolicyUsage(usageKey, window), 1, "exceeded interaction must not mutate usage");
    }

    /// @dev Verifies that policy does not apply does not mutate rate usage.
    function test_LOAT_AVTAOR_10_A_policyDoesNotApply_doesNotMutateRateUsage() public {
        // Setup: assemble inputs expected to hit the guarded failure path for policy does not apply does not mutate
        // rate usage.
        ValidationProofs memory proofs;
        bytes32 usageKey;
        uint256 window;
        {
            Policy memory policy =
                _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.AutoApprove});
            policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
            policy.config.rateLimit.timeIntervalHours = 1;
            policy.config.rateLimit.timeIntervalLimit = 1000;
            policy.config.rateLimit.destinationScope = RateLimitScope.PerEntity;
            policy.config.rateLimit.sourceScope = RateLimitScope.PerEntity;
            policy.config.rateLimit.initiatorScope = RateLimitScope.PerEntity;

            // Intentionally keep root unset and use empty proof => PolicyDoesNotApply before rate-limit update.
            proofs = _emptyProofsForPolicy(policy);
            usageKey = _computeUsageKey(DEFAULT_POLICY_ID, policy, ACCOUNT, DESTINATION, initiator1);
            window = _computeTimeWindow(policy);
        }
        policyStateHarness.setPolicyUsage(usageKey, window, 9);

        {
            bytes memory data = abi.encodeWithSelector(bytes4(0x16161616), uint256(16));
            uint256 expiration = block.timestamp + 1 days;
            bytes memory initiatorSignature =
                _signDefaultInitiatorTx(harness, DESTINATION, data, 16, expiration, true);

            // Verify: assert that the revert reason matches the policy guard under test.
            vm.expectRevert(
                abi.encodeWithSelector(IOrganizationAccountTransaction.PolicyDoesNotApply.selector, DEFAULT_POLICY_ID)
            );
            // Call: invoke `validateTransactionApprovalOrRevertViaLibrary` with the failing payload to exercise the revert
            // branch.
            _validateApproval(harness, DESTINATION, data, 16, expiration, initiatorSignature, bytes(""), proofs);
        }

        assertEq(
            policyStateHarness.getPolicyUsage(usageKey, window), 9, "usage must remain unchanged on pre-check failure"
        );
    }

    /// @dev Verifies that insufficient approvals does not mutate rate usage.
    function test_LOAT_AVTAOR_10_B_insufficientApprovals_doesNotMutateRateUsage() public {
        // Setup: assemble inputs expected to hit the guarded failure path for insufficient approvals does not mutate
        // rate usage.
        ValidationProofs memory proofs;
        bytes32 usageKey;
        uint256 window;
        {
            Policy memory policy =
                _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.RequireManualApproval});
            policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
            policy.config.rateLimit.timeIntervalHours = 1;
            policy.config.rateLimit.timeIntervalLimit = 1000;
            policy.config.rateLimit.destinationScope = RateLimitScope.PerEntity;
            policy.config.rateLimit.sourceScope = RateLimitScope.PerEntity;
            policy.config.rateLimit.initiatorScope = RateLimitScope.PerEntity;

            proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
            usageKey = _computeUsageKey(DEFAULT_POLICY_ID, policy, ACCOUNT, DESTINATION, initiator1);
            window = _computeTimeWindow(policy);
        }
        policyStateHarness.setPolicyUsage(usageKey, window, 7);

        {
            bytes memory data = abi.encodeWithSelector(bytes4(0x17171717), uint256(17));
            uint256 expiration = block.timestamp + 1 days;
            bytes memory initiatorSignature =
                _signDefaultInitiatorTx(harness, DESTINATION, data, 17, expiration, true);

            // Verify: assert that the revert reason matches the policy guard under test.
            vm.expectRevert(
                abi.encodeWithSelector(IOrganizationAccountTransaction.InsufficientApprovals.selector, 1, 0)
            );
            // Call: invoke `validateTransactionApprovalOrRevertViaLibrary` with the failing payload to exercise the revert
            // branch.
            _validateApproval(harness, DESTINATION, data, 17, expiration, initiatorSignature, bytes(""), proofs);
        }

        assertEq(
            policyStateHarness.getPolicyUsage(usageKey, window),
            7,
            "usage must remain unchanged on manual-check failure"
        );
    }

    /// @dev Verifies that root transition guard clear root rejects old proofs.
    function test_rootTransitionGuard_clearRootRejectsOldProofs() public {
        // Setup: assemble inputs expected to hit the guarded failure path for root transition guard clear root rejects
        // old proofs.
        ValidationProofs memory proofs;
        {
            Policy memory policy =
                _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.AutoApprove});
            proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        }

        // Under R1: succeeds.
        {
            bytes memory data = abi.encodeWithSelector(bytes4(0x18181818), uint256(18));
            uint256 expiration = block.timestamp + 1 days;
            bytes memory initiatorSignature =
                _signDefaultInitiatorTx(harness, DESTINATION, data, 18, expiration, true);
            // Call: invoke `validateTransactionApprovalOrRevertViaLibrary` with the failing payload to exercise the revert
            // branch.
            _validateApproval(harness, DESTINATION, data, 18, expiration, initiatorSignature, bytes(""), proofs);
        }

        // Clear root.
        policyStateHarness.setPoliciesRoot(bytes32(0));

        // Verify: assert that the revert reason matches the policy guard under test.
        {
            bytes memory data = abi.encodeWithSelector(bytes4(0x18181818), uint256(18));
            uint256 expiration = block.timestamp + 1 days;
            bytes memory initiatorSignature =
                _signDefaultInitiatorTx(harness, DESTINATION, data, 18, expiration, true);
            vm.expectRevert(
                abi.encodeWithSelector(IOrganizationAccountTransaction.PolicyDoesNotApply.selector, DEFAULT_POLICY_ID)
            );
            _validateApproval(harness, DESTINATION, data, 18, expiration, initiatorSignature, bytes(""), proofs);
        }
    }

    /// @dev Verifies that branch comparison auto approve succeeds manual without reviews reverts.
    function test_branchComparison_autoApproveSucceeds_manualWithoutReviewsReverts() public {
        // Setup: assemble inputs expected to hit the guarded failure path for branch comparison auto approve succeeds
        // manual without reviews reverts.
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

        {
            Policy memory autoPolicy =
                _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.AutoApprove});
            ValidationProofs memory autoProofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, autoPolicy);

            // Call: invoke `validateTransactionApprovalOrRevertViaLibrary` with the failing payload to exercise the revert
            // branch.
            _validateApproval(
                harness, DESTINATION, data, 19, expiration, initiatorSignature, bytes(""), autoProofs
            );
        }

        {
            Policy memory manualPolicy =
                _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.RequireManualApproval});
            ValidationProofs memory manualProofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, manualPolicy);

            // Verify: assert that the revert reason matches the policy guard under test.
            vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.InsufficientApprovals.selector, 1, 0));
            _validateApproval(
                harness, DESTINATION, data, 19, expiration, initiatorSignature, bytes(""), manualProofs
            );
        }
    }

    /// @dev Verifies that invalid approval policy type in proofs payload reverts.
    function test_invalidApprovalPolicyType_reverts() public {
        // Setup: assemble valid approval payload then mutate encoded proofs with an invalid enum value.
        bool success;
        {
            Policy memory policy =
                _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.AutoApprove});
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

            bytes memory callData = abi.encodeCall(
                harness.validateTransactionApprovalOrRevertViaLibrary,
                (ACCOUNT, DESTINATION, 0, data, 20, expiration, DEFAULT_POLICY_ID, initiatorSignature, bytes(""), proofs)
            );
            _setPolicyTypeInValidateApprovalCalldata(callData, 2);

            // Call: execute a low-level call with malformed enum calldata.
            (success,) = address(harness).call(callData);
        }
        // Verify: assert malformed enum values fail with a revert/panic.
        assertFalse(success, "invalid approval policy type should revert");
    }

    /// @dev Verifies that branch comparison manual with reviews and auto with same payload both succeed.
    function test_branchComparison_manualWithReviewsAndAutoWithSamePayloadBothSucceed() public {
        // Setup: configure a valid fixture for branch comparison manual with reviews and auto with same payload both
        // succeed.
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

        {
            Policy memory manualPolicy =
                _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.RequireManualApproval});
            ValidationProofs memory manualProofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, manualPolicy);

            // Call: execute `validateTransactionApprovalOrRevertViaLibrary` with the happy-path payload.
            _validateApproval(
                harness, DESTINATION, data, 21, expiration, initiatorSignature, reviewSignature, manualProofs
            );
        }

        {
            Policy memory autoPolicy =
                _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.AutoApprove});
            ValidationProofs memory autoProofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, autoPolicy);

            _validateApproval(
                harness, DESTINATION, data, 21, expiration, initiatorSignature, reviewSignature, autoProofs
            );
        }
    }

    /// @dev Verifies that rejection branch comparison auto succeeds manual insufficient for same payload.
    function test_rejectionBranchComparison_autoSucceeds_manualInsufficientForSamePayload() public {
        // Setup: assemble inputs expected to hit the guarded failure path for rejection branch comparison auto succeeds
        // manual insufficient for same payload.
        // Manual policy: group threshold=2. One valid signer should yield InsufficientApprovals.
        policyStateHarness.setGroupStatus(922, true);
        policyStateHarness.setGroupMemberStatus(922, initiator1, true);

        {
            bytes memory data = abi.encodeWithSelector(bytes4(0x22222222), uint256(22));
            uint256 expiration = block.timestamp + 1 days;
            bytes memory initiatorSignature =
                _signDefaultInitiatorTx(harness, DESTINATION, data, 22, expiration, true);
            bytes memory rejectionByInitiator =
                _signDefaultInitiatorTx(harness, DESTINATION, data, 22, expiration, false);
            Policy memory autoPolicy =
                _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.AutoApprove});
            autoPolicy.config.approval.approverType = ApproverType.Group;
            autoPolicy.config.approval.approverGroupId = 922;
            autoPolicy.config.approval.approvalThreshold = 2;

            ValidationProofs memory autoProofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, autoPolicy);
            // Call: invoke `validateTransactionRejectionOrRevertViaLibrary` with the failing payload to exercise the revert
            // branch.
            _validateRejection(
                harness, DESTINATION, data, 22, expiration, initiatorSignature, rejectionByInitiator, autoProofs
            );
        }

        {
            bytes memory data = abi.encodeWithSelector(bytes4(0x22222222), uint256(22));
            uint256 expiration = block.timestamp + 1 days;
            bytes memory initiatorSignature =
                _signDefaultInitiatorTx(harness, DESTINATION, data, 22, expiration, true);
            bytes memory rejectionByInitiator =
                _signDefaultInitiatorTx(harness, DESTINATION, data, 22, expiration, false);
            Policy memory manualPolicy =
                _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.RequireManualApproval});
            manualPolicy.config.approval.approverType = ApproverType.Group;
            manualPolicy.config.approval.approverGroupId = 922;
            manualPolicy.config.approval.approvalThreshold = 2;

            ValidationProofs memory manualProofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, manualPolicy);
            // Verify: assert that the revert reason matches the policy guard under test.
            vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.InsufficientApprovals.selector, 2, 0));
            _validateRejection(
                harness, DESTINATION, data, 22, expiration, initiatorSignature, rejectionByInitiator, manualProofs
            );
        }
    }

    /// @dev Verifies that rejection branch comparison manual succeeds auto rejects same reviewer payload.
    function test_rejectionBranchComparison_manualSucceeds_autoRejectsSameReviewerPayload() public {
        // Setup: assemble inputs expected to hit the guarded failure path for rejection branch comparison manual
        // succeeds auto rejects same reviewer payload.
        {
            bytes memory data = abi.encodeWithSelector(bytes4(0x23232323), uint256(23));
            uint256 expiration = block.timestamp + 1 days;
            bytes memory initiatorSignature =
                _signDefaultInitiatorTx(harness, DESTINATION, data, 23, expiration, true);
            bytes memory reviewerRejectionSignature =
                _signDefaultReviewTx(harness, REVIEWER_PK_1, DESTINATION, data, 23, expiration, false, initiatorSignature);
            Policy memory manualPolicy =
                _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.RequireManualApproval});
            ValidationProofs memory manualProofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, manualPolicy);
            // Call: invoke `validateTransactionRejectionOrRevertViaLibrary` with the failing payload to exercise the revert
            // branch.
            _validateRejection(
                harness, DESTINATION, data, 23, expiration, initiatorSignature, reviewerRejectionSignature, manualProofs
            );
        }

        {
            bytes memory data = abi.encodeWithSelector(bytes4(0x23232323), uint256(23));
            uint256 expiration = block.timestamp + 1 days;
            bytes memory initiatorSignature =
                _signDefaultInitiatorTx(harness, DESTINATION, data, 23, expiration, true);
            bytes memory reviewerRejectionSignature =
                _signDefaultReviewTx(harness, REVIEWER_PK_1, DESTINATION, data, 23, expiration, false, initiatorSignature);
            Policy memory autoPolicy =
                _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.RequireManualApproval});
            autoPolicy.config.approval.policyType = PolicyType.AutoApprove;
            ValidationProofs memory autoProofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, autoPolicy);

            // Verify: assert that the revert reason matches the policy guard under test.
            vm.expectRevert(IOrganizationAccountTransaction.TransactionRejectionNotAllowed.selector);
            _validateRejection(
                harness, DESTINATION, data, 23, expiration, initiatorSignature, reviewerRejectionSignature, autoProofs
            );
        }
    }

    /// @dev Verifies that cross chain replay initiator signature fails.
    function test_crossChainReplayInitiatorSignatureFails() public {
        // Setup: assemble inputs expected to hit the guarded failure path for cross chain replay initiator signature
        // fails.
        Policy memory policy = _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.AutoApprove});
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        bytes memory data = abi.encodeWithSelector(bytes4(0x24242424), uint256(24));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignatureChainA;

        {
            vm.chainId(1);
            initiatorSignatureChainA = _signInitiatorTx({
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
        }

        vm.chainId(31_337);
        // Verify: assert that the revert reason matches the policy guard under test.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAccountTransaction.PolicyDoesNotApply.selector, DEFAULT_POLICY_ID)
        );
        // Call: invoke `validateTransactionApprovalOrRevertViaLibrary` with the failing payload to exercise the revert
        // branch.
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
    function test_crossChainReplayReviewerSignaturesFailWithValidChainBInitiator() public {
        // Setup: assemble inputs expected to hit the guarded failure path for cross chain replay reviewer signatures
        // fail with valid chain b initiator.
        ValidationProofs memory proofs;
        {
            Policy memory policy =
                _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.RequireManualApproval});
            proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        }

        {
            bytes memory data = abi.encodeWithSelector(bytes4(0x25252525), uint256(25));
            uint256 expiration = block.timestamp + 1 days;
            vm.chainId(31_337);
            bytes memory initiatorSignatureChainB =
                _signDefaultInitiatorTx(harness, DESTINATION, data, 25, expiration, true);
            vm.chainId(1);
            bytes memory reviewerSignatureChainA =
                _signDefaultReviewTx(harness, REVIEWER_PK_1, DESTINATION, data, 25, expiration, true, initiatorSignatureChainB);

            vm.chainId(31_337);
            // Verify: assert that the revert reason matches the policy guard under test.
            vm.expectRevert(
                abi.encodeWithSelector(IOrganizationAccountTransaction.InsufficientApprovals.selector, 1, 0)
            );
            // Call: invoke `validateTransactionApprovalOrRevertViaLibrary` with the failing payload to exercise the revert
            // branch.
            _validateApproval(
                harness, DESTINATION, data, 25, expiration, initiatorSignatureChainB, reviewerSignatureChainA, proofs
            );
        }
    }

    /// @dev Verifies that invalid rate-limit type in proofs payload reverts.
    function test_invalidRateLimitType_reverts() public {
        // Setup: assemble valid approval payload then mutate encoded proofs with an invalid enum value.
        bool success;
        {
            Policy memory policy =
                _buildApprovalPolicy({txType: TransactionType.TokenTransfers, approvalType: PolicyType.AutoApprove});
            policy.config.rateLimit.timeIntervalHours = 1;
            policy.config.rateLimit.timeIntervalLimit = 1;
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

            bytes memory callData = abi.encodeCall(
                harness.validateTransactionApprovalOrRevertViaLibrary,
                (ACCOUNT, TOKEN, 0, data, 26, expiration, DEFAULT_POLICY_ID, initiatorSignature, bytes(""), proofs)
            );
            _setRateLimitTypeInValidateApprovalCalldata(callData, 2);

            // Call: execute a low-level call with malformed enum calldata.
            (success,) = address(harness).call(callData);
        }
        // Verify: assert malformed enum values fail with a revert/panic.
        assertFalse(success, "invalid rate-limit type should revert");
    }

    /// @dev Verifies that cross organization replay initiator signature fails.
    function test_OAT_RAT_1__INT_ETE_3_crossOrganizationReplayInitiatorSignatureFails() public {
        // Setup: assemble inputs expected to hit the guarded failure path for cross organization replay initiator
        // signature fails.
        LibOrganizationAccountTransactionHarness orgB = new LibOrganizationAccountTransactionHarness();
        ValidationProofs memory proofs;
        bytes memory data;
        uint256 expiration;
        bytes memory initiatorSignatureOrgA;

        // Seed shared org state.
        _seedMembers(address(orgB));
        {
            Policy memory policy =
                _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.AutoApprove});
            bytes32 root = _computePolicyLeaf(DEFAULT_POLICY_ID, policy);
            policyStateHarness.setPoliciesRoot(root);
            orgB.setPoliciesRoot(root);

            proofs = _emptyProofsForPolicy(policy);
            data = abi.encodeWithSelector(bytes4(0x27272727), uint256(27));
            expiration = block.timestamp + 1 days;

            initiatorSignatureOrgA = _signInitiatorTx({
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
        }

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
    function test_LOAT_CRHFP_1__INT_ETE_3_crossOrganizationReplayReviewerSignaturesFailWithValidOrgBInitiator()
        public
    {
        // Setup: assemble inputs expected to hit the guarded failure path for cross organization replay reviewer
        // signatures fail with valid org b initiator.
        LibOrganizationAccountTransactionHarness orgB = new LibOrganizationAccountTransactionHarness();
        ValidationProofs memory proofs;

        _seedMembers(address(orgB));
        {
            Policy memory policy =
                _buildApprovalPolicy({txType: TransactionType.Any, approvalType: PolicyType.RequireManualApproval});
            bytes32 root = _computePolicyLeaf(DEFAULT_POLICY_ID, policy);
            policyStateHarness.setPoliciesRoot(root);
            orgB.setPoliciesRoot(root);

            proofs = _emptyProofsForPolicy(policy);
        }

        // Call: validate with an org B review signature to prove the happy path succeeds.
        {
            bytes memory data = abi.encodeWithSelector(bytes4(0x28282828), uint256(28));
            uint256 expiration = block.timestamp + 1 days;
            bytes memory initiatorSignatureOrgB =
                _signDefaultInitiatorTx(orgB, DESTINATION, data, 28, expiration, true);
            bytes memory reviewerSignatureOrgB =
                _signDefaultReviewTx(orgB, REVIEWER_PK_1, DESTINATION, data, 28, expiration, true, initiatorSignatureOrgB);

            _validateApproval(
                orgB, DESTINATION, data, 28, expiration, initiatorSignatureOrgB, reviewerSignatureOrgB, proofs
            );
        }

        // Verify: the same reviewer key signed against org A produces an invalid review hash on org B,
        // isolating the different organization as the sole reason for failure.
        {
            bytes memory data = abi.encodeWithSelector(bytes4(0x28282828), uint256(28));
            uint256 expiration = block.timestamp + 1 days;
            bytes memory initiatorSignatureOrgB =
                _signDefaultInitiatorTx(orgB, DESTINATION, data, 28, expiration, true);
            bytes memory reviewerSignatureOrgA =
                _signDefaultReviewTx(harness, REVIEWER_PK_1, DESTINATION, data, 28, expiration, true, initiatorSignatureOrgB);

            vm.expectRevert(
                abi.encodeWithSelector(IOrganizationAccountTransaction.InsufficientApprovals.selector, 1, 0)
            );
            _validateApproval(
                orgB, DESTINATION, data, 28, expiration, initiatorSignatureOrgB, reviewerSignatureOrgA, proofs
            );
        }
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

    /// @dev Verifies that a rate limit with a future anchor reverts with RateLimitExceeded.
    function test_rateLimitWithAnchor_exceedsBeforeAnchor_reverts() public {
        // Setup: anchor is in the future relative to block.timestamp.
        Policy memory policy =
            _buildApprovalPolicy({txType: TransactionType.TokenTransfers, approvalType: PolicyType.AutoApprove});
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = 1000;
        policy.config.rateLimit.anchorTimestamp = block.timestamp + 1 days;

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        bytes memory data = _encodeERC20Transfer(RECIPIENT, 10);
        uint256 expiration = block.timestamp + 2 days;
        bytes memory initiatorSignature = _signDefaultInitiatorTx(harness, TOKEN, data, 2001, expiration, true);

        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAccountTransaction.RateLimitExceeded.selector, DEFAULT_POLICY_ID)
        );
        _validateApproval(harness, TOKEN, data, 2001, expiration, initiatorSignature, bytes(""), proofs);
    }

    /// @dev Verifies that token transfer usage tracks correctly with a non-zero anchor.
    function test_rateLimitWithAnchor_tokenTransfer_tracksUsageCorrectly() public {
        // Setup: anchor=500000, warp to 501000, interval=1h, limit=1000.
        vm.warp(501_000);

        Policy memory policy =
            _buildApprovalPolicy({txType: TransactionType.TokenTransfers, approvalType: PolicyType.AutoApprove});
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = 1000;
        policy.config.rateLimit.anchorTimestamp = 500_000;

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        bytes memory data = _encodeERC20Transfer(RECIPIENT, 42);
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signDefaultInitiatorTx(harness, TOKEN, data, 2002, expiration, true);

        _validateApproval(harness, TOKEN, data, 2002, expiration, initiatorSignature, bytes(""), proofs);

        bytes32 usageKey = _computeUsageKey(DEFAULT_POLICY_ID, policy, ACCOUNT, RECIPIENT, initiator1);
        uint256 window = _computeTimeWindow(policy);
        assertEq(policyStateHarness.getPolicyUsage(usageKey, window), 42, "usage should equal transfer amount");
    }

    /// @dev Verifies that rate limit resets at the anchor-aligned window boundary.
    function test_rateLimitWithAnchor_resetsAtAnchorAlignedBoundary() public {
        // Setup: anchor=500000, interval=1h, limit=100. Window 0=[500000,503600).
        vm.warp(500_000);

        Policy memory policy =
            _buildApprovalPolicy({txType: TransactionType.TokenTransfers, approvalType: PolicyType.AutoApprove});
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = 100;
        policy.config.rateLimit.anchorTimestamp = 500_000;

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        // Exhaust budget in window 0
        bytes memory data1 = _encodeERC20Transfer(RECIPIENT, 100);
        uint256 expiration = block.timestamp + 2 days;
        bytes memory sig1 = _signDefaultInitiatorTx(harness, TOKEN, data1, 2003, expiration, true);
        _validateApproval(harness, TOKEN, data1, 2003, expiration, sig1, bytes(""), proofs);

        // Second tx in same window should revert
        bytes memory data2 = _encodeERC20Transfer(RECIPIENT, 1);
        bytes memory sig2 = _signDefaultInitiatorTx(harness, TOKEN, data2, 2004, expiration, true);
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAccountTransaction.RateLimitExceeded.selector, DEFAULT_POLICY_ID)
        );
        _validateApproval(harness, TOKEN, data2, 2004, expiration, sig2, bytes(""), proofs);

        // Warp to next anchor-aligned boundary
        vm.warp(500_000 + 3600);
        bytes memory data3 = _encodeERC20Transfer(RECIPIENT, 100);
        bytes memory sig3 = _signDefaultInitiatorTx(harness, TOKEN, data3, 2005, expiration, true);
        _validateApproval(harness, TOKEN, data3, 2005, expiration, sig3, bytes(""), proofs);

        bytes32 usageKey = _computeUsageKey(DEFAULT_POLICY_ID, policy, ACCOUNT, RECIPIENT, initiator1);
        uint256 window1 = (500_000 - 500_000) / 3600;
        uint256 window2 = (500_000 + 3600 - 500_000) / 3600;
        assertEq(policyStateHarness.getPolicyUsage(usageKey, window1), 100, "window 0 usage should be 100");
        assertEq(policyStateHarness.getPolicyUsage(usageKey, window2), 100, "window 1 usage should be 100");
    }

    function _computeTimeWindow(Policy memory policy) internal view returns (uint256) {
        if (policy.config.rateLimit.timeIntervalHours == 0) return 0;
        uint256 anchor = policy.config.rateLimit.anchorTimestamp;
        if (block.timestamp < anchor) return 0;
        return (block.timestamp - anchor) / (uint256(policy.config.rateLimit.timeIntervalHours) * 3600);
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

        return keccak256(
            abi.encode(
                policyId,
                policy.config.rateLimit.anchorTimestamp,
                policy.config.rateLimit.timeIntervalHours,
                scopedAccount,
                scopedDestination,
                scopedInitiator
            )
        );
    }

    function _validateApproval(
        LibOrganizationAccountTransactionHarness txHarness,
        address to,
        bytes memory data,
        uint256 salt,
        uint256 expiration,
        bytes memory initiatorSignature,
        bytes memory reviewSignatures,
        ValidationProofs memory proofs
    ) internal {
        txHarness.validateTransactionApprovalOrRevertViaLibrary({
            account: ACCOUNT,
            to: to,
            value: 0,
            data: data,
            salt: salt,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: reviewSignatures,
            proofs: proofs
        });
    }

    function _validateRejection(
        LibOrganizationAccountTransactionHarness txHarness,
        address to,
        bytes memory data,
        uint256 salt,
        uint256 expiration,
        bytes memory initiatorSignature,
        bytes memory reviewSignatures,
        ValidationProofs memory proofs
    ) internal {
        txHarness.validateTransactionRejectionOrRevertViaLibrary({
            account: ACCOUNT,
            to: to,
            value: 0,
            data: data,
            salt: salt,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: reviewSignatures,
            proofs: proofs
        });
    }

    function _signDefaultInitiatorTx(
        LibOrganizationAccountTransactionHarness txHarness,
        address to,
        bytes memory data,
        uint256 salt,
        uint256 expiration,
        bool isApproval
    ) internal view returns (bytes memory) {
        return _signInitiatorTx({
            txHarness: txHarness,
            privateKey: INITIATOR_PK_1,
            account: ACCOUNT,
            to: to,
            value: 0,
            data: data,
            salt: salt,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: isApproval
        });
    }

    function _signDefaultReviewTx(
        LibOrganizationAccountTransactionHarness txHarness,
        uint256 privateKey,
        address to,
        bytes memory data,
        uint256 salt,
        uint256 expiration,
        bool isApproval,
        bytes memory initiatorSignature
    ) internal view returns (bytes memory) {
        return _signReviewTx({
            txHarness: txHarness,
            privateKey: privateKey,
            account: ACCOUNT,
            to: to,
            value: 0,
            data: data,
            salt: salt,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: isApproval,
            initiatorSignature: initiatorSignature
        });
    }

    function _assertInitiatorHashFieldBindings(bytes32 baseInitiatorHash, bytes memory data, uint256 expiration)
        internal
        view
    {
        _assertInitiatorHashPrimaryBindings(baseInitiatorHash, data, expiration);
        _assertInitiatorHashSecondaryBindings(baseInitiatorHash, data, expiration);
    }

    function _assertInitiatorHashPrimaryBindings(bytes32 baseInitiatorHash, bytes memory data, uint256 expiration)
        internal
        view
    {
        assertTrue(
            baseInitiatorHash
                != _computeInitiatorHash(address(uint160(ACCOUNT) + 1), DESTINATION, 1, data, 14, expiration, true),
            "account must be bound"
        );
        assertTrue(
            baseInitiatorHash
                != _computeInitiatorHash(ACCOUNT, address(uint160(DESTINATION) + 1), 1, data, 14, expiration, true),
            "to must be bound"
        );
        assertTrue(
            baseInitiatorHash != _computeInitiatorHash(ACCOUNT, DESTINATION, 2, data, 14, expiration, true),
            "value must be bound"
        );
        assertTrue(
            baseInitiatorHash != _computeInitiatorHash(ACCOUNT, DESTINATION, 1, data, 15, expiration, true),
            "salt must be bound"
        );
    }

    function _assertInitiatorHashSecondaryBindings(bytes32 baseInitiatorHash, bytes memory data, uint256 expiration)
        internal
        view
    {
        assertTrue(
            baseInitiatorHash != _computeInitiatorHash(ACCOUNT, DESTINATION, 1, data, 14, expiration + 1, true),
            "expiration must be bound"
        );
        assertTrue(
            baseInitiatorHash != _computeInitiatorHashForPolicy(ACCOUNT, DESTINATION, 1, data, 14, expiration, true, DEFAULT_POLICY_ID + 1),
            "policyId must be bound"
        );
        assertTrue(
            baseInitiatorHash
                != _computeInitiatorHash(
                    ACCOUNT,
                    DESTINATION,
                    1,
                    abi.encodeWithSelector(bytes4(0xCAFED00E), uint256(14)),
                    14,
                    expiration,
                    true
                ),
            "data must be bound"
        );
        assertTrue(
            baseInitiatorHash != _computeInitiatorHash(ACCOUNT, DESTINATION, 1, data, 14, expiration, false),
            "isApproval must be bound"
        );
    }

    function _assertInitiatorHashChainBinding(bytes32 baseInitiatorHash, bytes memory data, uint256 expiration)
        internal
    {
        uint256 originalChainId = block.chainid;
        vm.chainId(originalChainId + 1);
        bytes32 chainChangedHash = _computeInitiatorHash(ACCOUNT, DESTINATION, 1, data, 14, expiration, true);
        vm.chainId(originalChainId);
        assertTrue(baseInitiatorHash != chainChangedHash, "chainId must be bound");
    }

    function _assertReviewHashBindings(bytes32 baseInitiatorHash, bytes memory data, uint256 expiration)
        internal
        view
    {
        bytes memory initiatorSignature = _signHash(INITIATOR_PK_1, baseInitiatorHash);
        bytes32 baseReviewHashA = _computeReviewHash(DESTINATION, 1, data, 14, expiration, true, initiatorSignature);
        bytes32 baseReviewHashB = _computeReviewHash(DESTINATION, 1, data, 14, expiration, true, initiatorSignature);
        assertEq(baseReviewHashA, baseReviewHashB, "review hash must be deterministic");

        bytes memory differentInitiatorSig = _signHash(INITIATOR_PK_2, baseInitiatorHash);
        bytes32 changedReviewHash =
            _computeReviewHash(DESTINATION, 1, data, 14, expiration, true, differentInitiatorSig);
        assertTrue(baseReviewHashA != changedReviewHash, "review hash must bind initiator signature bytes");
    }

    function _computeInitiatorHash(
        address account,
        address to,
        uint256 value,
        bytes memory data,
        uint256 salt,
        uint256 expiration,
        bool isApproval
    ) internal view returns (bytes32) {
        return _computeInitiatorHashForPolicy(account, to, value, data, salt, expiration, isApproval, DEFAULT_POLICY_ID);
    }

    function _computeInitiatorHashForPolicy(
        address account,
        address to,
        uint256 value,
        bytes memory data,
        uint256 salt,
        uint256 expiration,
        bool isApproval,
        uint256 policyId
    ) internal view returns (bytes32) {
        return harness.computeInitiatorHashFromParamsViaLibrary({
            account: account,
            to: to,
            value: value,
            salt: salt,
            expirationTimestamp: expiration,
            policyId: policyId,
            data: data,
            isApproval: isApproval
        });
    }

    function _computeReviewHash(
        address to,
        uint256 value,
        bytes memory data,
        uint256 salt,
        uint256 expiration,
        bool isApproval,
        bytes memory initiatorSignature
    ) internal view returns (bytes32) {
        return harness.computeReviewHashFromParamsViaLibrary({
            account: ACCOUNT,
            to: to,
            value: value,
            salt: salt,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            data: data,
            isApproval: isApproval,
            initiatorSignature: initiatorSignature
        });
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

    function _setPolicyTypeInValidateApprovalCalldata(bytes memory callData, uint256 rawValue) internal pure {
        uint256 proofsOffset = _readWord(callData, 4 + 9 * 32);
        _setWord(callData, 4 + proofsOffset + 4 * 32, rawValue);
    }

    function _setRateLimitTypeInValidateApprovalCalldata(bytes memory callData, uint256 rawValue) internal pure {
        uint256 proofsOffset = _readWord(callData, 4 + 9 * 32);
        _setWord(callData, 4 + proofsOffset + 17 * 32, rawValue);
    }

    function _seedMembers(address target) internal {
        LibOrganizationAccountTransactionHarness targetHarness = LibOrganizationAccountTransactionHarness(target);
        targetHarness.setMemberStatus(initiator1, true);
        targetHarness.setMemberStatus(initiator2, true);
        targetHarness.setMemberStatus(reviewer1, true);
        targetHarness.setMemberStatus(reviewer2, true);
    }
}
