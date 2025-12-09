// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseUUPSImplementation } from "../proxy/BaseUUPSImplementation.sol";
import { LibAccountAdmin } from "./libraries/LibAccountAdmin.sol";
import { LibAccountGuardian } from "./libraries/LibAccountGuardian.sol";
import { LibAccountOrganizationAddressStorage } from "./libraries/storage/LibAccountOrganizationAddressStorage.sol";
import { IAdminFacet } from "../interfaces/IAdminFacet.sol";
import { OperationType } from "../interfaces/IOrganization.sol";
import { IUpgradeable } from "../interfaces/IUpgradeable.sol";
import { INativeTokenReceivedEventEmitter } from "./interfaces/INativeTokenReceivedEventEmitter.sol";

/**
 * @title Account Implementation
 * @notice UUPS upgradeable implementation contract for Account
 * @dev This contract exposes all Account library functions as external wrappers
 * @author Den Technologies Inc
 */
contract AccountImplementation is
    BaseUUPSImplementation,
    IAdminFacet,
    IUpgradeable,
    INativeTokenReceivedEventEmitter
{
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
     * @notice Modifier that enforces only the guardian can call the function
     */
    modifier onlyGuardian() {
        LibAccountGuardian.enforceOnlyGuardian();
        _;
    }

    /**
     * @notice Modifier that enforces only the associated organization can call the function
     */
    modifier onlyOrganization() {
        if (msg.sender != LibAccountOrganizationAddressStorage.layout().organizationAddress) {
            revert OnlyOrganization();
        }
        _;
    }

    // ================================
    // LibAccountAdmin wrappers
    // ================================

    /**
     * @notice Gets the organization address that this account is associated with
     * @return The organization address
     */
    function getOrganizationAddress() external view returns (address) {
        return LibAccountOrganizationAddressStorage.layout().organizationAddress;
    }

    function validateAdminAuthorization(
        OperationType operationType,
        bytes memory operationData,
        uint256 salt,
        bytes memory signatures
    )
        external
        override
    {
        LibAccountAdmin.validateAdminAuthorization(operationType, operationData, salt, signatures);
    }

    // ================================
    // LibAccountGuardian wrappers
    // ================================

    function enforceOnlyGuardian() external view {
        LibAccountGuardian.enforceOnlyGuardian();
    }

    function guardian() external view returns (address) {
        return LibAccountGuardian.guardian();
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
    // IUpgradeable interface
    // ================================

    function upgradeToWithAuthorization(
        address newImplementation,
        uint256 salt,
        bytes calldata signatures
    )
        external
        override
    {
        super.upgradeToWithAuthorization(newImplementation, salt, signatures);
    }

    function upgradeToAndCallWithAuthorization(
        address newImplementation,
        bytes memory data,
        uint256 salt,
        bytes calldata signatures
    )
        external
        override
    {
        super.upgradeToAndCallWithAuthorization(newImplementation, data, salt, signatures);
    }

    // ================================
    // INativeTokenReceivedEventEmitter
    // ================================

    receive() external payable override {
        emit OnchainCustodyAccountNativeTokenReceived(msg.sender, msg.value);
    }
}
