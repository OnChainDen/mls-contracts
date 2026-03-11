// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {LibOrganizationEIP712} from "organization/libraries/LibOrganizationEIP712.sol";

/**
 * @dev Library-focused harness exposing `LibOrganizationEIP712` helpers.
 */
contract LibOrganizationEIP712Harness {
    /**
     * @dev Exposes `LibOrganizationEIP712.EIP712_DOMAIN_TYPEHASH`.
     * @return typehash The domain-separator type hash constant.
     */
    function getDomainTypehash() external pure returns (bytes32 typehash) {
        return LibOrganizationEIP712.EIP712_DOMAIN_TYPEHASH;
    }

    /**
     * @dev Exposes `LibOrganizationEIP712.ADMIN_OPERATION_TYPEHASH`.
     * @return typehash The admin-operation type hash constant.
     */
    function getAdminOperationTypehash() external pure returns (bytes32 typehash) {
        return LibOrganizationEIP712.ADMIN_OPERATION_TYPEHASH;
    }

    /**
     * @dev Exposes `LibOrganizationEIP712.INITIATE_ACCOUNT_TRANSACTION_TYPEHASH`.
     * @return typehash The initiate-account-transaction type hash constant.
     */
    function getInitiateAccountTransactionTypehash() external pure returns (bytes32 typehash) {
        return LibOrganizationEIP712.INITIATE_ACCOUNT_TRANSACTION_TYPEHASH;
    }

    /**
     * @dev Exposes `LibOrganizationEIP712.REVIEW_ACCOUNT_TRANSACTION_TYPEHASH`.
     * @return typehash The review-account-transaction type hash constant.
     */
    function getReviewAccountTransactionTypehash() external pure returns (bytes32 typehash) {
        return LibOrganizationEIP712.REVIEW_ACCOUNT_TRANSACTION_TYPEHASH;
    }

    /**
     * @dev Exposes `LibOrganizationEIP712.INITIATE_SIGNATURE_VALIDATION_TYPEHASH`.
     * @return typehash The initiate-signature-validation type hash constant.
     */
    function getInitiateSignatureValidationTypehash() external pure returns (bytes32 typehash) {
        return LibOrganizationEIP712.INITIATE_SIGNATURE_VALIDATION_TYPEHASH;
    }

    /**
     * @dev Exposes `LibOrganizationEIP712.REVIEW_SIGNATURE_VALIDATION_TYPEHASH`.
     * @return typehash The review-signature-validation type hash constant.
     */
    function getReviewSignatureValidationTypehash() external pure returns (bytes32 typehash) {
        return LibOrganizationEIP712.REVIEW_SIGNATURE_VALIDATION_TYPEHASH;
    }

    /**
     * @dev Exposes `LibOrganizationEIP712.getDomainSeparator`.
     * @return domainSeparator The current EIP-712 domain separator for this harness.
     */
    function getDomainSeparatorViaLibrary() external view returns (bytes32 domainSeparator) {
        return LibOrganizationEIP712.getDomainSeparator();
    }

    /**
     * @dev Exposes `LibOrganizationEIP712.computeTypedDataHash`.
     * @param structHash The EIP-712 struct hash to wrap.
     * @return typedDataHash The final typed-data hash.
     */
    function computeTypedDataHashViaLibrary(bytes32 structHash) external view returns (bytes32 typedDataHash) {
        return LibOrganizationEIP712.computeTypedDataHash(structHash);
    }
}
