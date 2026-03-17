// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

import {LibAccountOrganizationAddressStorage} from "account/libraries/storage/LibAccountOrganizationAddressStorage.sol";
import {IAccount} from "interfaces/IAccount.sol";
import {IOrganizationAccountSignature} from "interfaces/organization/IOrganizationAccountSignature.sol";
import {SignatureUtils} from "libraries/SignatureUtils.sol";

/**
 * @title Account Implementation
 * @notice Implementation contract for Account (used with BeaconProxy)
 * @dev This contract is used behind a BeaconProxy where the Organization acts as the beacon.
 *      Upgrades are handled by the beacon (Organization), not by this contract directly.
 * @author Den Technologies Inc
 */
contract AccountImplementation is IAccount {
    /**
     * @notice Modifier that enforces only the associated organization can call the function
     */
    modifier onlyOrganization() {
        _onlyOrganization();
        _;
    }

    /// @inheritdoc IAccount
    receive() external payable override {
        emit MLSWalletAccountNativeTokenReceived(msg.sender, msg.value);
    }

    /// @inheritdoc IAccount
    function executeTransaction(address to, uint256 value, bytes calldata data, uint256 nonce, uint256 policyId)
        external
        override
        onlyOrganization
    {
        // Execute the transaction
        bool success = _execute(to, value, data, gasleft());

        if (!success) {
            revert TransactionExecutionFailed();
        }

        emit TransactionExecuted({to: to, value: value, data: data, nonce: nonce, policyId: policyId});
    }

    /// @inheritdoc IAccount
    function getOrganizationAddress() external view override returns (address) {
        return LibAccountOrganizationAddressStorage.getOrganizationAddress();
    }

    /// @inheritdoc IERC1271
    function isValidSignature(bytes32 hash, bytes calldata signature)
        external
        view
        override
        returns (bytes4 magicValue)
    {
        address organization = LibAccountOrganizationAddressStorage.getOrganizationAddress();
        (bool success, bytes memory result) = organization.staticcall(
            abi.encodeCall(IOrganizationAccountSignature.isValidSignatureForAccount, (address(this), hash, signature))
        );

        if (!success || result.length < 32) {
            return SignatureUtils.ERC1271_INVALID_VALUE;
        }

        return abi.decode(result, (bytes4));
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
    function _execute(address to, uint256 value, bytes memory data, uint256 txGas) internal returns (bool success) {
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
    function _onlyOrganization() internal view {
        if (msg.sender != LibAccountOrganizationAddressStorage.getOrganizationAddress()) {
            revert OnlyOrganization();
        }
    }
}
