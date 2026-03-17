// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IAccount} from "interfaces/IAccount.sol";
import {IOrganizationAccountTransaction} from "interfaces/organization/IOrganizationAccountTransaction.sol";
import {OrganizationModifiers} from "organization/common/OrganizationModifiers.sol";
import {LibOrganizationAccountFactory} from "organization/libraries/LibOrganizationAccountFactory.sol";
import {LibOrganizationAccountTransaction} from "organization/libraries/LibOrganizationAccountTransaction.sol";
import {LibOrganizationSignatures} from "organization/libraries/LibOrganizationSignatures.sol";
import {OperationType} from "types/CommonTypes.sol";
import {ValidationProofs} from "types/PolicyTypes.sol";

/**
 * @title OrganizationAccountTransactionBase
 * @dev Abstract contract implementing IOrganizationAccountTransaction.
 *      Handles account transaction execution and rejection.
 * @author Den Technologies Inc
 */
abstract contract OrganizationAccountTransactionBase is OrganizationModifiers, IOrganizationAccountTransaction {
    /// @inheritdoc IOrganizationAccountTransaction
    function executeAccountTransaction(
        address account,
        address to,
        uint256 value,
        bytes calldata data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bytes calldata initiatorSignature,
        bytes calldata reviewSignatures,
        ValidationProofs calldata proofs
    ) external override onlyGuardian {
        uint256 nonce = _validateApprovalAndConsumeNonce({
            account: account,
            to: to,
            value: value,
            data: data,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            policyId: policyId,
            initiatorSignature: initiatorSignature,
            reviewSignatures: reviewSignatures,
            proofs: proofs
        });

        // Emit event before external call (CEI pattern) - if execution fails, transaction reverts
        emit AccountTransactionExecuted({
            account: account, to: to, value: value, data: data, nonce: nonce, policyId: policyId
        });

        // Execute the transaction on the account
        // forgefmt: disable-next-item
        IAccount(payable(account)).executeTransaction({
            to: to,
            value: value,
            data: data,
            nonce: nonce,
            policyId: policyId
        });
    }

    /// @inheritdoc IOrganizationAccountTransaction
    function rejectAccountTransaction(
        address account,
        address to,
        uint256 value,
        bytes calldata data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bytes calldata initiatorSignature,
        bytes calldata reviewSignatures,
        ValidationProofs calldata proofs
    ) external override onlyGuardian {
        uint256 nonce = _validateRejectionAndConsumeNonce({
            account: account,
            to: to,
            value: value,
            data: data,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            policyId: policyId,
            initiatorSignature: initiatorSignature,
            reviewSignatures: reviewSignatures,
            proofs: proofs
        });

        emit AccountTransactionRejected({
            account: account, to: to, value: value, data: data, nonce: nonce, policyId: policyId
        });
    }

    /**
     * @dev Validates approval signatures for an account transaction and consumes its nonce.
     *      Hashes `data` before encoding the operation payload to keep nonce derivation aligned with
     *      the transaction-validation library while reducing stack pressure in the caller.
     * @param account The organization account that will execute the transaction
     * @param to The destination address of the transaction
     * @param value The amount of native token to transfer with the transaction
     * @param data The calldata to execute on the destination address
     * @param salt The user-provided salt used for nonce derivation
     * @param expirationTimestamp The timestamp after which the transaction signatures are invalid
     * @param policyId The policy ID governing the transaction
     * @param initiatorSignature The initiator signature authorizing the transaction
     * @param reviewSignatures The reviewer signatures authorizing the transaction
     * @param proofs The validation proofs used to verify the transaction policy
     * @return nonce The consumed nonce derived for the transaction
     */
    function _validateApprovalAndConsumeNonce(
        address account,
        address to,
        uint256 value,
        bytes calldata data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bytes calldata initiatorSignature,
        bytes calldata reviewSignatures,
        ValidationProofs calldata proofs
    ) internal returns (uint256 nonce) {
        // Ensure the target account was deployed by this organization before deriving the nonce.
        LibOrganizationAccountFactory.validateIsAccountDeployedByOrgOrRevert(account);

        // Encode the same operation payload used by signature validation while keeping local stack usage low.
        bytes32 dataHash = keccak256(data);
        bytes memory operationData = abi.encode(account, to, value, dataHash, policyId);

        // Consume the nonce before the caller reaches any execution path that can perform external work.
        nonce = LibOrganizationSignatures.computeNonce(OperationType.AccountTransaction, operationData, salt);
        LibOrganizationSignatures.validateAndConsumeNonceOrRevert(nonce);

        LibOrganizationAccountTransaction.validateTransactionApprovalOrRevert({
            account: account,
            to: to,
            value: value,
            data: data,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            policyId: policyId,
            initiatorSignature: initiatorSignature,
            reviewSignatures: reviewSignatures,
            proofs: proofs
        });
    }

    /**
     * @dev Validates rejection signatures for an account transaction and consumes its nonce.
     *      Uses the same hashed operation payload as approval validation so approvals and rejections
     *      derive an identical nonce for the same transaction intent.
     * @param account The organization account for which the transaction is being rejected
     * @param to The destination address of the transaction
     * @param value The amount of native token to transfer with the transaction
     * @param data The calldata of the transaction being rejected
     * @param salt The user-provided salt used for nonce derivation
     * @param expirationTimestamp The timestamp after which the transaction signatures are invalid
     * @param policyId The policy ID governing the transaction
     * @param initiatorSignature The initiator signature from the original transaction
     * @param reviewSignatures The reviewer signatures authorizing the rejection
     * @param proofs The validation proofs used to verify the transaction policy
     * @return nonce The consumed nonce derived for the transaction
     */
    function _validateRejectionAndConsumeNonce(
        address account,
        address to,
        uint256 value,
        bytes calldata data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bytes calldata initiatorSignature,
        bytes calldata reviewSignatures,
        ValidationProofs calldata proofs
    ) internal returns (uint256 nonce) {
        // Ensure the target account was deployed by this organization before deriving the nonce.
        LibOrganizationAccountFactory.validateIsAccountDeployedByOrgOrRevert(account);

        // Reuse the same operation payload shape as approvals so both flows target the same nonce.
        bytes32 dataHash = keccak256(data);
        bytes memory operationData = abi.encode(account, to, value, dataHash, policyId);

        // Consume the nonce before returning control to the caller.
        nonce = LibOrganizationSignatures.computeNonce(OperationType.AccountTransaction, operationData, salt);
        LibOrganizationSignatures.validateAndConsumeNonceOrRevert(nonce);

        LibOrganizationAccountTransaction.validateTransactionRejectionOrRevert({
            account: account,
            to: to,
            value: value,
            data: data,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            policyId: policyId,
            initiatorSignature: initiatorSignature,
            reviewSignatures: reviewSignatures,
            proofs: proofs
        });
    }
}
