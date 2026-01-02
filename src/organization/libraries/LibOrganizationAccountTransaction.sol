// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { LibOrganizationPolicy } from "./LibOrganizationPolicy.sol";
import { LibOrganizationSignatures } from "./LibOrganizationSignatures.sol";
import { Policies } from "../../libraries/Policies.sol";
import { SignatureUtils } from "../../libraries/SignatureUtils.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title Lib Organization Account Transaction
 * @notice Library for validating account transactions through the Organization contract
 * @dev Policies are verified via merkle proofs. Policy data is provided in calldata.
 * @author Den Technologies Inc
 */
library LibOrganizationAccountTransaction {
    /// @notice Struct to reduce stack depth when passing transaction params
    struct TxParams {
        address account;
        address to;
        uint256 value;
        uint256 salt;
        uint256 expirationTimestamp;
        uint256 policyId;
    }

    error TransactionRejectedByPolicy(string reason);
    error TransactionRejectionNotAllowed(string reason);
    error InsufficientApprovals(uint256 required, uint256 provided);
    error PolicyVerificationFailed(uint256 policyId);
    error PolicyDoesNotApply(uint256 policyId);
    error TransactionExpired(uint256 expirationTimestamp, uint256 currentTimestamp);
    error InvalidInitiatorSignature();
    error InsufficientSignaturesLength();
    error TimeBasedLimitExceeded(uint256 policyId);

    /**
     * @notice Validates a transaction against the specified policy using merkle proofs
     */
    function validateTransactionApproval(
        address account,
        address to,
        uint256 value,
        bytes calldata data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bytes memory signatures,
        Policies.ValidationProofs calldata proofs
    )
        internal
    {
        if (block.timestamp > expirationTimestamp) {
            revert TransactionExpired(expirationTimestamp, block.timestamp);
        }

        if (signatures.length < 65) {
            revert InsufficientSignaturesLength();
        }

        TxParams memory params = TxParams({
            account: account,
            to: to,
            value: value,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            policyId: policyId
        });

        bytes memory initiatorSignature = SignatureUtils.extractSignature(signatures, 0);
        address initiator = _recoverInitiatorFromParams(params, data, initiatorSignature);

        if (!LibOrganizationPolicy.doesPolicyApplyToTransaction(policyId, account, to, value, data, initiator, proofs))
        {
            revert PolicyDoesNotApply(policyId);
        }

        _processApproval(params, data, signatures, initiatorSignature, initiator, proofs);
    }

    function _recoverInitiatorFromParams(
        TxParams memory params,
        bytes calldata data,
        bytes memory initiatorSignature
    )
        private
        view
        returns (address)
    {
        bytes32 initiatorTxHash = _computeInitiatorHashFromParams(params, data, true);
        address initiator = ECDSA.recover(initiatorTxHash, initiatorSignature);
        if (initiator == address(0)) {
            revert InvalidInitiatorSignature();
        }
        return initiator;
    }

    function _processApproval(
        TxParams memory params,
        bytes calldata data,
        bytes memory signatures,
        bytes memory initiatorSignature,
        address initiator,
        Policies.ValidationProofs calldata proofs
    )
        private
    {
        Policies.PolicyType pType = proofs.policy.config.approval.policyType;

        if (pType == Policies.PolicyType.AutoApprove) {
            _updateTimeLimitForAutoApprove(params, data, initiator, proofs.policy);
            return;
        }

        if (pType == Policies.PolicyType.RequireManualApproval) {
            _validateAndUpdateManualApproval(params, data, signatures, initiatorSignature, initiator, proofs);
        }
    }

    function _updateTimeLimitForAutoApprove(
        TxParams memory params,
        bytes calldata data,
        address initiator,
        Policies.Policy calldata policy
    )
        private
    {
        if (policy.config.timeLimit.limitation != Policies.PolicyLimitation.TimeInterval) {
            return;
        }

        address destination = LibOrganizationPolicy.getActualDestination(params.to, data, params.value);

        uint256 usageAmount;
        if (policy.config.transactionType == Policies.TransactionType.TokenTransfers) {
            usageAmount = LibOrganizationPolicy.extractTransferAmount(data, params.value);
        } else {
            usageAmount = 1;
        }

        bool withinLimit = LibOrganizationPolicy.checkAndUpdateTimeBasedLimit(
            params.policyId, policy, params.account, destination, initiator, usageAmount
        );

        if (!withinLimit) {
            revert TimeBasedLimitExceeded(params.policyId);
        }
    }

    function _validateAndUpdateManualApproval(
        TxParams memory params,
        bytes calldata data,
        bytes memory signatures,
        bytes memory initiatorSignature,
        address initiator,
        Policies.ValidationProofs calldata proofs
    )
        private
    {
        uint256 requiredApprovals = LibOrganizationPolicy.getRequiredApprovals(proofs.policy);

        bytes memory reviewSignatures = LibOrganizationSignatures.extractReviewSignatures(signatures);

        bytes32 reviewTxHash = _computeReviewHashFromParams(params, data, true, initiatorSignature);

        uint256 validApprovals = LibOrganizationPolicy.getValidApprovals(proofs.policy, reviewSignatures, reviewTxHash);

        if (validApprovals < requiredApprovals) {
            revert InsufficientApprovals(requiredApprovals, validApprovals);
        }

        _updateTimeLimitForAutoApprove(params, data, initiator, proofs.policy);
    }

    /**
     * @notice Validates that the caller is authorized to reject the given transaction
     */
    function validateTransactionRejection(
        address account,
        address to,
        uint256 value,
        bytes calldata data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bytes memory signatures,
        Policies.ValidationProofs calldata proofs
    )
        internal
        view
    {
        if (block.timestamp > expirationTimestamp) {
            revert TransactionExpired(expirationTimestamp, block.timestamp);
        }

        if (signatures.length < 65) {
            revert InsufficientSignaturesLength();
        }

        TxParams memory params = TxParams({
            account: account,
            to: to,
            value: value,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            policyId: policyId
        });

        bytes memory initiatorSignature = SignatureUtils.extractSignature(signatures, 0);
        address initiator = _recoverInitiatorFromParams(params, data, initiatorSignature);

        if (!LibOrganizationPolicy.doesPolicyApplyToTransaction(policyId, account, to, value, data, initiator, proofs))
        {
            revert PolicyDoesNotApply(policyId);
        }

        _processRejection(params, data, signatures, initiatorSignature, proofs);
    }

    function _processRejection(
        TxParams memory params,
        bytes calldata data,
        bytes memory signatures,
        bytes memory initiatorSignature,
        Policies.ValidationProofs calldata proofs
    )
        private
        view
    {
        Policies.PolicyType pType = proofs.policy.config.approval.policyType;

        if (pType == Policies.PolicyType.AutoApprove) {
            _validateAutoApproveRejection(params, data, signatures, proofs);
            return;
        }

        if (pType == Policies.PolicyType.RequireManualApproval) {
            _validateManualRejection(params, data, signatures, initiatorSignature, proofs);
        }
    }

    function _validateAutoApproveRejection(
        TxParams memory params,
        bytes calldata data,
        bytes memory signatures,
        Policies.ValidationProofs calldata proofs
    )
        private
        view
    {
        bytes32 rejectionTxHash = _computeInitiatorHashFromParams(params, data, false);

        if (signatures.length < 130) {
            revert TransactionRejectionNotAllowed("AutoApprove rejection requires authorized initiator signature");
        }
        bytes memory rejectionSignature = SignatureUtils.extractSignature(signatures, 1);

        address rejectionSigner = ECDSA.recover(rejectionTxHash, rejectionSignature);
        if (!LibOrganizationPolicy.doesTransactionMatchPolicyInitiator(proofs.policy, rejectionSigner)) {
            revert TransactionRejectionNotAllowed("Rejection signature must be from an authorized initiator");
        }
    }

    function _validateManualRejection(
        TxParams memory params,
        bytes calldata data,
        bytes memory signatures,
        bytes memory initiatorSignature,
        Policies.ValidationProofs calldata proofs
    )
        private
        view
    {
        uint256 requiredApprovals = LibOrganizationPolicy.getRequiredApprovals(proofs.policy);

        bytes memory reviewSignatures = LibOrganizationSignatures.extractReviewSignatures(signatures);

        bytes32 reviewTxHash = _computeReviewHashFromParams(params, data, false, initiatorSignature);

        uint256 validApprovals = LibOrganizationPolicy.getValidApprovals(proofs.policy, reviewSignatures, reviewTxHash);

        if (validApprovals < requiredApprovals) {
            revert InsufficientApprovals(requiredApprovals, validApprovals);
        }
    }

    function _computeInitiatorHashFromParams(
        TxParams memory params,
        bytes calldata data,
        bool isApproval
    )
        private
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "InitiateAccountTransaction(address organization,address account,address to,uint256 value,bytes data,uint256 salt,uint256 expirationTimestamp,uint256 policyId,bool isApproval,uint256 chainId)"
                ),
                address(this),
                params.account,
                params.to,
                params.value,
                keccak256(data),
                params.salt,
                params.expirationTimestamp,
                params.policyId,
                isApproval,
                block.chainid
            )
        );

        return MessageHashUtils.toTypedDataHash(_getDomainSeparator(), structHash);
    }

    function _computeReviewHashFromParams(
        TxParams memory params,
        bytes calldata data,
        bool isApproval,
        bytes memory initiatorSignature
    )
        private
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "ReviewAccountTransaction(address organization,address account,address to,uint256 value,bytes data,uint256 salt,uint256 expirationTimestamp,uint256 policyId,bool isApproval,uint256 chainId,bytes initiatorSignature)"
                ),
                address(this),
                params.account,
                params.to,
                params.value,
                keccak256(data),
                params.salt,
                params.expirationTimestamp,
                params.policyId,
                isApproval,
                block.chainid,
                keccak256(initiatorSignature)
            )
        );

        return MessageHashUtils.toTypedDataHash(_getDomainSeparator(), structHash);
    }

    function _getDomainSeparator() private view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("OnchainCustodyOrganization"),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }
}
