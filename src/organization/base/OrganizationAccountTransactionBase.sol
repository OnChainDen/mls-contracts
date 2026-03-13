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
        uint256 nonce = _validateApprovalAndConsumeNonce(
            account, to, value, data, salt, expirationTimestamp, policyId, initiatorSignature, reviewSignatures, proofs
        );

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
        uint256 nonce = _validateRejectionAndConsumeNonce(
            account, to, value, data, salt, expirationTimestamp, policyId, initiatorSignature, reviewSignatures, proofs
        );

        emit AccountTransactionRejected({
            account: account, to: to, value: value, data: data, nonce: nonce, policyId: policyId
        });
    }

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
        // Verify the account is deployed by this organization
        LibOrganizationAccountFactory.validateIsAccountDeployedByOrgOrRevert(account);

        bytes32 dataHash = keccak256(data);
        bytes memory operationData = abi.encode(account, to, value, dataHash, policyId);

        // Compute nonce and consume it before any external execution path.
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
        // Verify the account is deployed by this organization
        LibOrganizationAccountFactory.validateIsAccountDeployedByOrgOrRevert(account);

        bytes32 dataHash = keccak256(data);
        bytes memory operationData = abi.encode(account, to, value, dataHash, policyId);

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
