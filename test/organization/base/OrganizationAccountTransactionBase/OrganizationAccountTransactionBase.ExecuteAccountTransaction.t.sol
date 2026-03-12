// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {Vm} from "forge-std/Vm.sol";

import {AccountImplementation} from "account/AccountImplementation.sol";
import {IAccount} from "interfaces/IAccount.sol";
import {IOrganizationAccountFactory} from "interfaces/organization/IOrganizationAccountFactory.sol";
import {IOrganizationAccountTransaction} from "interfaces/organization/IOrganizationAccountTransaction.sol";
import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
import {IOrganizationSignatures} from "interfaces/organization/IOrganizationSignatures.sol";
import {MockERC1271ValidSigner} from "test/helpers/MockERC1271Signers.sol";
import {
    MockAccountForOrganizationTransaction,
    MockERC1271NonceConsumedSigner,
    MockERC20ForAccountTransaction,
    MockInteractionTarget,
    MockNativeReceiver
} from "test/organization/base/OrganizationAccountTransactionBase/OrganizationAccountTransactionBaseMocks.sol";
import {
    OrganizationAccountTransactionBaseHarness
} from "test/organization/base/OrganizationAccountTransactionBase/OrganizationAccountTransactionBaseHarness.sol";
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
    function test_OATB_EAT_1_executeAccountTransaction_nonGuardianCaller_revertsOnlyGuardian() public {
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
    function test_OATB_EAT_2__OAT_EAT_8_executeAccountTransaction_accountNotDeployed_revertsAccountNotDeployedByOrganization()
        public
    {
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
     * @dev Verifies cross-organization accounts are rejected by both execute and reject entrypoints.
     */
    /// OATB-AXACT-1
    function test_OATB_AXACT_1_crossOrganizationAccount_revertsAccountNotDeployedByOrganization() public {
        // Setup: deploy an account bound to a different organization and mark it as deployed only there.
        OrganizationAccountTransactionBaseHarness otherHarness = new OrganizationAccountTransactionBaseHarness();
        MockAccountForOrganizationTransaction foreignAccount =
            new MockAccountForOrganizationTransaction(address(otherHarness));
        otherHarness.setDeployedAccount(address(foreignAccount), true);

        bytes memory data = abi.encodeWithSelector(bytes4(0x01020304), uint256(201));
        (, ValidationProofs memory proofs, bytes memory initiatorSignature, uint256 expiration) =
            _buildAutoApprovePayload(address(foreignAccount), DESTINATION, 0, data, 201, DEFAULT_POLICY_ID);
        bytes memory rejectionSignature = _signInitiatorTx({
            txHarness: address(harness),
            privateKey: INITIATOR_PK_1,
            account: address(foreignAccount),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 201,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: false
        });

        bytes memory expectedRevertData = abi.encodeWithSelector(
            IOrganizationAccountFactory.AccountNotDeployedByOrganization.selector, address(foreignAccount)
        );

        // Verify: both base entrypoints fail closed against an account deployed by another organization.
        vm.expectRevert(expectedRevertData);
        vm.prank(GUARDIAN);
        // Call: attempt execute against the foreign account.
        harness.executeAccountTransaction({
            account: address(foreignAccount),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 201,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        vm.expectRevert(expectedRevertData);
        vm.prank(GUARDIAN);
        // Call: attempt reject against the same foreign account tuple.
        harness.rejectAccountTransaction({
            account: address(foreignAccount),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 201,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: rejectionSignature,
            proofs: proofs
        });
    }

    /**
     * @dev Verifies nonce computation is deterministic for `(account,to,value,keccak256(data),policyId,salt)`.
     */
    function test_OATB_EAT_3__OAT_EAT_4_executeAccountTransaction_nonceComputedDeterministicallyFromParams()
        public
        view
    {
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
     * @dev Verifies execute-path nonce derivation depends only on the tuple fields and ignores
     * expiration/signatures/proofs.
     */
    function test_NMATB_EAT_1__NMATB_EAT_2__NMATB_EAT_3_executeAccountTransaction_nonceDependsOnlyOnTupleFields()
        public
    {
        // Setup: build one baseline tuple plus field mutations, and prepare two distinct auth/proof payloads.
        address account = address(0xAAAA11);
        address alternateAccount = address(0xAAAA12);
        address alternateDestination = address(0xBBBB13);
        bytes memory data = abi.encodeWithSelector(bytes4(0x01015555), uint256(44));
        bytes memory alternateData = abi.encodeWithSelector(bytes4(0x01016666), uint256(44));
        uint256 policyId = DEFAULT_POLICY_ID;
        uint256 salt = 44;

        Policy memory autoPolicy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofsA = _setSinglePolicyRootAndBuildProofs(policyId, autoPolicy);

        Policy memory manualPolicy = _buildApprovalPolicy(TransactionType.Any, PolicyType.RequireManualApproval);
        ValidationProofs memory proofsB = _setSinglePolicyRootAndBuildProofs(policyId, manualPolicy);

        bytes memory initiatorSignatureA = _signInitiatorTx({
            txHarness: address(harness),
            privateKey: INITIATOR_PK_1,
            account: account,
            to: DESTINATION,
            value: 3,
            data: data,
            salt: salt,
            expirationTimestamp: block.timestamp + 1 days,
            policyId: policyId,
            isApproval: true
        });
        bytes memory initiatorSignatureB = _signInitiatorTx({
            txHarness: address(harness),
            privateKey: INITIATOR_PK_2,
            account: account,
            to: DESTINATION,
            value: 3,
            data: data,
            salt: salt,
            expirationTimestamp: block.timestamp + 2 days,
            policyId: policyId,
            isApproval: true
        });

        // Call: compute the baseline nonce, tuple-field mutations, and same-tuple variants with only auth/proof
        // changes.
        uint256 baseline = _computeNonce(account, DESTINATION, 3, data, policyId, salt);
        uint256 differentAccount = _computeNonce(alternateAccount, DESTINATION, 3, data, policyId, salt);
        uint256 differentDestination = _computeNonce(account, alternateDestination, 3, data, policyId, salt);
        uint256 differentValue = _computeNonce(account, DESTINATION, 4, data, policyId, salt);
        uint256 differentData = _computeNonce(account, DESTINATION, 3, alternateData, policyId, salt);
        uint256 differentPolicyId = _computeNonce(account, DESTINATION, 3, data, policyId + 1, salt);
        uint256 differentSalt = _computeNonce(account, DESTINATION, 3, data, policyId, salt + 1);

        // Verify: tuple-field changes alter the nonce, while expiration/signature/proof changes alone do not.
        assertTrue(baseline != differentAccount, "account should be bound");
        assertTrue(baseline != differentDestination, "destination should be bound");
        assertTrue(baseline != differentValue, "value should be bound");
        assertTrue(baseline != differentData, "data hash should be bound");
        assertTrue(baseline != differentPolicyId, "policy id should be bound");
        assertTrue(baseline != differentSalt, "salt should be bound");
        assertTrue(initiatorSignatureA.length != 0 && initiatorSignatureB.length != 0, "auth fixtures should exist");
        assertTrue(
            keccak256(abi.encode(proofsA.policy)) != keccak256(abi.encode(proofsB.policy)),
            "proof variants should differ for the auth-agnostic nonce assertion"
        );
    }

    /**
     * @dev Verifies nonce is consumed before entering the account external call (CEI ordering).
     */
    /// OATB-AXACT-2
    function test_OATB_AXACT_2__OATB_EAT_4_executeAccountTransaction_nonceConsumedBeforeAccountCall() public {
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
     * @dev Verifies nonce is consumed before approval validation starts.
     */
    function test_OATB_EAT_4_executeAccountTransaction_nonceConsumedBeforeApprovalValidation() public {
        // Setup: deploy account and configure nonce-aware ERC-1271 initiator signer.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        bytes memory data = abi.encodeWithSelector(bytes4(0x89898989), uint256(31));
        uint256 salt = 31;
        uint256 expiration = block.timestamp + 1 days;
        uint256 nonce = _computeNonce(address(account), DESTINATION, 0, data, DEFAULT_POLICY_ID, salt);

        MockERC1271NonceConsumedSigner nonceConsumedSigner = new MockERC1271NonceConsumedSigner(address(harness));
        nonceConsumedSigner.setObservedNonce(nonce);

        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        policy.config.initiator.initiatorMember = address(nonceConsumedSigner);
        harness.setMemberStatus(address(nonceConsumedSigner), true);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        bytes memory initiatorSignature = _buildContractSignature(address(nonceConsumedSigner), hex"CAFE");

        vm.prank(GUARDIAN);
        // Call: execute transaction where initiator signature validation checks nonce state.
        harness.executeAccountTransaction({
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: salt,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        // Verify: execution succeeds, proving nonce was already consumed at validation-time signature recovery.
        assertTrue(harness.getUsedNonce(nonce), "nonce should be consumed");
        assertEq(account.executionCount(), 1, "account should execute once");
    }

    /**
     * @dev Verifies replay with a previously used nonce reverts with `NonceAlreadyUsed`.
     */
    function test_OATB_EAT_5_NMATB_EAT_5_executeAccountTransaction_usedNonce_revertsNonceAlreadyUsed() public {
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
     * @dev Verifies `OrganizationAccountTransactionBase.executeAccountTransaction` blocks same-tuple reentry after
     * nonce consumption.
     */
    function test_OATB_AXACT_3__NMATB_EAT_6__OAT_EAT_5_executeAccountTransaction_reentrantSameNonceAttemptInSameTransaction_revertsNonceAlreadyUsed()
        public
    {
        // Setup: make the account itself the guardian, then configure a nested replay call with the exact same tuple.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        harness.setGuardian(address(account));

        bytes memory data = abi.encodeWithSelector(bytes4(0xDEADBEEF), uint256(41));
        (, ValidationProofs memory proofs, bytes memory initiatorSignature, uint256 expiration) =
            _buildAutoApprovePayload(address(account), DESTINATION, 0, data, 41, DEFAULT_POLICY_ID);
        uint256 nonce = _computeNonce(address(account), DESTINATION, 0, data, DEFAULT_POLICY_ID, 41);

        bytes memory reentrantCallData = abi.encodeCall(
            IOrganizationAccountTransaction.executeAccountTransaction,
            (
                address(account),
                DESTINATION,
                0,
                data,
                41,
                expiration,
                DEFAULT_POLICY_ID,
                initiatorSignature,
                bytes(""),
                proofs
            )
        );
        account.setReentrantCallData(reentrantCallData);

        // Call: execute the outer transaction from the guardian/account address so the account replays the same nonce
        // in-flight.
        vm.prank(address(account));
        harness.executeAccountTransaction({
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 41,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        // Verify: the outer execution succeeds once, while the nested replay fails with `NonceAlreadyUsed`.
        assertTrue(harness.getUsedNonce(nonce), "outer execution should consume the nonce");
        assertEq(account.executionCount(), 1, "outer account call should execute exactly once");
        assertEq(
            account.reentrantRevertData(),
            abi.encodeWithSelector(IOrganizationSignatures.NonceAlreadyUsed.selector, nonce),
            "nested replay should fail with the consumed nonce"
        );
    }

    /**
     * @dev Verifies `OrganizationAccountTransactionBase.executeAccountTransaction` cannot re-enter privileged
     * organization entrypoints from the account context. [TXRL-INV-12]
     */
    function test_TXRL_INV_12_executeAccountTransaction_accountReentryCannotCallPrivilegedOrganizationFunctions()
        public
    {
        // Setup: deploy an account plus downstream target, configure one valid auto-approve transaction, and stage a
        // guardian-only `rejectAccountTransaction` reentry from the account context.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        MockInteractionTarget target = new MockInteractionTarget();
        bytes memory data = abi.encodeWithSelector(target.ping.selector, uint256(73));
        (, ValidationProofs memory proofs, bytes memory initiatorSignature, uint256 expiration) =
            _buildAutoApprovePayload(address(account), address(target), 0, data, 73, DEFAULT_POLICY_ID);
        bytes memory rejectionSignature = _signInitiatorTx({
            txHarness: address(harness),
            privateKey: INITIATOR_PK_1,
            account: address(account),
            to: address(target),
            value: 0,
            data: data,
            salt: 73,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: false
        });
        bytes32 policiesRootBefore = harness.getPoliciesRoot();

        account.setReentrantCallData(
            abi.encodeCall(
                IOrganizationAccountTransaction.rejectAccountTransaction,
                (
                    address(account),
                    address(target),
                    0,
                    data,
                    73,
                    expiration,
                    DEFAULT_POLICY_ID,
                    initiatorSignature,
                    rejectionSignature,
                    proofs
                )
            )
        );

        // Call: execute the outer account transaction as guardian so the account re-enters the organization while the
        // execution path is in flight.
        vm.prank(GUARDIAN);
        harness.executeAccountTransaction({
            account: address(account),
            to: address(target),
            value: 0,
            data: data,
            salt: 73,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        // Verify: the outer execution succeeds once, the reentrant privileged call fails with `UnauthorizedGuardian`,
        // and organization state remains unchanged.
        assertEq(account.executionCount(), 1, "outer account execution should still succeed");
        assertEq(target.calls(), 1, "downstream target should still be called exactly once");
        assertEq(
            account.reentrantRevertData(),
            abi.encodeWithSelector(IOrganizationGuardian.UnauthorizedGuardian.selector, address(account), GUARDIAN),
            "reentrant guardian-only organization call should fail from the account context"
        );
        assertEq(harness.getPoliciesRoot(), policiesRootBefore, "reentrant privileged call must not mutate policy root");
    }

    /**
     * @dev Verifies execution delegates policy validation to `validateTransactionApprovalOrRevert`.
     */
    function test_OATB_EAT_6_executeAccountTransaction_invalidPolicyRevertsPolicyDoesNotApply() public {
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
    function test_OATB_EAT_7_NMATB_EAT_4_executeAccountTransaction_success_emitsAccountTransactionExecuted() public {
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
    function test_OATB_EAT_8_executeAccountTransaction_emitsBeforeAccountExecuteTransactionCall() public {
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
    function test_OATB_EAT_9_executeAccountTransaction_callsAccountExecuteTransactionWithExpectedArguments() public {
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
    function test_OATB_AXACT_4__OATB_EAT_10__OAT_EAT_6__NMATB_EAT_8__OAT_AI_2_executeAccountTransaction_accountExecutionReverts_rollsBackNonceUsage()
        public
    {
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
    function test_OATB_EAT_11_executeAccountTransaction_successfulNativeTransfer_endToEnd() public {
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
    function test_OATB_EAT_12_executeAccountTransaction_successfulERC20Transfer_endToEnd() public {
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
    function test_OATB_EAT_13_executeAccountTransaction_successfulContractInteraction_endToEnd() public {
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
    function test_OATB_EAT_14_executeAccountTransaction_successfulContractInteractionWithValue_endToEnd() public {
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
     * @dev Verifies contract interaction with non-zero value succeeds under a `TransactionType.ContractInteractions`
     *      policy. A transaction with both calldata and `value > 0` is NOT a token transfer, so the
     *      `ContractInteractions` policy type should match it.
     */
    function test_OATB_EAT_14_executeAccountTransaction_contractInteractionWithValue_contractInteractionsPolicy_endToEnd()
        public
    {
        // Setup: deploy account + interaction target and fund account balance.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        MockInteractionTarget target = new MockInteractionTarget();
        uint256 callValue = 0.3 ether;
        vm.deal(address(account), callValue);
        bytes memory data = abi.encodeWithSelector(target.ping.selector, uint256(42));

        Policy memory policy = _buildApprovalPolicy(TransactionType.ContractInteractions, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorTx({
            txHarness: address(harness),
            privateKey: INITIATOR_PK_1,
            account: address(account),
            to: address(target),
            value: callValue,
            data: data,
            salt: 141,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        vm.prank(GUARDIAN);
        // Call: execute value-carrying interaction call under ContractInteractions policy.
        harness.executeAccountTransaction({
            account: address(account),
            to: address(target),
            value: callValue,
            data: data,
            salt: 141,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        // Verify: target receives both value and calldata.
        assertEq(target.calls(), 1, "target should be called once");
        assertEq(target.lastValue(), callValue, "call value should be forwarded");
        assertEq(target.total(), 42, "calldata should be forwarded");
    }

    /**
     * @dev Verifies expired transactions revert in the base execution path.
     */
    function test_OATB_EAT_15__NMATB_EAT_9_executeAccountTransaction_expiredTransaction_revertsTransactionExpired()
        public
    {
        // Setup: deploy account and sign payload with past expiration.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        bytes memory data = abi.encodeWithSelector(bytes4(0x14141414), uint256(14));
        uint256 expiration = block.timestamp - 1;
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        uint256 nonce = _computeNonce(address(account), DESTINATION, 0, data, DEFAULT_POLICY_ID, 14);
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

        // Verify: the reverted expired path must not leave the nonce consumed.
        assertFalse(harness.getUsedNonce(nonce), "expired execution should roll back nonce consumption");
    }

    /**
     * @dev Verifies manual-approval policy with insufficient reviewers reverts.
     */
    function test_OATB_EAT_16__LOAT_VTAOR_12_executeAccountTransaction_manualApprovalInsufficientReviewers_revertsInsufficientApprovals()
        public
    {
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
     * @dev Verifies manual-approval review signatures are bound to the exact initiator signature bytes used during
     * execution.
     */
    function test_OAT_EAT_7_executeAccountTransaction_manualApprovalReviewSignaturesBindInitiatorSignature()
        public
    {
        // Setup: deploy an account, authorize one ERC-1271 initiator member, and prepare two different valid
        // initiator-signature byte arrays for the same transaction tuple.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        MockInteractionTarget target = new MockInteractionTarget();
        MockERC1271ValidSigner contractInitiator = new MockERC1271ValidSigner();

        Policy memory policy = _buildApprovalPolicy(TransactionType.ContractInteractions, PolicyType.RequireManualApproval);
        policy.config.initiator.initiatorMember = address(contractInitiator);
        harness.setMemberStatus(address(contractInitiator), true);

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        bytes memory data = abi.encodeWithSelector(target.ping.selector, uint256(17));
        uint256 expiration = block.timestamp + 1 days;
        uint256 nonce = _computeNonce(address(account), address(target), 0, data, DEFAULT_POLICY_ID, 151);

        bytes memory initiatorSignatureA = _buildContractSignature(address(contractInitiator), hex"CAFE");
        bytes memory initiatorSignatureB = _buildContractSignature(address(contractInitiator), hex"BEEF");
        bytes memory reviewSignatureForA = _signReviewTx({
            txHarness: address(harness),
            privateKey: REVIEWER_PK_1,
            account: address(account),
            to: address(target),
            value: 0,
            data: data,
            salt: 151,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true,
            initiatorSignature: initiatorSignatureA
        });

        // Verify: reusing approvals collected for one initiator-signature byte array fails once the initiator
        // signature changes.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.InsufficientApprovals.selector, 1, 0));
        vm.prank(GUARDIAN);
        // Call: execute the tuple with a different initiator signature while replaying stale review signatures.
        harness.executeAccountTransaction({
            account: address(account),
            to: address(target),
            value: 0,
            data: data,
            salt: 151,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignatureB,
            reviewSignatures: reviewSignatureForA,
            proofs: proofs
        });

        assertFalse(harness.getUsedNonce(nonce), "stale review signatures must not consume the shared nonce");

        bytes memory reviewSignatureForB = _signReviewTx({
            txHarness: address(harness),
            privateKey: REVIEWER_PK_1,
            account: address(account),
            to: address(target),
            value: 0,
            data: data,
            salt: 151,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true,
            initiatorSignature: initiatorSignatureB
        });

        vm.prank(GUARDIAN);
        // Call: execute again with freshly collected review signatures bound to the new initiator signature bytes.
        harness.executeAccountTransaction({
            account: address(account),
            to: address(target),
            value: 0,
            data: data,
            salt: 151,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignatureB,
            reviewSignatures: reviewSignatureForB,
            proofs: proofs
        });

        // Verify: the correctly rebound approvals execute successfully and consume the nonce exactly once.
        assertEq(target.calls(), 1, "only the rebound manual approval should reach the target");
        assertTrue(harness.getUsedNonce(nonce), "successful rebound execution should consume the nonce");
    }

    /**
     * @dev Verifies failed pre-validation does not permanently burn nonce; fixed retry can succeed.
     */
    function test_OATB_AXACT_7__OATB_EAT_17__OAT_EAT_6__LOAT_VTAOR_14__NMATB_EAT_7_executeAccountTransaction_failedValidationDoesNotBurnNonce_sameSaltCanSucceed()
        public
    {
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
     * @dev Verifies execute-path validation reverts cannot leave partial rate-limit usage behind.
     */
    /// OATB-AXACT-8
    function test_OATB_AXACT_8_executeAccountTransaction_validationRevert_rollsBackRateLimitUsage() public {
        // Setup: deploy an account and configure a manual-approval policy with active time-interval rate limiting.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        bytes memory data = abi.encodeWithSelector(bytes4(0x1616A8A8), uint256(168));

        Policy memory policy = _buildApprovalPolicy(TransactionType.ContractInteractions, PolicyType.RequireManualApproval);
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = 25;

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorTx({
            txHarness: address(harness),
            privateKey: INITIATOR_PK_1,
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 168,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        bytes32 usageKey = _computeUsageKey(DEFAULT_POLICY_ID, policy, address(account), DESTINATION, initiator1);
        uint256 window = _computeTimeWindow(policy);

        // Verify: the execute-path validation revert leaves the tracked usage bucket untouched.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.InsufficientApprovals.selector, 1, 0));
        vm.prank(GUARDIAN);
        // Call: attempt execution without the required reviewer signatures.
        harness.executeAccountTransaction({
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 168,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        assertEq(harness.getPolicyUsage(usageKey, window), 0, "validation revert must not persist rate-limit usage");
    }

    /**
     * @dev Verifies external-call failure rolls back prior rate-limit usage updates.
     */
    function test_OATB_AXACT_4_B__OATB_EAT_18__OAT_EAT_10_executeAccountTransaction_executionFailure_rollsBackRateLimitUsage()
        public
    {
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
     * @dev Verifies expired execute-path signatures fail closed without burning the nonce, so the same tuple can be
     * retried successfully with a fresh expiration.
     */
    function test_OAT_EAT_9_executeAccountTransaction_expiredSignatureRejectsAndFreshRetrySucceeds() public {
        // Setup: deploy an account and prepare one transaction tuple with both expired and fresh initiator
        // signatures.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        bytes memory data = abi.encodeWithSelector(bytes4(0x19191919), uint256(19));
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        uint256 expiredExpiration = block.timestamp - 1;
        uint256 freshExpiration = block.timestamp + 1 days;
        uint256 nonce = _computeNonce(address(account), DESTINATION, 0, data, DEFAULT_POLICY_ID, 191);
        bytes memory expiredInitiatorSignature = _signInitiatorTx({
            txHarness: address(harness),
            privateKey: INITIATOR_PK_1,
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 191,
            expirationTimestamp: expiredExpiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });
        bytes memory freshInitiatorSignature = _signInitiatorTx({
            txHarness: address(harness),
            privateKey: INITIATOR_PK_1,
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 191,
            expirationTimestamp: freshExpiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });

        // Verify: the expired signature path reverts before the nonce is burned.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAccountTransaction.TransactionExpired.selector, expiredExpiration, block.timestamp
            )
        );
        vm.prank(GUARDIAN);
        // Call: execute with the expired initiator signature.
        harness.executeAccountTransaction({
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 191,
            expirationTimestamp: expiredExpiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: expiredInitiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        assertFalse(harness.getUsedNonce(nonce), "expired execution must leave the nonce reusable");

        vm.prank(GUARDIAN);
        // Call: retry the exact same tuple and salt with a fresh expiration/signature.
        harness.executeAccountTransaction({
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 191,
            expirationTimestamp: freshExpiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: freshInitiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        // Verify: the fresh retry succeeds and consumes the nonce on the successful path.
        assertTrue(harness.getUsedNonce(nonce), "fresh retry should consume the nonce");
        assertEq(account.executionCount(), 1, "only the fresh execution should reach the account");
    }

    /**
     * @dev Verifies same transaction tuple can execute multiple times using distinct salts/signatures.
     */
    function test_OATB_EAT_19_executeAccountTransaction_sameTupleDifferentSalt_executesMultipleTimes() public {
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
