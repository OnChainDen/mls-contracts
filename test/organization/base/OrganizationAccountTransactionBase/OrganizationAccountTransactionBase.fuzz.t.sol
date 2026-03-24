// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAccountTransaction} from "interfaces/organization/IOrganizationAccountTransaction.sol";
import {IOrganizationSignatures} from "interfaces/organization/IOrganizationSignatures.sol";
import {
    MockAccountForOrganizationTransaction
} from "test/organization/base/OrganizationAccountTransactionBase/OrganizationAccountTransactionBaseMocks.sol";
import {
    OrganizationAccountTransactionBaseSuiteBase
} from "test/organization/base/OrganizationAccountTransactionBase/OrganizationAccountTransactionBaseSuiteBase.sol";
import {OperationType} from "types/CommonTypes.sol";
import {Policy, PolicyType, TransactionType, ValidationProofs} from "types/PolicyTypes.sol";

/**
 * @dev Fuzz tests for `OrganizationAccountTransactionBase`.
 */
contract OrganizationAccountTransactionBaseFuzzTest is OrganizationAccountTransactionBaseSuiteBase {
    /**
     * @dev Verifies `OrganizationAccountTransactionBase.executeAccountTransaction` consumes the nonce before the
     *      account can reenter and replay the same tuple.
     * @param saltRaw Raw salt used to derive a bounded replay-domain salt
     * @param payloadArg Fuzzed payload argument used to vary calldata while keeping the replay tuple exact
     */
    function testFuzz_executeAccountTransaction_reentrantReplayFailsAfterNonceConsumption(
        uint256 saltRaw,
        uint256 payloadArg
    ) public {
        uint256 salt = bound(saltRaw, 1, type(uint256).max);

        // Setup: make the account itself the guardian, then configure a nested replay with the exact same tuple and
        // signatures.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        harness.setGuardian(address(account));

        bytes memory data = abi.encodeWithSelector(bytes4(0xDEADBEEF), payloadArg);
        (, ValidationProofs memory proofs, bytes memory initiatorSignature, uint256 expiration) =
            _buildAutoApprovePayload(address(account), DESTINATION, 0, data, salt, DEFAULT_POLICY_ID);
        uint256 nonce = _computeNonce(address(account), DESTINATION, 0, data, DEFAULT_POLICY_ID, salt);

        bytes memory reentrantCallData = abi.encodeCall(
            IOrganizationAccountTransaction.executeAccountTransaction,
            (
                address(account),
                DESTINATION,
                0,
                data,
                salt,
                expiration,
                DEFAULT_POLICY_ID,
                initiatorSignature,
                bytes(""),
                proofs
            )
        );
        account.setReentrantCallData(reentrantCallData);

        // Call: execute the outer transaction from the account/guardian so the nested replay occurs in-flight.
        vm.prank(address(account));
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

        // Verify: the outer execution succeeds once, while the nested replay fails with `NonceAlreadyUsed`.
        assertTrue(harness.getUsedNonce(nonce), "outer execution should consume the nonce before account reentry");
        assertEq(account.executionCount(), 1, "outer account call should execute exactly once");
        assertEq(
            account.reentrantRevertData(),
            abi.encodeWithSelector(IOrganizationSignatures.NonceAlreadyUsed.selector, nonce),
            "nested replay should fail with the already-consumed nonce"
        );
    }

    /**
     * @dev Deploys a mock account and marks it as organization-deployed for base entrypoint tests.
     * @return account The deployed mock account
     */
    function _deployMockAccount() internal returns (MockAccountForOrganizationTransaction account) {
        account = new MockAccountForOrganizationTransaction(address(harness));
        harness.setDeployedAccount(address(account), true);
    }

    /**
     * @dev Builds valid auto-approve proofs and initiator signature for one account-transaction tuple.
     * @param account Source account bound into the signed tuple
     * @param to Destination bound into the signed tuple
     * @param value Native value bound into the signed tuple
     * @param data Calldata bound into the signed tuple
     * @param salt Replay-protection salt bound into the signed tuple
     * @param policyId Policy identifier bound into the signed tuple
     * @return policy The configured auto-approve policy
     * @return proofs The proof bundle for `policyId`
     * @return initiatorSignature The valid initiator approval signature for the tuple
     * @return expiration Expiration timestamp bound into the signature
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
     * @dev Computes the account-transaction nonce for one exact `(account,to,value,keccak256(data),policyId,salt)`
     *      tuple.
     * @param account Source account bound into the tuple
     * @param to Destination bound into the tuple
     * @param value Native value bound into the tuple
     * @param data Calldata bound into the tuple
     * @param policyId Policy identifier bound into the tuple
     * @param salt Replay-protection salt bound into the tuple
     * @return nonce The derived organization nonce for the tuple
     */
    function _computeNonce(
        address account,
        address to,
        uint256 value,
        bytes memory data,
        uint256 policyId,
        uint256 salt
    ) internal view returns (uint256 nonce) {
        bytes memory operationData = abi.encode(account, to, value, keccak256(data), policyId);
        return harness.computeNonce(OperationType.AccountTransaction, operationData, salt);
    }
}
