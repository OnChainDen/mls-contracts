// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { LibAccountOrganizationAddressStorage } from "./libraries/storage/LibAccountOrganizationAddressStorage.sol";
import { INativeTokenReceivedEventEmitter } from "./interfaces/INativeTokenReceivedEventEmitter.sol";

/**
 * @title Account Implementation
 * @notice Implementation contract for Account (used with BeaconProxy)
 * @dev This contract is used behind a BeaconProxy where the Organization acts as the beacon.
 *      Upgrades are handled by the beacon (Organization), not by this contract directly.
 * @author Den Technologies Inc
 */
contract AccountImplementation is INativeTokenReceivedEventEmitter {
    /**
     * @notice Emitted when a transaction is executed
     * @param to The destination address of the transaction
     * @param value The value of the transaction
     * @param data The data of the transaction
     * @param nonce The nonce used for this transaction
     * @param policyId The policy ID that governed this transaction
     */
    event TransactionExecuted(
        address indexed to, uint256 value, bytes data, uint256 indexed nonce, uint256 indexed policyId
    );

    /**
     * @notice Emitted when a transaction execution fails
     */
    error TransactionExecutionFailed();

    /**
     * @notice Emitted when the caller is not the associated organization
     */
    error OnlyOrganization();

    /**
     * @notice Modifier that enforces only the associated organization can call the function
     */
    modifier onlyOrganization() {
        if (msg.sender != LibAccountOrganizationAddressStorage.getOrganizationAddress()) {
            revert OnlyOrganization();
        }
        _;
    }

    // ================================
    // Organization reference
    // ================================

    /**
     * @notice Gets the organization address that this account is associated with (the beacon)
     * @return The organization address
     */
    function getOrganizationAddress() external view returns (address) {
        return LibAccountOrganizationAddressStorage.getOrganizationAddress();
    }

    // ================================
    // Transaction execution
    // ================================

    /**
     * @notice Executes a transaction from this account
     * @dev Can only be called by the associated Organization contract
     * @param to The destination address of the transaction
     * @param value The value of the transaction
     * @param data The data of the transaction
     * @param nonce The nonce for this transaction (computed by Organization)
     * @param policyId The ID of the policy that governs this transaction
     */
    function executeTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint256 nonce,
        uint256 policyId
    )
        external
        onlyOrganization
    {
        // Execute the transaction
        bool success = _execute(to, value, data, gasleft());

        if (!success) {
            revert TransactionExecutionFailed();
        }

        emit TransactionExecuted(to, value, data, nonce, policyId);
    }

    /**
     * @notice Executes a `CALL` with provided parameters.
     * @dev This method doesn't perform any sanity check of the transaction, such as:
     *      - if the contract at `to` address has code or not
     *      It is the responsibility of the caller to perform such checks.
     * @param to Destination address.
     * @param value Ether value.
     * @param data Data payload.
     * @param txGas Gas to use for the call.
     * @return success boolean flag indicating if the call succeeded.
     */
    function _execute(address to, uint256 value, bytes memory data, uint256 txGas) private returns (bool success) {
        /* solhint-disable no-inline-assembly */
        /// @solidity memory-safe-assembly
        assembly {
            success := call(txGas, to, value, add(data, 0x20), mload(data), 0, 0)
        }
    }

    // ================================
    // INativeTokenReceivedEventEmitter
    // ================================

    receive() external payable override {
        emit OnchainCustodyAccountNativeTokenReceived(msg.sender, msg.value);
    }
}
