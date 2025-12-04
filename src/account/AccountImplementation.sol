// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseUUPSImplementation } from "../proxy/BaseUUPSImplementation.sol";
import { LibAccountAdmin } from "./libraries/LibAccountAdmin.sol";
import { LibAccountGuardian } from "./libraries/LibAccountGuardian.sol";
import { LibAccountTransaction } from "./libraries/LibAccountTransaction.sol";
import { IAdminFacet, AdminOperationType } from "../interfaces/IAdminFacet.sol";
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
     * @notice Modifier that enforces only the guardian can call the function
     */
    modifier onlyGuardian() {
        LibAccountGuardian.enforceOnlyGuardian();
        _;
    }

    // ================================
    // LibAccountAdmin wrappers
    // ================================

    function getOrganizationAddress() external view returns (address) {
        return LibAccountAdmin.getOrganizationAddress();
    }

    function validateAdminAuthorization(
        AdminOperationType operationType,
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
    // LibAccountTransaction wrappers
    // ================================

    function isNonceUsed(uint256 nonce) external view returns (bool) {
        return LibAccountTransaction.isNonceUsed(nonce);
    }

    function computeNonce(
        address to,
        uint256 value,
        bytes calldata data,
        uint256 salt,
        uint256 policyId
    )
        external
        view
        returns (uint256)
    {
        return LibAccountTransaction.computeNonce(to, value, data, salt, policyId);
    }

    function executeTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint256 salt,
        uint256 policyId,
        bytes memory signatures
    )
        external
        onlyGuardian
    {
        LibAccountTransaction.executeTransaction(to, value, data, salt, policyId, signatures);
    }

    function rejectTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint256 salt,
        uint256 policyId,
        uint256 chainId,
        bytes memory signatures
    )
        external
        onlyGuardian
    {
        LibAccountTransaction.rejectTransaction(to, value, data, salt, policyId, chainId, signatures);
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
