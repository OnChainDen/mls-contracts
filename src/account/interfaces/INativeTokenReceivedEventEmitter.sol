// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Native Token Received Event Emitter Interface
 * @notice An interface to a contract that emits an event when native tokens are received
 * @author Den Technologies Inc
 */
interface INativeTokenReceivedEventEmitter {
    /**
     * @notice Native tokens were received
     * @param sender The address that sent the tokens
     * @param value The native token value that was received
     */
    event OnchainCustodyAccountNativeTokenReceived(address indexed sender, uint256 value);

    /**
     * @notice Receive fallback function triggered when native tokens are received
     * @dev Emits an event with information about the sender and amount received
     */
    receive() external payable;
}
