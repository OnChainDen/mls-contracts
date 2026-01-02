// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { LibOrganizationPolicy } from "./LibOrganizationPolicy.sol";
import { LibOrganizationGuardian } from "./LibOrganizationGuardian.sol";
import { LibOrganizationSignatures } from "./LibOrganizationSignatures.sol";
import { Policies } from "../../libraries/Policies.sol";
import { SignatureUtils } from "../../libraries/SignatureUtils.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title Lib Organization Account Signature
 * @notice Library for validating ERC-1271 signatures through the Organization contract
 * @dev Policy existence is verified via merkle proof. Policy data is provided in calldata.
 * @author Den Technologies Inc
 */
library LibOrganizationAccountSignature {
    bytes4 internal constant ERC1271_MAGIC_VALUE = 0x1626ba7e;
    bytes4 internal constant ERC1271_INVALID_VALUE = 0xffffffff;

    /**
     * @notice Validates an ERC-1271 signature for a given account
     */
    function isValidSignature(
        address account,
        bytes32 hash,
        bytes memory signature
    )
        internal
        view
        returns (bytes4 magicValue)
    {
        (
            uint256 policyId,
            uint256 expirationTimestamp,
            bytes memory approverSignatures,
            bytes memory guardianSignature,
            Policies.ValidationProofs memory proofs
        ) = abi.decode(signature, (uint256, uint256, bytes, bytes, Policies.ValidationProofs));

        if (block.timestamp > expirationTimestamp) {
            return ERC1271_INVALID_VALUE;
        }

        if (!_verifyGuardianSignature(account, hash, policyId, expirationTimestamp, guardianSignature)) {
            return ERC1271_INVALID_VALUE;
        }

        if (!LibOrganizationPolicy.policyExistsMemory(policyId, proofs.policy, proofs.policyProof)) {
            return ERC1271_INVALID_VALUE;
        }

        if (proofs.policy.config.transactionType != Policies.TransactionType.Signatures) {
            return ERC1271_INVALID_VALUE;
        }

        if (!_doesPolicyApplyToAccount(proofs.policy, account, proofs.sourceAccountProof)) {
            return ERC1271_INVALID_VALUE;
        }

        // Continue validation in separate function to reduce stack depth
        return _validateSignatures(account, hash, policyId, expirationTimestamp, approverSignatures, proofs);
    }

    function _validateSignatures(
        address account,
        bytes32 hash,
        uint256 policyId,
        uint256 expirationTimestamp,
        bytes memory approverSignatures,
        Policies.ValidationProofs memory proofs
    )
        private
        view
        returns (bytes4)
    {
        if (approverSignatures.length < 65) {
            return ERC1271_INVALID_VALUE;
        }

        bytes memory initiatorSignature = SignatureUtils.extractSignature(approverSignatures, 0);

        bytes32 initiatorHash = _getInitiatorSignatureHash(account, hash, policyId, expirationTimestamp);

        address initiator = ECDSA.recover(initiatorHash, initiatorSignature);
        if (initiator == address(0)) {
            return ERC1271_INVALID_VALUE;
        }

        if (!LibOrganizationPolicy.doesTransactionMatchPolicyInitiatorMemory(proofs.policy, initiator)) {
            return ERC1271_INVALID_VALUE;
        }

        return _checkPolicyType(
            account, hash, policyId, expirationTimestamp, approverSignatures, initiatorSignature, proofs
        );
    }

    function _checkPolicyType(
        address account,
        bytes32 hash,
        uint256 policyId,
        uint256 expirationTimestamp,
        bytes memory approverSignatures,
        bytes memory initiatorSignature,
        Policies.ValidationProofs memory proofs
    )
        private
        view
        returns (bytes4)
    {
        Policies.PolicyType pType = proofs.policy.config.approval.policyType;

        if (pType == Policies.PolicyType.AutoApprove) {
            return ERC1271_MAGIC_VALUE;
        }

        if (pType == Policies.PolicyType.RequireManualApproval) {
            return _validateManualApproval(
                account, hash, policyId, expirationTimestamp, approverSignatures, initiatorSignature, proofs
            );
        }

        return ERC1271_INVALID_VALUE;
    }

    function _validateManualApproval(
        address account,
        bytes32 hash,
        uint256 policyId,
        uint256 expirationTimestamp,
        bytes memory approverSignatures,
        bytes memory initiatorSignature,
        Policies.ValidationProofs memory proofs
    )
        private
        view
        returns (bytes4)
    {
        uint256 requiredApprovals = LibOrganizationPolicy.getRequiredApprovalsMemory(proofs.policy);

        bytes memory reviewSignatures = LibOrganizationSignatures.extractReviewSignatures(approverSignatures);

        bytes32 reviewHash = _getReviewSignatureHash(account, hash, policyId, expirationTimestamp, initiatorSignature);

        uint256 validApprovals =
            LibOrganizationPolicy.getValidApprovalsMemory(proofs.policy, reviewSignatures, reviewHash);

        if (validApprovals >= requiredApprovals) {
            return ERC1271_MAGIC_VALUE;
        }

        return ERC1271_INVALID_VALUE;
    }

    function _doesPolicyApplyToAccount(
        Policies.Policy memory policy,
        address account,
        bytes32[] memory sourceAccountProof
    )
        private
        pure
        returns (bool)
    {
        if (policy.config.anySourceAccount) return true;

        bytes32 accountLeaf = keccak256(bytes.concat(keccak256(abi.encode(account))));
        return MerkleProof.verify(sourceAccountProof, policy.roots.sourceAccountsRoot, accountLeaf);
    }

    function _verifyGuardianSignature(
        address account,
        bytes32 hash,
        uint256 policyId,
        uint256 expirationTimestamp,
        bytes memory guardianSignature
    )
        private
        view
        returns (bool)
    {
        address guardianAddress = LibOrganizationGuardian.guardian();

        bytes32 guardianMessageHash = _getInitiatorSignatureHash(account, hash, policyId, expirationTimestamp);

        return SignatureChecker.isValidSignatureNow(guardianAddress, guardianMessageHash, guardianSignature);
    }

    function _getInitiatorSignatureHash(
        address account,
        bytes32 hash,
        uint256 policyId,
        uint256 expirationTimestamp
    )
        private
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "InitiateSignatureValidation(address organization,address account,bytes32 hash,uint256 policyId,uint256 expirationTimestamp,uint256 chainId)"
                ),
                address(this),
                account,
                hash,
                policyId,
                expirationTimestamp,
                block.chainid
            )
        );

        return MessageHashUtils.toTypedDataHash(_getDomainSeparator(), structHash);
    }

    function _getReviewSignatureHash(
        address account,
        bytes32 hash,
        uint256 policyId,
        uint256 expirationTimestamp,
        bytes memory initiatorSignature
    )
        private
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "ReviewSignatureValidation(address organization,address account,bytes32 hash,uint256 policyId,uint256 expirationTimestamp,uint256 chainId,bytes initiatorSignature)"
                ),
                address(this),
                account,
                hash,
                policyId,
                expirationTimestamp,
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
