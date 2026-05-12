// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAccountTransaction} from "interfaces/organization/IOrganizationAccountTransaction.sol";
import {
    LibOrganizationAccountTransactionTestBase
} from "test/organization/libraries/LibOrganizationAccountTransaction/LibOrganizationAccountTransactionTestBase.sol";
import {
    Policy,
    PolicyType,
    RateLimitScope,
    RateLimitType,
    TransactionType,
    ValidationProofs
} from "types/PolicyTypes.sol";
import {ApproverType} from "types/PolicyTypes.sol";

/**
 * @dev Unit tests for internal helper wrappers in `LibOrganizationAccountTransaction`.
 */
contract LibOrganizationAccountTransactionInternalHelpersTest is LibOrganizationAccountTransactionTestBase {
    /// @dev Verifies non-time-interval rate-limit type is treated as no-op.
    function test_validateAndUpdateRateLimit_nonTimeIntervalType_noOp() public {
        // Setup: policy disables rate limiting and pre-seed usage.
        Policy memory policy = _buildApprovalPolicy(TransactionType.ContractInteractions, PolicyType.AutoApprove);
        policy.config.rateLimit.limitType = RateLimitType.None;
        policy.config.rateLimit.destinationScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.sourceScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.initiatorScope = RateLimitScope.PerEntity;

        bytes memory data = abi.encodeWithSelector(bytes4(0x41414141), uint256(1));
        bytes32 usageKey = _computeUsageKey(DEFAULT_POLICY_ID, policy, ACCOUNT, DESTINATION, initiator1);
        policyStateHarness.setPolicyUsage(usageKey, 0, 9);

        // Call: run rate-limit validation/update helper.
        harness.validateAndUpdateRateLimitOrRevertViaLibrary(
            ACCOUNT, DESTINATION, 0, 1, block.timestamp + 1 days, DEFAULT_POLICY_ID, data, initiator1, policy
        );

        // Verify: usage remains unchanged in no-op mode.
        assertEq(policyStateHarness.getPolicyUsage(usageKey, 0), 9, "rate-limit none should not mutate usage");
    }

    /// @dev Verifies token-transfer rate usage uses extracted transfer amount and recipient destination.
    function test_validateAndUpdateRateLimit_tokenTransfer_usesTransferAmountAndRecipientDestination() public {
        // Setup: token-transfer policy with enabled rate-limit and scoped usage key.
        Policy memory policy = _buildApprovalPolicy(TransactionType.TokenTransfers, PolicyType.AutoApprove);
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = 1000;
        policy.config.rateLimit.destinationScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.sourceScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.initiatorScope = RateLimitScope.PerEntity;

        uint256 amount = 42;
        bytes memory data = _encodeErc20Transfer(RECIPIENT, amount);

        // Call: run rate-limit validation/update helper.
        harness.validateAndUpdateRateLimitOrRevertViaLibrary(
            ACCOUNT, TOKEN, 0, 2, block.timestamp + 1 days, DEFAULT_POLICY_ID, data, initiator1, policy
        );

        bytes32 usageKey = _computeUsageKey(DEFAULT_POLICY_ID, policy, ACCOUNT, RECIPIENT, initiator1);
        uint256 window = _computeTimeWindow(policy);
        // Verify: usage increments by transfer amount on recipient-scoped key.
        assertEq(policyStateHarness.getPolicyUsage(usageKey, window), amount, "usage should equal transfer amount");
    }

    /// @dev Verifies contract-interaction usage is count-based (`usageAmount = 1`).
    function test_validateAndUpdateRateLimit_nonTokenTransfer_usesCountBasedUsage() public {
        // Setup: contract-interaction policy with enabled rate-limit.
        Policy memory policy = _buildApprovalPolicy(TransactionType.ContractInteractions, PolicyType.AutoApprove);
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = 1000;
        policy.config.rateLimit.destinationScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.sourceScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.initiatorScope = RateLimitScope.PerEntity;

        bytes memory data = abi.encodeWithSelector(bytes4(0x42424242), uint256(2));
        // Call: run rate-limit validation/update helper.
        harness.validateAndUpdateRateLimitOrRevertViaLibrary(
            ACCOUNT, DESTINATION, 0, 3, block.timestamp + 1 days, DEFAULT_POLICY_ID, data, initiator1, policy
        );

        bytes32 usageKey = _computeUsageKey(DEFAULT_POLICY_ID, policy, ACCOUNT, DESTINATION, initiator1);
        uint256 window = _computeTimeWindow(policy);
        // Verify: usage increments by one for non-token interactions.
        assertEq(policyStateHarness.getPolicyUsage(usageKey, window), 1, "non-token usage should increment by one");
    }

    /// @dev Verifies native transfer usage amount is derived from `value` when calldata is empty.
    function test_validateAndUpdateRateLimit_nativeTransfer_usesValueAsUsageAmount() public {
        // Setup: token-transfer policy with enabled rate-limit.
        Policy memory policy = _buildApprovalPolicy(TransactionType.TokenTransfers, PolicyType.AutoApprove);
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = 1000;
        policy.config.rateLimit.destinationScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.sourceScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.initiatorScope = RateLimitScope.PerEntity;

        uint256 value = 55;
        // Call: run rate-limit validation/update helper on native transfer shape.
        harness.validateAndUpdateRateLimitOrRevertViaLibrary(
            ACCOUNT, DESTINATION, value, 4, block.timestamp + 1 days, DEFAULT_POLICY_ID, bytes(""), initiator1, policy
        );

        bytes32 usageKey = _computeUsageKey(DEFAULT_POLICY_ID, policy, ACCOUNT, DESTINATION, initiator1);
        uint256 window = _computeTimeWindow(policy);
        // Verify: usage tracks native transfer value.
        assertEq(policyStateHarness.getPolicyUsage(usageKey, window), value, "native transfer usage should equal value");
    }

    /// @dev Verifies an unrecognized rate-limit type fails closed rather than reverting with `RateLimitExceeded`.
    function test_validateAndUpdateRateLimit_unknownRateLimitType_failsClosed() public {
        // Setup: build a valid time-interval rate-limit payload, then patch the encoded
        // `limitType` word to an out-of-range enum value. Solidity's own range check on calldata
        // enum reads will fire before the library's explicit guard, but the outcome is the same
        // fail-closed behavior the dedicated `UnknownRateLimitType` error exists to express.
        Policy memory policy = _buildApprovalPolicy(TransactionType.ContractInteractions, PolicyType.AutoApprove);
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = 1000;
        policy.config.rateLimit.destinationScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.sourceScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.initiatorScope = RateLimitScope.PerEntity;

        bytes memory data = abi.encodeWithSelector(bytes4(0x53535353), uint256(13));
        bytes memory callData = abi.encodeCall(
            harness.validateAndUpdateRateLimitOrRevertViaLibrary,
            (ACCOUNT, DESTINATION, 0, 19, block.timestamp + 1 days, DEFAULT_POLICY_ID, data, initiator1, policy)
        );
        _setRateLimitTypeInRateLimitCalldata(callData, 2);

        // Call: dispatch the patched calldata via low-level call so the bad enum byte reaches the library.
        (bool success, bytes memory returnData) = address(harness).call(callData);

        // Verify: the call fails closed and never resolves to the misleading `RateLimitExceeded` error.
        assertFalse(success, "unknown rate-limit type must fail closed");
        // Reading the first 4 bytes of a revert payload to compare selectors is intentional here.
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes4 returnSelector = returnData.length >= 4 ? bytes4(returnData) : bytes4(0);
        assertTrue(
            returnSelector != IOrganizationAccountTransaction.RateLimitExceeded.selector,
            "unknown rate-limit type must not surface as RateLimitExceeded"
        );
    }

    /// @dev Verifies the dedicated `UnknownRateLimitType` error has a stable selector distinct from
    /// `RateLimitExceeded`.
    function test_unknownRateLimitTypeErrorSelector_isDistinctFromRateLimitExceeded() public pure {
        // Setup: nothing to set up, this is a pure selector comparison.
        // Call: read both error selectors off the interface.
        bytes4 unknownSelector = IOrganizationAccountTransaction.UnknownRateLimitType.selector;
        bytes4 exceededSelector = IOrganizationAccountTransaction.RateLimitExceeded.selector;
        // Verify: the two errors have distinct ABI selectors so callers can tell them apart.
        assertTrue(unknownSelector != exceededSelector, "UnknownRateLimitType must not collide with RateLimitExceeded");
        assertEq(
            unknownSelector, bytes4(keccak256("UnknownRateLimitType(uint256)")), "selector must encode policyId arg"
        );
    }

    // Patches the `rateLimit.limitType` word inside the encoded calldata for
    // `validateAndUpdateRateLimitOrRevertViaLibrary` so a test can inject an out-of-range enum value
    // without tripping Solidity's compile-time enum range check on the in-memory `Policy`.
    function _setRateLimitTypeInRateLimitCalldata(bytes memory callData, uint256 rawValue) internal pure {
        // 4 bytes selector + 8 head slots before the inlined `Policy`
        // (account, to, value, salt, expirationTimestamp, policyId, data offset, initiator)
        // + 17 slots into the inlined `Policy` to reach `config.rateLimit.limitType`.
        _setWord(callData, 4 + 25 * 32, rawValue);
    }

    /// @dev Verifies rate-limit exceedance reverts `RateLimitExceeded`.
    function test_validateAndUpdateRateLimit_exceeded_revertsRateLimitExceeded() public {
        // Setup: low interval limit and oversized token transfer amount.
        Policy memory policy = _buildApprovalPolicy(TransactionType.TokenTransfers, PolicyType.AutoApprove);
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = 10;
        bytes memory data = _encodeErc20Transfer(RECIPIENT, 11);

        // Verify: helper reverts when usage would exceed limit.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAccountTransaction.RateLimitExceeded.selector, DEFAULT_POLICY_ID)
        );
        // Call: run rate-limit validation/update helper.
        harness.validateAndUpdateRateLimitOrRevertViaLibrary(
            ACCOUNT, TOKEN, 0, 5, block.timestamp + 1 days, DEFAULT_POLICY_ID, data, initiator1, policy
        );
    }

    /// @dev Verifies time-window rollover allows usage again after interval boundary.
    function test_validateAndUpdateRateLimit_nextWindow_allowsUsageAgain() public {
        // Setup: initialize a one-hour interval policy with per-entity scopes.
        Policy memory policy = _buildApprovalPolicy(TransactionType.ContractInteractions, PolicyType.AutoApprove);
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = 1;
        policy.config.rateLimit.destinationScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.sourceScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.initiatorScope = RateLimitScope.PerEntity;
        bytes memory data = abi.encodeWithSelector(bytes4(0x43434343), uint256(3));

        // Call: consume full limit in current window.
        harness.validateAndUpdateRateLimitOrRevertViaLibrary(
            ACCOUNT, DESTINATION, 0, 6, block.timestamp + 1 days, DEFAULT_POLICY_ID, data, initiator1, policy
        );

        // Verify: second call in same window exceeds limit.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAccountTransaction.RateLimitExceeded.selector, DEFAULT_POLICY_ID)
        );
        harness.validateAndUpdateRateLimitOrRevertViaLibrary(
            ACCOUNT, DESTINATION, 0, 7, block.timestamp + 1 days, DEFAULT_POLICY_ID, data, initiator1, policy
        );

        // Move into next time window.
        vm.warp(block.timestamp + 3600);

        // Call: usage in next window should succeed again.
        harness.validateAndUpdateRateLimitOrRevertViaLibrary(
            ACCOUNT, DESTINATION, 0, 8, block.timestamp + 1 days, DEFAULT_POLICY_ID, data, initiator1, policy
        );
    }

    /// @dev Verifies `TransactionType.Any` uses count-based usage even for token transfer shapes.
    function test_validateAndUpdateRateLimit_transactionTypeAny_usesCountBasedUsage() public {
        // Setup: any-type policy with rate-limit enabled.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = 1000;
        policy.config.rateLimit.destinationScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.sourceScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.initiatorScope = RateLimitScope.PerEntity;
        bytes memory data = _encodeErc20Transfer(RECIPIENT, 500);

        // Call: run helper on ERC-20 transfer shaped transaction.
        harness.validateAndUpdateRateLimitOrRevertViaLibrary(
            ACCOUNT, TOKEN, 0, 9, block.timestamp + 1 days, DEFAULT_POLICY_ID, data, initiator1, policy
        );

        bytes32 usageKey = _computeUsageKey(DEFAULT_POLICY_ID, policy, ACCOUNT, RECIPIENT, initiator1);
        uint256 window = _computeTimeWindow(policy);
        // Verify: usage is count-based (1), not transfer amount.
        assertEq(policyStateHarness.getPolicyUsage(usageKey, window), 1, "txType Any should be count-based");
    }

    /// @dev Verifies auto-approve rejection requires non-empty review signature.
    function test_validateAutoApproveRejection_emptyReviewSignature_revertsTransactionRejectionNotAllowed() public {
        // Setup: valid auto-approve rejection context with empty review signatures.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        // Verify: empty review signatures are rejected for auto-approve rejection flow.
        vm.expectRevert(IOrganizationAccountTransaction.TransactionRejectionNotAllowed.selector);
        // Call: validate auto-approve rejection helper directly.
        harness.validateAutoApproveRejectionOrRevertViaLibrary(
            ACCOUNT,
            DESTINATION,
            0,
            10,
            block.timestamp + 1 days,
            DEFAULT_POLICY_ID,
            abi.encodeWithSelector(bytes4(0x44444444), uint256(4)),
            bytes(""),
            proofs
        );
    }

    /// @dev Verifies auto-approve rejection succeeds for authorized initiator signatures.
    function test_validateAutoApproveRejection_authorizedInitiatorSigner_succeeds() public {
        // Setup: auto-approve policy and rejection signature from authorized initiator.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        bytes memory data = abi.encodeWithSelector(bytes4(0x45454545), uint256(5));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory rejectionSig = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 11, expiration, DEFAULT_POLICY_ID, false
        );

        // Call: validate auto-approve rejection helper.
        harness.validateAutoApproveRejectionOrRevertViaLibrary(
            ACCOUNT, DESTINATION, 0, 11, expiration, DEFAULT_POLICY_ID, data, rejectionSig, proofs
        );
    }

    /// @dev Verifies auto-approve rejection also accepts a different authorized initiator.
    function test_validateAutoApproveRejection_differentAuthorizedInitiator_succeeds() public {
        // Setup: allow initiator group with two members and sign rejection by second initiator.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        policy.config.initiator.initiatorType = ApproverType.Group;
        policy.config.initiator.initiatorGroupId = 901;
        policyStateHarness.setGroupStatus(901, true);
        policyStateHarness.setGroupMemberStatus(901, initiator1, true);
        policyStateHarness.setGroupMemberStatus(901, initiator2, true);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        bytes memory data = abi.encodeWithSelector(bytes4(0x46464646), uint256(6));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory rejectionSig = _signInitiatorTx(
            address(harness), INITIATOR_PK_2, ACCOUNT, DESTINATION, 0, data, 12, expiration, DEFAULT_POLICY_ID, false
        );

        // Call: validate auto-approve rejection helper with second initiator signature.
        harness.validateAutoApproveRejectionOrRevertViaLibrary(
            ACCOUNT, DESTINATION, 0, 12, expiration, DEFAULT_POLICY_ID, data, rejectionSig, proofs
        );
    }

    /// @dev Verifies manual-confirmation helper uses policy threshold and rejects below-threshold approvals.
    function test_validateManualConfirmation_belowThreshold_revertsInsufficientApprovals() public {
        // Setup: group approver threshold=2 with one valid review signature.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.RequireManualApproval);
        policy.config.approval.approverType = ApproverType.Group;
        policy.config.approval.approverGroupId = 902;
        policy.config.approval.approvalThreshold = 2;
        policyStateHarness.setGroupStatus(902, true);
        policyStateHarness.setGroupMemberStatus(902, reviewer1, true);
        policyStateHarness.setGroupMemberStatus(902, reviewer2, true);

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        bytes memory data = abi.encodeWithSelector(bytes4(0x47474747), uint256(7));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSig = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 13, expiration, DEFAULT_POLICY_ID, true
        );
        bytes memory oneReviewSig = _signReviewTx(
            address(harness),
            REVIEWER_PK_1,
            ACCOUNT,
            DESTINATION,
            0,
            data,
            13,
            expiration,
            DEFAULT_POLICY_ID,
            true,
            initiatorSig
        );

        // Verify: one-of-two approvals reverts with InsufficientApprovals(required, 0).
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.InsufficientApprovals.selector, 2, 0));
        // Call: validate manual confirmation helper.
        harness.validateManualConfirmationOrRevertViaLibrary(
            ACCOUNT, DESTINATION, 0, 13, expiration, DEFAULT_POLICY_ID, data, oneReviewSig, initiatorSig, proofs, true
        );
    }

    /// @dev Verifies manual-confirmation succeeds with sufficient approvals.
    function test_validateManualConfirmation_sufficientApprovals_succeeds() public {
        // Setup: group approver threshold=2 with two valid review signatures.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.RequireManualApproval);
        policy.config.approval.approverType = ApproverType.Group;
        policy.config.approval.approverGroupId = 903;
        policy.config.approval.approvalThreshold = 2;
        policyStateHarness.setGroupStatus(903, true);
        policyStateHarness.setGroupMemberStatus(903, reviewer1, true);
        policyStateHarness.setGroupMemberStatus(903, reviewer2, true);

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        bytes memory data = abi.encodeWithSelector(bytes4(0x48484848), uint256(8));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSig = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 14, expiration, DEFAULT_POLICY_ID, true
        );
        bytes memory sig1 = _signReviewTx(
            address(harness),
            REVIEWER_PK_1,
            ACCOUNT,
            DESTINATION,
            0,
            data,
            14,
            expiration,
            DEFAULT_POLICY_ID,
            true,
            initiatorSig
        );
        bytes memory sig2 = _signReviewTx(
            address(harness),
            REVIEWER_PK_2,
            ACCOUNT,
            DESTINATION,
            0,
            data,
            14,
            expiration,
            DEFAULT_POLICY_ID,
            true,
            initiatorSig
        );
        bytes memory reviewSignatures =
            reviewer1 < reviewer2 ? abi.encodePacked(sig1, sig2) : abi.encodePacked(sig2, sig1);

        // Call: validate manual confirmation helper.
        harness.validateManualConfirmationOrRevertViaLibrary(
            ACCOUNT,
            DESTINATION,
            0,
            14,
            expiration,
            DEFAULT_POLICY_ID,
            data,
            reviewSignatures,
            initiatorSig,
            proofs,
            true
        );
    }

    /// @dev Verifies review-hash binding changes when initiator signature bytes change.
    function test_validateManualConfirmation_reviewHashBindsInitiatorSignature() public {
        // Setup: derive two initiator signatures for the same transaction hash from different keys.
        bytes memory data = abi.encodeWithSelector(bytes4(0x49494949), uint256(9));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSigA = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 15, expiration, DEFAULT_POLICY_ID, true
        );
        bytes memory initiatorSigB = _signInitiatorTx(
            address(harness), INITIATOR_PK_2, ACCOUNT, DESTINATION, 0, data, 15, expiration, DEFAULT_POLICY_ID, true
        );

        // Call: compute review hashes for each initiator signature.
        bytes32 reviewHashA = harness.computeReviewHashFromParamsViaLibrary(
            ACCOUNT, DESTINATION, 0, 15, expiration, DEFAULT_POLICY_ID, data, true, initiatorSigA
        );
        bytes32 reviewHashB = harness.computeReviewHashFromParamsViaLibrary(
            ACCOUNT, DESTINATION, 0, 15, expiration, DEFAULT_POLICY_ID, data, true, initiatorSigB
        );

        // Verify: initiator signature bytes are part of review hash binding.
        assertTrue(reviewHashA != reviewHashB, "review hash should bind initiator signature bytes");
    }

    /// @dev Verifies duplicate/out-of-order reviewers fail closed by reverting `InsufficientApprovals`.
    function test_validateManualConfirmation_duplicateOrOutOfOrderReviewers_failClosedWithInsufficientApprovals()
        public
    {
        // Setup: threshold-two group policy with duplicate reviewer signatures.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.RequireManualApproval);
        policy.config.approval.approverType = ApproverType.Group;
        policy.config.approval.approverGroupId = 904;
        policy.config.approval.approvalThreshold = 2;
        policyStateHarness.setGroupStatus(904, true);
        policyStateHarness.setGroupMemberStatus(904, reviewer1, true);
        policyStateHarness.setGroupMemberStatus(904, reviewer2, true);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        bytes memory data = abi.encodeWithSelector(bytes4(0x50505050), uint256(10));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSig = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 16, expiration, DEFAULT_POLICY_ID, true
        );
        bytes memory dupSig = _signReviewTx(
            address(harness),
            REVIEWER_PK_1,
            ACCOUNT,
            DESTINATION,
            0,
            data,
            16,
            expiration,
            DEFAULT_POLICY_ID,
            true,
            initiatorSig
        );
        bytes memory duplicated = abi.encodePacked(dupSig, dupSig);

        // Verify: duplicate reviewer signatures fail closed as insufficient approvals.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.InsufficientApprovals.selector, 2, 0));
        // Call: validate manual confirmation helper.
        harness.validateManualConfirmationOrRevertViaLibrary(
            ACCOUNT, DESTINATION, 0, 16, expiration, DEFAULT_POLICY_ID, data, duplicated, initiatorSig, proofs, true
        );
    }

    /// @dev Verifies unauthorized reviewer fails closed by reverting `InsufficientApprovals`.
    function test_validateManualConfirmation_unauthorizedReviewer_failClosedWithInsufficientApprovals() public {
        // Setup: member-approver policy where reviewer2 is unauthorized signer.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.RequireManualApproval);
        policy.config.approval.approverType = ApproverType.Member;
        policy.config.approval.approverMember = reviewer1;
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        bytes memory data = abi.encodeWithSelector(bytes4(0x51515151), uint256(11));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSig = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 17, expiration, DEFAULT_POLICY_ID, true
        );
        bytes memory unauthorizedSig = _signReviewTx(
            address(harness),
            REVIEWER_PK_2,
            ACCOUNT,
            DESTINATION,
            0,
            data,
            17,
            expiration,
            DEFAULT_POLICY_ID,
            true,
            initiatorSig
        );

        // Verify: unauthorized reviewer signature fails closed as insufficient approvals.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.InsufficientApprovals.selector, 1, 0));
        // Call: validate manual confirmation helper.
        harness.validateManualConfirmationOrRevertViaLibrary(
            ACCOUNT,
            DESTINATION,
            0,
            17,
            expiration,
            DEFAULT_POLICY_ID,
            data,
            unauthorizedSig,
            initiatorSig,
            proofs,
            true
        );
    }

    /// @dev Verifies non-existent approver group fails closed by reverting `InsufficientApprovals`.
    function test_validateManualConfirmation_nonExistentApproverGroup_failClosedWithInsufficientApprovals() public {
        // Setup: group-approver policy references a missing group ID.
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.RequireManualApproval);
        policy.config.approval.approverType = ApproverType.Group;
        policy.config.approval.approverGroupId = 905;
        policy.config.approval.approvalThreshold = 1;
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        bytes memory data = abi.encodeWithSelector(bytes4(0x52525252), uint256(12));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSig = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 18, expiration, DEFAULT_POLICY_ID, true
        );
        bytes memory reviewerSig = _signReviewTx(
            address(harness),
            REVIEWER_PK_1,
            ACCOUNT,
            DESTINATION,
            0,
            data,
            18,
            expiration,
            DEFAULT_POLICY_ID,
            true,
            initiatorSig
        );

        // Verify: missing approver group fails closed as insufficient approvals.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.InsufficientApprovals.selector, 1, 0));
        // Call: validate manual confirmation helper.
        harness.validateManualConfirmationOrRevertViaLibrary(
            ACCOUNT, DESTINATION, 0, 18, expiration, DEFAULT_POLICY_ID, data, reviewerSig, initiatorSig, proofs, true
        );
    }
}
