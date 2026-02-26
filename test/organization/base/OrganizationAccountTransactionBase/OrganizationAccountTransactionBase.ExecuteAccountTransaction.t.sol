// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {Vm} from "forge-std/Vm.sol";

import {AccountImplementation} from "account/AccountImplementation.sol";
import {IAccount} from "interfaces/IAccount.sol";
import {IOrganizationAccountFactory} from "interfaces/organization/IOrganizationAccountFactory.sol";
import {IOrganizationAccountTransaction} from "interfaces/organization/IOrganizationAccountTransaction.sol";
import {IOrganizationSignatures} from "interfaces/organization/IOrganizationSignatures.sol";
import {
    MockAccountForOrganizationTransaction,
    MockERC20ForAccountTransaction,
    MockInteractionTarget,
    MockNativeReceiver
} from "test/organization/base/OrganizationAccountTransactionBase/OrganizationAccountTransactionBaseMocks.sol";
import {
    OrganizationAccountTransactionBaseSuiteBase
} from "test/organization/base/OrganizationAccountTransactionBase/OrganizationAccountTransactionBaseSuiteBase.sol";
import {OperationType} from "types/CommonTypes.sol";
import {Policy, PolicyType, RateLimitType, TransactionType, ValidationProofs} from "types/PolicyTypes.sol";

/**
 * @dev Unit/integration tests for `OrganizationAccountTransactionBase.executeAccountTransaction`.
 */
contract OrganizationAccountTransactionBaseExecuteAccountTransactionTest is
    OrganizationAccountTransactionBaseSuiteBase
{
    /**
     * @dev Verifies that a non-guardian caller is rejected by the `onlyGuardian` modifier.
     */
    function test_executeAccountTransaction_nonGuardianCaller_revertsOnlyGuardian() public {
        // Setup: configure a deployed account fixture and valid payload.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        bytes memory data = abi.encodeWithSelector(bytes4(0x01020304), uint256(1));
        (, ValidationProofs memory proofs, bytes memory initiatorSignature, uint256 expiration) =
            _buildAutoApprovePayload(address(account), DESTINATION, 0, data, 1, DEFAULT_POLICY_ID);

        // Verify: assert non-guardian caller is rejected.
        _expectOnlyGuardianRevert(NON_GUARDIAN);
        vm.prank(NON_GUARDIAN);
        // Call: invoke `executeAccountTransaction` with a non-guardian caller.
        harness.executeAccountTransaction({
            account: address(account),
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

    /**
     * @dev Verifies that an account not deployed by this organization reverts.
     */
    function test_executeAccountTransaction_accountNotDeployed_revertsAccountNotDeployedByOrganization() public {
        // Setup: use a random non-deployed account address.
        address undeployedAccount = address(0xA11CE001);
        bytes memory data = abi.encodeWithSelector(bytes4(0x01020304), uint256(2));
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        // Verify: assert account deployment guard reverts before downstream checks.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAccountFactory.AccountNotDeployedByOrganization.selector, undeployedAccount
            )
        );
        vm.prank(GUARDIAN);
        // Call: invoke `executeAccountTransaction` for a non-deployed account.
        harness.executeAccountTransaction({
            account: undeployedAccount,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 2,
            expirationTimestamp: block.timestamp + 1 days,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: hex"01",
            reviewSignatures: bytes(""),
            proofs: proofs
        });
    }

    /**
     * @dev Verifies nonce computation is deterministic for `(account,to,value,keccak256(data),policyId,salt)`.
     */
    function test_executeAccountTransaction_nonceComputedDeterministicallyFromParams() public view {
        // Setup: define a deterministic operation tuple.
        address account = address(0xAAAA01);
        address to = address(0xBBBB02);
        uint256 value = 33;
        bytes memory data = abi.encodeWithSelector(bytes4(0x12345678), uint256(7));
        uint256 policyId = DEFAULT_POLICY_ID;
        uint256 salt = 81;
        bytes memory operationData = abi.encode(account, to, value, keccak256(data), policyId);

        // Call: compute nonce repeatedly and across a one-field mutation.
        uint256 nonceA = harness.computeNonce(OperationType.AccountTransaction, operationData, salt);
        uint256 nonceB = harness.computeNonce(OperationType.AccountTransaction, operationData, salt);
        uint256 nonceDifferentSalt = harness.computeNonce(OperationType.AccountTransaction, operationData, salt + 1);

        // Verify: deterministic inputs produce identical nonce, and tuple mutations produce distinct nonce.
        assertEq(nonceA, nonceB, "same tuple should map to identical nonce");
        assertTrue(nonceA != nonceDifferentSalt, "different salt should produce different nonce");
    }

    /**
     * @dev Verifies nonce is consumed before entering the account external call (CEI ordering).
     */
    function test_executeAccountTransaction_nonceConsumedBeforeAccountCall() public {
        // Setup: deploy account fixture configured to assert nonce usage at entry.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        account.setAssertNonceConsumedOnEntry(true);

        bytes memory data = abi.encodeWithSelector(bytes4(0x87654321), uint256(3));
        (, ValidationProofs memory proofs, bytes memory initiatorSignature, uint256 expiration) =
            _buildAutoApprovePayload(address(account), DESTINATION, 0, data, 3, DEFAULT_POLICY_ID);

        vm.prank(GUARDIAN);
        // Call: execute a valid account transaction.
        harness.executeAccountTransaction({
            account: address(account),
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

        // Verify: account call executed, proving nonce check passed at external-call entry.
        assertEq(account.executionCount(), 1, "account call should complete once");
    }

    /**
     * @dev Verifies replay with a previously used nonce reverts with `NonceAlreadyUsed`.
     */
    function test_executeAccountTransaction_usedNonce_revertsNonceAlreadyUsed() public {
        // Setup: deploy account and execute once with deterministic tuple.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        bytes memory data = abi.encodeWithSelector(bytes4(0xAABBCCDD), uint256(4));
        (, ValidationProofs memory proofs, bytes memory initiatorSignature, uint256 expiration) =
            _buildAutoApprovePayload(address(account), DESTINATION, 0, data, 4, DEFAULT_POLICY_ID);

        vm.prank(GUARDIAN);
        harness.executeAccountTransaction({
            account: address(account),
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

        uint256 nonce = _computeNonce(address(account), DESTINATION, 0, data, DEFAULT_POLICY_ID, 4);
        vm.expectRevert(abi.encodeWithSelector(IOrganizationSignatures.NonceAlreadyUsed.selector, nonce));
        vm.prank(GUARDIAN);
        // Call: replay the exact same payload.
        harness.executeAccountTransaction({
            account: address(account),
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

    /**
     * @dev Verifies execution delegates policy validation to `validateTransactionApprovalOrRevert`.
     */
    function test_executeAccountTransaction_invalidPolicyRevertsPolicyDoesNotApply() public {
        // Setup: build payload where policy proof is intentionally invalid.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _emptyProofsForPolicy(policy);
        bytes memory data = abi.encodeWithSelector(bytes4(0xA0A0A0A0), uint256(5));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorTx({
            txHarness: address(harness),
            privateKey: INITIATOR_PK_1,
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 5,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        // Verify: policy validation failure bubbles up from library validation.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAccountTransaction.PolicyDoesNotApply.selector, DEFAULT_POLICY_ID)
        );
        vm.prank(GUARDIAN);
        // Call: execute with invalid proofs.
        harness.executeAccountTransaction({
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 5,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });
    }

    /**
     * @dev Verifies success emits `AccountTransactionExecuted` with expected payload.
     */
    function test_executeAccountTransaction_success_emitsAccountTransactionExecuted() public {
        // Setup: deploy account and build valid payload.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        bytes memory data = abi.encodeWithSelector(bytes4(0xB0B0B0B0), uint256(6));
        (, ValidationProofs memory proofs, bytes memory initiatorSignature, uint256 expiration) =
            _buildAutoApprovePayload(address(account), DESTINATION, 0, data, 6, DEFAULT_POLICY_ID);
        uint256 nonce = _computeNonce(address(account), DESTINATION, 0, data, DEFAULT_POLICY_ID, 6);

        vm.expectEmit(true, true, true, true);
        emit IOrganizationAccountTransaction.AccountTransactionExecuted(
            address(account), DESTINATION, 0, data, nonce, DEFAULT_POLICY_ID
        );

        vm.prank(GUARDIAN);
        // Call: execute valid transaction.
        harness.executeAccountTransaction({
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 6,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });
    }

    /**
     * @dev Verifies `AccountTransactionExecuted` is emitted before the account execution event.
     */
    function test_executeAccountTransaction_emitsBeforeAccountExecuteTransactionCall() public {
        // Setup: deploy account and valid payload.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        bytes memory data = abi.encodeWithSelector(bytes4(0xC0C0C0C0), uint256(7));
        (, ValidationProofs memory proofs, bytes memory initiatorSignature, uint256 expiration) =
            _buildAutoApprovePayload(address(account), DESTINATION, 0, data, 7, DEFAULT_POLICY_ID);

        vm.recordLogs();
        vm.prank(GUARDIAN);
        // Call: execute valid transaction and capture logs.
        harness.executeAccountTransaction({
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 7,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        // Verify: organization event precedes account event in emitted logs.
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 orgTopic = keccak256("AccountTransactionExecuted(address,address,uint256,bytes,uint256,uint256)");
        bytes32 accountTopic = keccak256("TransactionExecuted(address,uint256,bytes,uint256,uint256)");

        uint256 orgIndex = type(uint256).max;
        uint256 accountIndex = type(uint256).max;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == orgTopic && orgIndex == type(uint256).max) {
                orgIndex = i;
            }
            if (logs[i].topics[0] == accountTopic && accountIndex == type(uint256).max) {
                accountIndex = i;
            }
        }

        assertTrue(orgIndex != type(uint256).max, "organization event must be emitted");
        assertTrue(accountIndex != type(uint256).max, "account event must be emitted");
        assertTrue(orgIndex < accountIndex, "organization event must precede account event");
    }

    /**
     * @dev Verifies account `executeTransaction` receives the expected argument tuple.
     */
    function test_executeAccountTransaction_callsAccountExecuteTransactionWithExpectedArguments() public {
        // Setup: deploy account and build valid payload.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        bytes memory data = abi.encodeWithSelector(bytes4(0xD0D0D0D0), uint256(8));
        uint256 value = 19;
        (, ValidationProofs memory proofs, bytes memory initiatorSignature, uint256 expiration) =
            _buildAutoApprovePayload(address(account), DESTINATION, value, data, 8, DEFAULT_POLICY_ID);
        uint256 nonce = _computeNonce(address(account), DESTINATION, value, data, DEFAULT_POLICY_ID, 8);

        vm.deal(address(account), value);
        vm.prank(GUARDIAN);
        // Call: execute valid transaction.
        harness.executeAccountTransaction({
            account: address(account),
            to: DESTINATION,
            value: value,
            data: data,
            salt: 8,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        // Verify: recorded args match expected call tuple.
        assertEq(account.lastTo(), DESTINATION, "destination should match");
        assertEq(account.lastValue(), value, "value should match");
        assertEq(account.lastData(), data, "calldata should match");
        assertEq(account.lastNonce(), nonce, "nonce should match");
        assertEq(account.lastPolicyId(), DEFAULT_POLICY_ID, "policyId should match");
    }

    /**
     * @dev Verifies account execution revert bubbles and nonce usage is rolled back.
     */
    function test_executeAccountTransaction_accountExecutionReverts_rollsBackNonceUsage() public {
        // Setup: deploy account configured to revert on execute.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        account.setShouldRevertExecution(true);
        bytes memory data = abi.encodeWithSelector(bytes4(0xE0E0E0E0), uint256(9));
        (, ValidationProofs memory proofs, bytes memory initiatorSignature, uint256 expiration) =
            _buildAutoApprovePayload(address(account), DESTINATION, 0, data, 9, DEFAULT_POLICY_ID);
        uint256 nonce = _computeNonce(address(account), DESTINATION, 0, data, DEFAULT_POLICY_ID, 9);

        // Verify: account revert aborts whole transaction.
        vm.expectRevert(IAccount.TransactionExecutionFailed.selector);
        vm.prank(GUARDIAN);
        // Call: execute payload against reverting account.
        harness.executeAccountTransaction({
            account: address(account),
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

        // Verify: nonce write is rolled back by full revert.
        assertFalse(harness.getUsedNonce(nonce), "nonce must remain unused after revert");
    }

    /**
     * @dev Verifies successful native ETH transfer through account execution path.
     */
    function test_executeAccountTransaction_successfulNativeTransfer_endToEnd() public {
        // Setup: deploy account + receiver and fund account balance.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        MockNativeReceiver receiver = new MockNativeReceiver();
        uint256 transferValue = 0.4 ether;
        vm.deal(address(account), transferValue);

        bytes memory data = bytes("");
        (, ValidationProofs memory proofs, bytes memory initiatorSignature, uint256 expiration) =
            _buildAutoApprovePayload(address(account), address(receiver), transferValue, data, 11, DEFAULT_POLICY_ID);

        vm.prank(GUARDIAN);
        // Call: execute native transfer from account to receiver.
        harness.executeAccountTransaction({
            account: address(account),
            to: address(receiver),
            value: transferValue,
            data: data,
            salt: 11,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        // Verify: receiver balance reflects forwarded ETH.
        assertEq(receiver.totalReceived(), transferValue, "receiver must receive forwarded ETH");
    }

    /**
     * @dev Verifies successful ERC-20 transfer through account execution path.
     */
    function test_executeAccountTransaction_successfulERC20Transfer_endToEnd() public {
        // Setup: deploy account + token and fund account token balance.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        MockERC20ForAccountTransaction token = new MockERC20ForAccountTransaction();
        uint256 amount = 250;
        token.mint(address(account), amount);

        bytes memory data = abi.encodeWithSelector(token.transfer.selector, RECIPIENT, amount);
        (, ValidationProofs memory proofs, bytes memory initiatorSignature, uint256 expiration) =
            _buildAutoApprovePayload(address(account), address(token), 0, data, 12, DEFAULT_POLICY_ID);

        vm.prank(GUARDIAN);
        // Call: execute ERC-20 transfer.
        harness.executeAccountTransaction({
            account: address(account),
            to: address(token),
            value: 0,
            data: data,
            salt: 12,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        // Verify: recipient receives transferred token amount.
        assertEq(token.balanceOf(RECIPIENT), amount, "recipient token balance should increase");
    }

    /**
     * @dev Verifies successful contract interaction through account execution path.
     */
    function test_executeAccountTransaction_successfulContractInteraction_endToEnd() public {
        // Setup: deploy account + interaction target.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        MockInteractionTarget target = new MockInteractionTarget();
        bytes memory data = abi.encodeWithSelector(target.ping.selector, uint256(19));

        (, ValidationProofs memory proofs, bytes memory initiatorSignature, uint256 expiration) =
            _buildAutoApprovePayload(address(account), address(target), 0, data, 13, DEFAULT_POLICY_ID);

        vm.prank(GUARDIAN);
        // Call: execute interaction call.
        harness.executeAccountTransaction({
            account: address(account),
            to: address(target),
            value: 0,
            data: data,
            salt: 13,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        // Verify: target records calldata/caller and updates state.
        assertEq(target.calls(), 1, "target should be called once");
        assertEq(target.lastCaller(), address(account), "call should originate from account");
        assertEq(target.total(), 19, "target should process calldata payload");
    }

    /**
     * @dev Verifies contract interaction with non-zero value forwards native token + calldata.
     */
    function test_executeAccountTransaction_successfulContractInteractionWithValue_endToEnd() public {
        // Setup: deploy account + interaction target and fund account balance.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        MockInteractionTarget target = new MockInteractionTarget();
        uint256 callValue = 0.25 ether;
        vm.deal(address(account), callValue);
        bytes memory data = abi.encodeWithSelector(target.ping.selector, uint256(22));

        (, ValidationProofs memory proofs, bytes memory initiatorSignature, uint256 expiration) =
            _buildAutoApprovePayload(address(account), address(target), callValue, data, 131, DEFAULT_POLICY_ID);

        vm.prank(GUARDIAN);
        // Call: execute value-carrying interaction call.
        harness.executeAccountTransaction({
            account: address(account),
            to: address(target),
            value: callValue,
            data: data,
            salt: 131,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        // Verify: target receives both value and calldata.
        assertEq(target.calls(), 1, "target should be called once");
        assertEq(target.lastValue(), callValue, "call value should be forwarded");
        assertEq(target.total(), 22, "calldata should be forwarded");
    }

    /**
     * @dev Verifies expired transactions revert in the base execution path.
     */
    function test_executeAccountTransaction_expiredTransaction_revertsTransactionExpired() public {
        // Setup: deploy account and sign payload with past expiration.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        bytes memory data = abi.encodeWithSelector(bytes4(0x14141414), uint256(14));
        uint256 expiration = block.timestamp - 1;
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        bytes memory initiatorSignature = _signInitiatorTx({
            txHarness: address(harness),
            privateKey: INITIATOR_PK_1,
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 14,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        // Verify: expiration guard reverts from validation library.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAccountTransaction.TransactionExpired.selector, expiration, block.timestamp
            )
        );
        vm.prank(GUARDIAN);
        // Call: execute with expired timestamp.
        harness.executeAccountTransaction({
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 14,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });
    }

    /**
     * @dev Verifies manual-approval policy with insufficient reviewers reverts.
     */
    function test_executeAccountTransaction_manualApprovalInsufficientReviewers_revertsInsufficientApprovals() public {
        // Setup: deploy account and manual-approval policy payload with no review signatures.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        bytes memory data = abi.encodeWithSelector(bytes4(0x15151515), uint256(15));
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.RequireManualApproval);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorTx({
            txHarness: address(harness),
            privateKey: INITIATOR_PK_1,
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 15,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        // Verify: manual threshold check fails with insufficient approvals.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.InsufficientApprovals.selector, 1, 0));
        vm.prank(GUARDIAN);
        // Call: execute manual policy path without reviewers.
        harness.executeAccountTransaction({
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 15,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });
    }

    /**
     * @dev Verifies failed pre-validation does not permanently burn nonce; fixed retry can succeed.
     */
    function test_executeAccountTransaction_failedValidationDoesNotBurnNonce_sameSaltCanSucceed() public {
        // Setup: deploy account and build payload with first attempt signed by unauthorized initiator.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        bytes memory data = abi.encodeWithSelector(bytes4(0x16161616), uint256(16));
        (, ValidationProofs memory proofs,, uint256 expiration) =
            _buildAutoApprovePayload(address(account), DESTINATION, 0, data, 16, DEFAULT_POLICY_ID);

        bytes memory invalidInitiatorSignature = _signInitiatorTx({
            txHarness: address(harness),
            privateKey: INITIATOR_PK_2,
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 16,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        // Verify: first attempt fails policy validation.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAccountTransaction.PolicyDoesNotApply.selector, DEFAULT_POLICY_ID)
        );
        vm.prank(GUARDIAN);
        // Call: first attempt with invalid initiator signature.
        harness.executeAccountTransaction({
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 16,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: invalidInitiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        uint256 nonce = _computeNonce(address(account), DESTINATION, 0, data, DEFAULT_POLICY_ID, 16);
        assertFalse(harness.getUsedNonce(nonce), "failed validation must not consume nonce");

        bytes memory validInitiatorSignature = _signInitiatorTx({
            txHarness: address(harness),
            privateKey: INITIATOR_PK_1,
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 16,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        vm.prank(GUARDIAN);
        // Call: second attempt reuses same tuple/salt with corrected signature.
        harness.executeAccountTransaction({
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 16,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: validInitiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        // Verify: corrected retry succeeds and consumes nonce once.
        assertTrue(harness.getUsedNonce(nonce), "successful retry should consume nonce");
        assertEq(account.executionCount(), 1, "account should execute exactly once");
    }

    /**
     * @dev Verifies external-call failure rolls back prior rate-limit usage updates.
     */
    function test_executeAccountTransaction_executionFailure_rollsBackRateLimitUsage() public {
        // Setup: deploy account configured to revert after validation and use rate-limited policy.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        account.setShouldRevertExecution(true);
        bytes memory data = abi.encodeWithSelector(bytes4(0x17171717), uint256(17));

        Policy memory policy = _buildApprovalPolicy(TransactionType.ContractInteractions, PolicyType.AutoApprove);
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = 100;

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorTx({
            txHarness: address(harness),
            privateKey: INITIATOR_PK_1,
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 17,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        bytes32 usageKey = _computeUsageKey(DEFAULT_POLICY_ID, policy, address(account), DESTINATION, initiator1);
        uint256 window = _computeTimeWindow(policy);

        vm.expectRevert(IAccount.TransactionExecutionFailed.selector);
        vm.prank(GUARDIAN);
        // Call: execute payload that passes validation but reverts in account execution.
        harness.executeAccountTransaction({
            account: address(account),
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

        // Verify: usage mutation is rolled back with full transaction revert.
        assertEq(harness.getPolicyUsage(usageKey, window), 0, "rate-limit usage must rollback on revert");
    }

    /**
     * @dev Verifies same transaction tuple can execute multiple times using distinct salts/signatures.
     */
    function test_executeAccountTransaction_sameTupleDifferentSalt_executesMultipleTimes() public {
        // Setup: deploy account and build shared transaction tuple.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        bytes memory data = abi.encodeWithSelector(bytes4(0x18181818), uint256(18));
        (, ValidationProofs memory proofs,, uint256 expiration) =
            _buildAutoApprovePayload(address(account), DESTINATION, 0, data, 18, DEFAULT_POLICY_ID);

        bytes memory sigSaltA = _signInitiatorTx({
            txHarness: address(harness),
            privateKey: INITIATOR_PK_1,
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 18,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });
        bytes memory sigSaltB = _signInitiatorTx({
            txHarness: address(harness),
            privateKey: INITIATOR_PK_1,
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 19,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        vm.prank(GUARDIAN);
        // Call: execute first transaction with salt A.
        harness.executeAccountTransaction({
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 18,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: sigSaltA,
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        vm.prank(GUARDIAN);
        // Call: execute second transaction with identical tuple but salt B.
        harness.executeAccountTransaction({
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 19,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: sigSaltB,
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        uint256 nonceA = _computeNonce(address(account), DESTINATION, 0, data, DEFAULT_POLICY_ID, 18);
        uint256 nonceB = _computeNonce(address(account), DESTINATION, 0, data, DEFAULT_POLICY_ID, 19);

        // Verify: distinct salts consume distinct nonces and both executions succeed.
        assertTrue(nonceA != nonceB, "distinct salts should map to distinct nonces");
        assertTrue(harness.getUsedNonce(nonceA), "first nonce should be consumed");
        assertTrue(harness.getUsedNonce(nonceB), "second nonce should be consumed");
        assertEq(account.executionCount(), 2, "both executions should complete");
    }

    // Helpers

    /**
     * @dev Deploys and marks a mock account as organization-deployed.
     */
    function _deployMockAccount() internal returns (MockAccountForOrganizationTransaction account) {
        account = new MockAccountForOrganizationTransaction(address(harness));
        harness.setDeployedAccount(address(account), true);
    }

    /**
     * @dev Builds valid auto-approve proofs + initiator signature for execution flow.
     */
    function _buildAutoApprovePayload(
        address account,
        address to,
        uint256 value,
        bytes memory data,
        uint256 salt,
        uint256 policyId
    )
        internal
        returns (
            Policy memory policy,
            ValidationProofs memory proofs,
            bytes memory initiatorSignature,
            uint256 expiration
        )
    {
        policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        proofs = _setSinglePolicyRootAndBuildProofs(policyId, policy);
        expiration = block.timestamp + 1 days;
        initiatorSignature = _signInitiatorTx({
            txHarness: address(harness),
            privateKey: INITIATOR_PK_1,
            account: account,
            to: to,
            value: value,
            data: data,
            salt: salt,
            expirationTimestamp: expiration,
            policyId: policyId,
            isApproval: true
        });
    }

    /**
     * @dev Computes account-transaction nonce from operation tuple.
     */
    function _computeNonce(
        address account,
        address to,
        uint256 value,
        bytes memory data,
        uint256 policyId,
        uint256 salt
    ) internal view returns (uint256) {
        bytes memory operationData = abi.encode(account, to, value, keccak256(data), policyId);
        return harness.computeNonce(OperationType.AccountTransaction, operationData, salt);
    }
}
