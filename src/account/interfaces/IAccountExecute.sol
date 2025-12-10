// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IAccountExecute
 * @notice Interface for the Account contract's execute function
 * @author Den Technologies Inc
 */
interface IAccountExecute {
    function executeTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint256 nonce,
        uint256 policyId
    )
        external;
}
