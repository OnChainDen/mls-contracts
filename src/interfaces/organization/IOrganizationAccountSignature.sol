// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IOrganizationAccountSignature
 * @notice Interface for validating ERC-1271 signatures on behalf of accounts
 * @dev Maps to LibOrganizationAccountSignature library functionality
 * @author Den Technologies Inc
 */
interface IOrganizationAccountSignature {
    /**
     * @notice Validates an ERC-1271 signature for a given account
     * @dev Note: Time-based policy limits are NOT supported for ERC-1271 signatures because the standard
     *      requires isValidSignature to be a view function (cannot modify storage to track usage).
     * @param account The account address on behalf of which the signature is being validated
     * @param hash The hash that was signed
     * @param signature The signature to validate (encoded with policyId, approver signatures, guardian signature)
     * @return magicValue 0x1626ba7e if valid, 0xffffffff otherwise
     */
    function isValidSignatureForAccount(address account, bytes32 hash, bytes calldata signature)
        external
        view
        returns (bytes4 magicValue);
}
