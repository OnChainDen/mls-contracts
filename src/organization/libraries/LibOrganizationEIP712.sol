// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title Lib Organization EIP712
 * @dev Library for EIP-712 typed data hashing for Organization contracts.
 *      Provides shared EIP-712 domain separator computation used across organization libraries.
 * @author Den Technologies Inc
 */
library LibOrganizationEIP712 {
    /// @dev EIP-712 domain separator type hash for typed data signing
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH = keccak256(
        // solhint-disable-next-line max-line-length
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    /// @dev Type hash for admin operation signatures (used for admin authorization)
    bytes32 internal constant ADMIN_OPERATION_TYPEHASH = keccak256(
        // solhint-disable-next-line max-line-length
        "AdminOperation(uint8 operationType,bytes operationData,uint256 salt,uint256 expirationTimestamp,bool isApproval,uint256 chainId,address organization)"
    );

    /// @dev Type hash for initiator signatures on account transactions
    bytes32 internal constant INITIATE_ACCOUNT_TRANSACTION_TYPEHASH = keccak256(
        // solhint-disable-next-line max-line-length
        "InitiateAccountTransaction(address organization,address account,address to,uint256 value,bytes data,uint256 salt,uint256 expirationTimestamp,uint256 policyId,bool isApproval,uint256 chainId)"
    );

    /// @dev Type hash for reviewer signatures on account transactions
    bytes32 internal constant REVIEW_ACCOUNT_TRANSACTION_TYPEHASH = keccak256(
        // solhint-disable-next-line max-line-length
        "ReviewAccountTransaction(address organization,address account,address to,uint256 value,bytes data,uint256 salt,uint256 expirationTimestamp,uint256 policyId,bool isApproval,uint256 chainId,bytes initiatorSignature)"
    );

    /// @dev Type hash for initiator signatures on ERC-1271 signature validation requests
    bytes32 internal constant INITIATE_SIGNATURE_VALIDATION_TYPEHASH = keccak256(
        // solhint-disable-next-line max-line-length
        "InitiateSignatureValidation(address organization,address account,bytes32 hash,uint256 policyId,uint256 expirationTimestamp,uint256 chainId)"
    );

    /// @dev Type hash for reviewer signatures on ERC-1271 signature validation requests
    bytes32 internal constant REVIEW_SIGNATURE_VALIDATION_TYPEHASH = keccak256(
        // solhint-disable-next-line max-line-length
        "ReviewSignatureValidation(address organization,address account,bytes32 hash,uint256 policyId,uint256 expirationTimestamp,uint256 chainId,bytes initiatorSignature)"
    );

    /**
     * @dev Computes the EIP-712 domain separator for this organization.
     *      Used for all EIP-712 typed data hashes in transaction and signature validation.
     * @return The domain separator hash
     */
    function getDomainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256("OnchainCustodyOrganization"),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    /**
     * @dev Computes the EIP-712 typed data hash for this organization.
     *      Wraps the provided struct hash with the Organization's EIP-712 domain separator.
     * @param structHash The EIP-712 struct hash
     * @return The final EIP-712 typed data hash to be signed / verified
     */
    function computeTypedDataHash(bytes32 structHash) internal view returns (bytes32) {
        return MessageHashUtils.toTypedDataHash(getDomainSeparator(), structHash);
    }
}
