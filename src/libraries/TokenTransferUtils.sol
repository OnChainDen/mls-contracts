// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ContractInteractionUtils} from "./ContractInteractionUtils.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TokenTransferUtils
 * @dev A library for ERC-20 and native token transfer detection and extraction utilities
 * @author Den Technologies Inc
 */
library TokenTransferUtils {
    /**
     * @dev Thrown when a token transfer transaction is malformed
     */
    error MalformedTokenTransfer();

    /**
     * @dev Checks if a transaction is a token transfer
     * @dev A transaction is considered a token transfer if:
     *      1. It has value > 0 and no data (native token transfer), OR
     *      2. It calls transfer(address,uint256) for ERC-20 transfers
     * @param data The transaction calldata
     * @param value The transaction value in wei
     * @return True if the transaction is a token transfer, false otherwise
     */
    function isTransactionTokenTransfer(bytes calldata data, uint256 value) internal pure returns (bool) {
        // Case: The transaction is a native token transfer
        if (isTransactionNativeTokenTransfer(data, value)) return true;

        // Case: The transaction is an ERC20 token transfer
        if (isTransactionERC20TokenTransfer(data, value)) return true;

        // Case: The transaction is not a token transfer
        return false;
    }

    /**
     * @dev Checks if a transaction is a native token transfer
     * @dev A transaction is considered a native token transfer if it has value > 0 and no data
     * @param data The transaction calldata
     * @param value The transaction value in wei
     * @return True if the transaction is a native token transfer, false otherwise
     */
    function isTransactionNativeTokenTransfer(bytes calldata data, uint256 value) internal pure returns (bool) {
        return data.length == 0 && value > 0;
    }

    /**
     * @notice Checks if a transaction is an ERC20 token transfer
     * @dev A transaction is considered an ERC20 token transfer if it calls transfer(address,uint256)
     *      and has no native value attached
     * @param data The transaction calldata
     * @param value The transaction value in wei
     * @return True if the transaction is an ERC20 token transfer, false otherwise
     */
    // forge-lint: disable-next-line(mixed-case-function)
    function isTransactionERC20TokenTransfer(bytes calldata data, uint256 value) internal pure returns (bool) {
        // Case: The transaction data is too short to call a function
        if (data.length < ContractInteractionUtils.SELECTOR_LENGTH) return false;

        // Case: The transaction has native value attached (not a pure ERC20 transfer)
        if (value > 0) return false;

        // Case: Check if the transaction is calling the `transfer` function
        bytes4 selector = ContractInteractionUtils.extractFunctionSelector(data);
        return selector == IERC20.transfer.selector;
    }

    /**
     * @dev Extracts the token recipient from ERC-20 transfer calldata
     * @dev Only supports ERC20 transfer(address,uint256)
     * @param data The transaction calldata (must be a valid ERC-20 transfer call)
     * @return The recipient address
     */
    // forge-lint: disable-next-line(mixed-case-function)
    function extractERC20TransferRecipient(bytes calldata data) internal pure returns (address) {
        // Case: Transaction data is too short to contain a valid selector
        if (data.length < 36) revert MalformedTokenTransfer();

        bytes4 selector = ContractInteractionUtils.extractFunctionSelector(data);

        // Case: The transaction is calling the `transfer` function
        // transfer(address to, uint256 amount)
        // The recipient is the first parameter after the selector
        if (selector == IERC20.transfer.selector) {
            return address(bytes20(data[16:36]));
        }

        // Case: The transaction is not a valid ERC-20 transfer
        revert MalformedTokenTransfer();
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
     * @dev Extracts the transfer amount from a token transfer
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
