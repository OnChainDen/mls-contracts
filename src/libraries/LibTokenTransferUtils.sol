// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title LibTokenTransferUtils
 * @notice A library for ERC-20 and native token transfer detection and extraction utilities
 * @author Den Technologies Inc
 */
library LibTokenTransferUtils {
    /**
     * @notice Thrown when a token transfer transaction is malformed
     */
    error MalformedTokenTransfer();

    /**
     * @notice Checks if a transaction is a token transfer
     * @dev A transaction is considered a token transfer if:
     *      1. It has value > 0 and no data (native token transfer), OR
     *      2. It calls transfer(address,uint256) or transferFrom(address,address,uint256)
     * @param data The transaction calldata
     * @param value The transaction value in wei
     * @return True if the transaction is a token transfer, false otherwise
     */
    function isTransactionTokenTransfer(bytes calldata data, uint256 value) internal pure returns (bool) {
        // Case: The transaction is a native token transfer
        if (data.length == 0 && value > 0) return true;

        // Case: The transaction data is too short to call a function
        if (data.length < 4) return false;

        // Case: The transaction is not a native token transfer, but the value is greater than zero
        if (value > 0) return false;

        // Case: The transaction is a token transfer
        bytes4 selector = bytes4(data[:4]);

        // Case: The transaction is a token transfer
        if (
            selector == bytes4(keccak256("transfer(address,uint256)"))
                || selector == bytes4(keccak256("transferFrom(address,address,uint256)"))
        ) {
            return true;
        }

        // Case: The transaction is not a token transfer
        return false;
    }

    /**
     * @notice Extracts the token recipient from token transfer calldata
     * @dev Supports ERC20 transfer(address,uint256) and transferFrom(address,address,uint256)
     * @param data The transaction calldata
     * @return The recipient address, or address(0) if not a valid token transfer
     */
    function extractTransferRecipient(bytes calldata data) internal pure returns (address) {
        // Case: Transaction data is too short to contain a valid selector
        if (data.length < 36) return address(0);

        bytes4 selector = bytes4(data[:4]);

        // Case: The transaction is calling the `transfer` function
        // transfer(address to, uint256 amount)
        // The recipient is the first parameter after the selector
        if (selector == bytes4(keccak256("transfer(address,uint256)"))) {
            return address(bytes20(data[16:36]));
        }

        // Case: The transaction is calling the `transferFrom` function
        // transferFrom(address from, address to, uint256 amount)
        // Note: The recipient is the second address parameter after the selector
        if (selector == bytes4(keccak256("transferFrom(address,address,uint256)"))) {
            // Case: Transaction data is too short to contain a valid recipient
            if (data.length < 68) return address(0);
            return address(bytes20(data[48:68]));
        }

        // Case: The transaction is not a valid ERC-20 transfer
        return address(0);
    }

    /**
     * @notice Extracts the token contract address from a token transfer
     * @dev For ERC20 transfers, the token contract is the `to` address.
     *      For native transfers, returns address(0).
     * @param to The transaction `to` address
     * @param data The transaction calldata
     * @return The token contract address
     */
    function extractTokenAddress(address to, bytes calldata data) internal pure returns (address) {
        if (data.length == 0) {
            return address(0); // Native token
        }
        return to; // ERC20 token address
    }

    /**
     * @notice Extracts the transfer amount from a token transfer
     * @dev For native transfers, returns the transaction value.
     *      For ERC20 transfers, extracts the amount from calldata.
     * @param data The transaction calldata
     * @param value The transaction value in wei
     * @return The transfer amount
     */
    function extractTransferAmount(bytes calldata data, uint256 value) internal pure returns (uint256) {
        // Case: The transaction is a native token transfer
        if (data.length == 0) return value;

        // Case: The ERC-20 transaction is malformed
        // Note: 4 bytes selector + 32 bytes address + 32 bytes amount = 68 bytes
        if (data.length < 68) revert MalformedTokenTransfer();

        // Case: The ERC-20 transaction is transferring a non-zero value
        // ERC20 transfer - amount is second parameter (offset 36-68)
        return uint256(bytes32(data[36:68]));
    }
}
