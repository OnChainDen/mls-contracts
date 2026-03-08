// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Vm} from "forge-std/Vm.sol";

import {IOrganizationAccountFactory} from "interfaces/organization/IOrganizationAccountFactory.sol";
import {IOrganizationAccountTransaction} from "interfaces/organization/IOrganizationAccountTransaction.sol";
import {IOrganizationSignatures} from "interfaces/organization/IOrganizationSignatures.sol";
import {
    MockAccountForOrganizationTransaction,
    MockERC1271NonceConsumedSigner
} from "test/organization/base/OrganizationAccountTransactionBase/OrganizationAccountTransactionBaseMocks.sol";
import {
    OrganizationAccountTransactionBaseSuiteBase
} from "test/organization/base/OrganizationAccountTransactionBase/OrganizationAccountTransactionBaseSuiteBase.sol";
import {OperationType} from "types/CommonTypes.sol";
import {Policy, PolicyType, TransactionType, ValidationProofs} from "types/PolicyTypes.sol";

/**
 * @dev Unit/integration tests for `OrganizationAccountTransactionBase.rejectAccountTransaction`.
 */
contract OrganizationAccountTransactionBaseRejectAccountTransactionTest is OrganizationAccountTransactionBaseSuiteBase {
    /**
     * @dev Verifies that a non-guardian caller is rejected by the `onlyGuardian` modifier.
     */
    function test_OATB_RAT_1_rejectAccountTransaction_nonGuardianCaller_revertsOnlyGuardian() public {
        // Setup: configure a deployed account fixture and valid rejection payload.
        address account = address(0xAC001);
        harness.setDeployedAccount(account, true);
        bytes memory data = abi.encodeWithSelector(bytes4(0x01020304), uint256(1));
        (
            ,
            ValidationProofs memory proofs,
            bytes memory initiatorSignature,
            bytes memory reviewSignature,
            uint256 expiration
        ) = _buildAutoRejectPayload(account, DESTINATION, 0, data, 1, DEFAULT_POLICY_ID);

        // Verify: assert non-guardian caller is rejected.
        _expectOnlyGuardianRevert(NON_GUARDIAN);
        vm.prank(NON_GUARDIAN);
        // Call: invoke `rejectAccountTransaction` with a non-guardian caller.
        harness.rejectAccountTransaction({
            account: account,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 1,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: reviewSignature,
            proofs: proofs
        });
    }

    /**
     * @dev Verifies that an account not deployed by this organization reverts.
     */
    function test_OATB_RAT_2_rejectAccountTransaction_accountNotDeployed_revertsAccountNotDeployedByOrganization()
        public
    {
        // Setup: use a random non-deployed account address.
        address undeployedAccount = address(0xAC002);
        bytes memory data = abi.encodeWithSelector(bytes4(0x02030405), uint256(2));
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        // Verify: assert account deployment guard reverts before downstream checks.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAccountFactory.AccountNotDeployedByOrganization.selector, undeployedAccount
            )
        );
        vm.prank(GUARDIAN);
        // Call: invoke `rejectAccountTransaction` for a non-deployed account.
        harness.rejectAccountTransaction({
            account: undeployedAccount,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 2,
            expirationTimestamp: block.timestamp + 1 days,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: hex"01",
            reviewSignatures: hex"01",
            proofs: proofs
        });
    }

    /**
     * @dev Verifies reject nonce matches execute nonce for the same operation tuple by going
     *      through the actual execute and reject paths.
     */
    function test_OATB_RAT_3__NMATB_RAT_1__NMATB_RAT_7_rejectAccountTransaction_nonceMatchesExecuteForSameTuple()
        public
    {
        // Setup: deploy account and build shared payload with both approval and rejection signatures.
        MockAccountForOrganizationTransaction account = new MockAccountForOrganizationTransaction(address(harness));
        harness.setDeployedAccount(address(account), true);
        bytes memory data = abi.encodeWithSelector(bytes4(0x03040506), uint256(3));
        (
            ,
            ValidationProofs memory proofs,
            bytes memory initiatorSignature,
            bytes memory rejectionSignature,
            uint256 expiration
        ) = _buildAutoRejectPayload(address(account), DESTINATION, 0, data, 3, DEFAULT_POLICY_ID);

        // Call: execute the transaction and extract the nonce from the emitted event.
        vm.recordLogs();
        vm.prank(GUARDIAN);
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
        uint256 executeNonce = _extractExecuteEventNonce(vm.getRecordedLogs());

        // Verify: reject with the same tuple reverts with the nonce emitted by execute.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationSignatures.NonceAlreadyUsed.selector, executeNonce));
        vm.prank(GUARDIAN);
        harness.rejectAccountTransaction({
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 3,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: rejectionSignature,
            proofs: proofs
        });
    }

    /**
     * @dev Verifies nonce is consumed before rejection validation starts.
     */
    function test_OATB_RAT_4_rejectAccountTransaction_nonceConsumedBeforeRejectionValidation() public {
        // Setup: configure deployed account and nonce-aware ERC-1271 signer for initiator/rejection signatures.
        address account = address(0xAC003A);
        harness.setDeployedAccount(account, true);
        bytes memory data = abi.encodeWithSelector(bytes4(0x033A3A3A), uint256(33));
        uint256 salt = 33;
        uint256 expiration = block.timestamp + 1 days;
        uint256 nonce = _computeNonce(account, DESTINATION, 0, data, DEFAULT_POLICY_ID, salt);

        MockERC1271NonceConsumedSigner nonceConsumedSigner = new MockERC1271NonceConsumedSigner(address(harness));
        nonceConsumedSigner.setObservedNonce(nonce);

        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        policy.config.initiator.initiatorMember = address(nonceConsumedSigner);
        harness.setMemberStatus(address(nonceConsumedSigner), true);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        bytes memory initiatorSignature = _buildContractSignature(address(nonceConsumedSigner), hex"A1A2");
        bytes memory reviewSignature = _buildContractSignature(address(nonceConsumedSigner), hex"B1B2");

        vm.prank(GUARDIAN);
        // Call: reject transaction where validation checks nonce state during signature recovery.
        harness.rejectAccountTransaction({
            account: account,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: salt,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: reviewSignature,
            proofs: proofs
        });

        // Verify: rejection succeeds, proving nonce was already consumed when validation began.
        assertTrue(harness.getUsedNonce(nonce), "nonce should be consumed");
    }

    /**
     * @dev Verifies successful rejection consumes nonce.
     */
    function test_NMATB_RAT_2_rejectAccountTransaction_success_consumesNonce() public {
        // Setup: build valid auto-reject payload.
        address account = address(0xAC004);
        harness.setDeployedAccount(account, true);
        bytes memory data = abi.encodeWithSelector(bytes4(0x04050607), uint256(4));
        (
            ,
            ValidationProofs memory proofs,
            bytes memory initiatorSignature,
            bytes memory reviewSignature,
            uint256 expiration
        ) = _buildAutoRejectPayload(account, DESTINATION, 0, data, 4, DEFAULT_POLICY_ID);
        uint256 nonce = _computeNonce(account, DESTINATION, 0, data, DEFAULT_POLICY_ID, 4);

        vm.prank(GUARDIAN);
        // Call: execute valid rejection.
        harness.rejectAccountTransaction({
            account: account,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 4,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: reviewSignature,
            proofs: proofs
        });

        // Verify: nonce is marked used after successful rejection.
        assertTrue(harness.getUsedNonce(nonce), "successful rejection must consume nonce");
    }

    /**
     * @dev Verifies expired rejection reverts and rolls back nonce consumption.
     */
    function test_NMATB_RAT_8_rejectAccountTransaction_expiredTransaction_rollsBackNonceUsage() public {
        // Setup: deploy account and build approval/rejection signatures with a past expiration timestamp.
        address account = address(0xAC00E);
        harness.setDeployedAccount(account, true);
        bytes memory data = abi.encodeWithSelector(bytes4(0x0E0F1011), uint256(14));
        uint256 expiration = block.timestamp - 1;
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        bytes memory initiatorSignature = _signInitiatorTx({
            txHarness: address(harness),
            privateKey: INITIATOR_PK_1,
            account: account,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 14,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: true
        });
        bytes memory rejectionSignature = _signInitiatorTx({
            txHarness: address(harness),
            privateKey: INITIATOR_PK_1,
            account: account,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 14,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: false
        });
        uint256 nonce = _computeNonce(account, DESTINATION, 0, data, DEFAULT_POLICY_ID, 14);

        // Verify: expiration failure bubbles from validation and the nonce remains unused.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAccountTransaction.TransactionExpired.selector, expiration, block.timestamp
            )
        );
        vm.prank(GUARDIAN);
        // Call: reject the expired transaction payload.
        harness.rejectAccountTransaction({
            account: account,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 14,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: rejectionSignature,
            proofs: proofs
        });

        // Verify: the reverted expired path must not leave the nonce consumed.
        assertFalse(harness.getUsedNonce(nonce), "expired rejection should roll back nonce consumption");
    }

    /**
     * @dev Verifies replay with a previously used nonce reverts with `NonceAlreadyUsed`.
     */
    function test_OATB_RAT_5_NMATB_RAT_3_rejectAccountTransaction_usedNonce_revertsNonceAlreadyUsed() public {
        // Setup: execute one successful rejection.
        address account = address(0xAC005);
        harness.setDeployedAccount(account, true);
        bytes memory data = abi.encodeWithSelector(bytes4(0x05060708), uint256(5));
        (
            ,
            ValidationProofs memory proofs,
            bytes memory initiatorSignature,
            bytes memory reviewSignature,
            uint256 expiration
        ) = _buildAutoRejectPayload(account, DESTINATION, 0, data, 5, DEFAULT_POLICY_ID);
        uint256 nonce = _computeNonce(account, DESTINATION, 0, data, DEFAULT_POLICY_ID, 5);

        vm.prank(GUARDIAN);
        harness.rejectAccountTransaction({
            account: account,
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

        // Verify: replay should fail with nonce-already-used.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationSignatures.NonceAlreadyUsed.selector, nonce));
        vm.prank(GUARDIAN);
        // Call: replay same rejection payload.
        harness.rejectAccountTransaction({
            account: account,
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

    /**
     * @dev Verifies rejection delegates validation to `validateTransactionRejectionOrRevert`.
     */
    function test_OATB_RAT_6_rejectAccountTransaction_invalidValidationInput_revertsFromValidationLibrary() public {
        // Setup: build payload with empty initiator signature to trigger validation guard.
        address account = address(0xAC006);
        harness.setDeployedAccount(account, true);
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        bytes memory data = abi.encodeWithSelector(bytes4(0x06070809), uint256(6));

        // Verify: rejection validation reverts on empty initiator signature.
        vm.expectRevert(IOrganizationAccountTransaction.InsufficientSignaturesLength.selector);
        vm.prank(GUARDIAN);
        // Call: invoke rejection path with invalid signature input.
        harness.rejectAccountTransaction({
            account: account,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 6,
            expirationTimestamp: block.timestamp + 1 days,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: bytes(""),
            reviewSignatures: bytes(""),
            proofs: proofs
        });
    }

    /**
     * @dev Verifies success emits `AccountTransactionRejected` with expected payload.
     */
    function test_OATB_RAT_7_NMATB_RAT_2_rejectAccountTransaction_success_emitsAccountTransactionRejected() public {
        // Setup: build valid auto-reject payload.
        address account = address(0xAC007);
        harness.setDeployedAccount(account, true);
        bytes memory data = abi.encodeWithSelector(bytes4(0x0708090A), uint256(7));
        (
            ,
            ValidationProofs memory proofs,
            bytes memory initiatorSignature,
            bytes memory reviewSignature,
            uint256 expiration
        ) = _buildAutoRejectPayload(account, DESTINATION, 0, data, 7, DEFAULT_POLICY_ID);
        uint256 nonce = _computeNonce(account, DESTINATION, 0, data, DEFAULT_POLICY_ID, 7);

        vm.expectEmit(true, true, true, true);
        emit IOrganizationAccountTransaction.AccountTransactionRejected(
            account, DESTINATION, 0, data, nonce, DEFAULT_POLICY_ID
        );

        vm.prank(GUARDIAN);
        // Call: execute valid rejection.
        harness.rejectAccountTransaction({
            account: account,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 7,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: reviewSignature,
            proofs: proofs
        });
    }

    /**
     * @dev Verifies execute then reject with identical tuple reverts due to shared nonce space.
     */
    function test_OATB_RAT_8__NMATB_RAT_5__NMATB_RAT_7_rejectAccountTransaction_executeThenRejectSameTuple_revertsNonceAlreadyUsed()
        public
    {
        // Setup: deploy account and build one shared payload tuple.
        MockAccountForOrganizationTransaction account = new MockAccountForOrganizationTransaction(address(harness));
        harness.setDeployedAccount(address(account), true);
        bytes memory data = abi.encodeWithSelector(bytes4(0x08090A0B), uint256(8));
        (
            ,
            ValidationProofs memory proofs,
            bytes memory initiatorSignature,
            bytes memory rejectionSignature,
            uint256 expiration
        ) = _buildAutoRejectPayload(address(account), DESTINATION, 0, data, 8, DEFAULT_POLICY_ID);
        uint256 nonce = _computeNonce(address(account), DESTINATION, 0, data, DEFAULT_POLICY_ID, 8);

        vm.prank(GUARDIAN);
        // Call: execute first to consume nonce.
        harness.executeAccountTransaction({
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 8,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        vm.expectRevert(abi.encodeWithSelector(IOrganizationSignatures.NonceAlreadyUsed.selector, nonce));
        vm.prank(GUARDIAN);
        // Call: reject same tuple after execution.
        harness.rejectAccountTransaction({
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 8,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: rejectionSignature,
            proofs: proofs
        });
    }

    /**
     * @dev Verifies reject then execute with identical tuple reverts due to shared nonce space.
     */
    function test_OATB_RAT_9__NMATB_RAT_4__NMATB_RAT_7_rejectAccountTransaction_rejectThenExecuteSameTuple_revertsNonceAlreadyUsed()
        public
    {
        // Setup: deploy account and build one shared payload tuple.
        MockAccountForOrganizationTransaction account = new MockAccountForOrganizationTransaction(address(harness));
        harness.setDeployedAccount(address(account), true);
        bytes memory data = abi.encodeWithSelector(bytes4(0x090A0B0C), uint256(9));
        (
            ,
            ValidationProofs memory proofs,
            bytes memory initiatorSignature,
            bytes memory rejectionSignature,
            uint256 expiration
        ) = _buildAutoRejectPayload(address(account), DESTINATION, 0, data, 9, DEFAULT_POLICY_ID);
        uint256 nonce = _computeNonce(address(account), DESTINATION, 0, data, DEFAULT_POLICY_ID, 9);

        vm.prank(GUARDIAN);
        // Call: reject first to consume nonce.
        harness.rejectAccountTransaction({
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 9,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: rejectionSignature,
            proofs: proofs
        });

        vm.expectRevert(abi.encodeWithSelector(IOrganizationSignatures.NonceAlreadyUsed.selector, nonce));
        vm.prank(GUARDIAN);
        // Call: execute same tuple after rejection.
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
    }

    /**
     * @dev Verifies failed rejection validation does not burn nonce; fixed retry can succeed.
     */
    function test_OATB_RAT_10__NMATB_RAT_6_rejectAccountTransaction_failedValidationDoesNotBurnNonce_sameSaltCanSucceed()
        public
    {
        // Setup: configure auto-approve rejection where first review signature is unauthorized.
        address account = address(0xAC008);
        harness.setDeployedAccount(account, true);
        bytes memory data = abi.encodeWithSelector(bytes4(0x0A0B0C0D), uint256(10));
        (, ValidationProofs memory proofs, bytes memory initiatorSignature,, uint256 expiration) =
            _buildAutoRejectPayload(account, DESTINATION, 0, data, 10, DEFAULT_POLICY_ID);
        uint256 nonce = _computeNonce(account, DESTINATION, 0, data, DEFAULT_POLICY_ID, 10);

        bytes memory unauthorizedRejectionSig = _signInitiatorTx({
            txHarness: address(harness),
            privateKey: REVIEWER_PK_1,
            account: account,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 10,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: false
        });

        vm.expectRevert(IOrganizationAccountTransaction.TransactionRejectionNotAllowed.selector);
        vm.prank(GUARDIAN);
        // Call: first attempt with unauthorized rejection signer.
        harness.rejectAccountTransaction({
            account: account,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 10,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: unauthorizedRejectionSig,
            proofs: proofs
        });
        assertFalse(harness.getUsedNonce(nonce), "failed validation must not consume nonce");

        bytes memory validRejectionSig = _signInitiatorTx({
            txHarness: address(harness),
            privateKey: INITIATOR_PK_1,
            account: account,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 10,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            isApproval: false
        });

        vm.prank(GUARDIAN);
        // Call: second attempt with authorized rejection signature.
        harness.rejectAccountTransaction({
            account: account,
            to: DESTINATION,
            value: 0,
            data: data,
            salt: 10,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: validRejectionSig,
            proofs: proofs
        });

        // Verify: corrected retry succeeds and consumes nonce.
        assertTrue(harness.getUsedNonce(nonce), "successful retry should consume nonce");
    }

    // Helpers

    /**
     * @dev Builds valid auto-approve rejection payload.
     */
    function _buildAutoRejectPayload(
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
            bytes memory rejectionSignature,
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
        rejectionSignature = _signInitiatorTx({
            txHarness: address(harness),
            privateKey: INITIATOR_PK_1,
            account: account,
            to: to,
            value: value,
            data: data,
            salt: salt,
            expirationTimestamp: expiration,
            policyId: policyId,
            isApproval: false
        });
    }

    /**
     * @dev Extracts nonce from the first `AccountTransactionExecuted` event in recorded logs.
     */
    function _extractExecuteEventNonce(Vm.Log[] memory logs) internal pure returns (uint256) {
        bytes32 topic = IOrganizationAccountTransaction.AccountTransactionExecuted.selector;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == topic) {
                return uint256(logs[i].topics[3]);
            }
        }
        revert("AccountTransactionExecuted event not found");
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
