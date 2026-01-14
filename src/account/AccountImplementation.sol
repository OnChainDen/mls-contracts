// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IOrganizationSignatureValidator} from "../interfaces/IOrganization.sol";
import {IAccount} from "../interfaces/IAccount.sol";
import {LibAccountOrganizationAddressStorage} from "./libraries/storage/LibAccountOrganizationAddressStorage.sol";

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

/**
 * @title Account Implementation
 * @notice Implementation contract for Account (used with BeaconProxy)
 * @dev This contract is used behind a BeaconProxy where the Organization acts as the beacon.
 *      Upgrades are handled by the beacon (Organization), not by this contract directly.
 * @author Den Technologies Inc
 */
contract AccountImplementation is IAccount, IERC1271 {
    /**
     * @notice Modifier that enforces only the associated organization can call the function
     */
    modifier onlyOrganization() {
        _onlyOrganization();
        _;
    }

    /**
     * @notice Receives native tokens (ETH) sent to this account
     * @dev Emits OnchainCustodyAccountNativeTokenReceived event when native tokens are received
     */
    receive() external payable override {
        emit OnchainCustodyAccountNativeTokenReceived(msg.sender, msg.value);
    }

    /**
     * @notice Executes a transaction from this account
     * @dev Can only be called by the associated Organization contract
     * @param to The destination address of the transaction
     * @param value The value of the transaction
     * @param data The data of the transaction
     * @param nonce The nonce for this transaction (computed by Organization)
     * @param policyId The ID of the policy that governs this transaction
     */
    function executeTransaction(address to, uint256 value, bytes calldata data, uint256 nonce, uint256 policyId)
        external
        onlyOrganization
    {
        // Execute the transaction
        bool success = _execute(to, value, data, gasleft());

        if (!success) {
            revert TransactionExecutionFailed();
        }

        emit TransactionExecuted({to: to, value: value, data: data, nonce: nonce, policyId: policyId});
    }

    /**
     * @notice Gets the organization address that this account is associated with (the beacon)
     * @return The organization address
     */
    function getOrganizationAddress() external view returns (address) {
        return LibAccountOrganizationAddressStorage.getOrganizationAddress();
    }

    /**
     * @notice Validates a signature according to ERC-1271
     * @dev Delegates signature validation to the associated Organization contract.
     *      Note: Time-based policy limits are NOT supported for ERC-1271 signatures because the standard
     *      requires isValidSignature to be a view function (cannot modify storage to track usage).
     * @param hash The hash of the data that was signed
     * @param signature The signature to validate (encoded with policyId, approver signatures, guardian signature)
     * @return magicValue 0x1626ba7e if valid, 0xffffffff otherwise
     */
    function isValidSignature(bytes32 hash, bytes calldata signature)
        external
        view
        override(IAccount, IERC1271)
        returns (bytes4 magicValue)
    {
        address organization = LibAccountOrganizationAddressStorage.getOrganizationAddress();
        return IOrganizationSignatureValidator(organization).isValidSignatureForAccount(address(this), hash, signature);
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
        // slither-disable-next-line assembly
        assembly {
            success := call(txGas, to, value, add(data, 0x20), mload(data), 0, 0)
        }
    }

    /**
     * @notice Internal function to check if the caller is the organization
     * @dev Extracted from modifier to reduce code size
     */
    function _onlyOrganization() private view {
        if (msg.sender != LibAccountOrganizationAddressStorage.getOrganizationAddress()) {
            revert OnlyOrganization();
        }
    }
}
