// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {IOrganization} from "interfaces/IOrganization.sol";
import {IOrganizationAccountFactory} from "interfaces/organization/IOrganizationAccountFactory.sol";
import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {OrganizationModifiers} from "organization/common/OrganizationModifiers.sol";
import {LibOrganizationAccountFactory} from "organization/libraries/LibOrganizationAccountFactory.sol";
import {LibOrganizationAdmin} from "organization/libraries/LibOrganizationAdmin.sol";
import {
    LibOrganizationAccountFactoryStorage
} from "organization/libraries/storage/LibOrganizationAccountFactoryStorage.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @title OrganizationAccountFactoryBase
 * @dev Abstract contract implementing IOrganizationAccountFactory.
 *      Handles account deployment and implementation management.
 *      Also implements IBeacon.implementation() for Account BeaconProxies.
 *      Note: IBeacon is inherited via IOrganization in the final contract.
 * @author Den Technologies Inc
 */
abstract contract OrganizationAccountFactoryBase is OrganizationModifiers, IOrganizationAccountFactory {
    /// @inheritdoc IOrganizationAccountFactory
    function deployAccount(bytes32 create2Salt, AdminAuthParams calldata authParams)
        external
        override
        onlyGuardian
        returns (address)
    {
        // Validate admin authorization for account deployment
        bytes memory operationData = abi.encode(create2Salt);

        // isApproval = true for execution
        uint256 nonce = LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.DeployAccount,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        // Execute via low-level self-call so that a revert does not bubble up.
        /* solhint-disable avoid-low-level-calls */
        // slither-disable-next-line low-level-calls,reentrancy-events
        (bool success, bytes memory returnData) =
            address(this).call(abi.encodeCall(this.executeDeployAccount, (create2Salt)));
        /* solhint-enable avoid-low-level-calls */

        if (success) {
            return abi.decode(returnData, (address));
        }

        emit IOrganizationAdmin.AdminOperationExecutionReverted(OperationType.DeployAccount, nonce, returnData);
        return address(0);
    }

    /// @inheritdoc IOrganizationAccountFactory
    function executeDeployAccount(bytes32 create2Salt) external onlySelf returns (address) {
        return LibOrganizationAccountFactory.deployAccount(create2Salt);
    }

    /// @inheritdoc IOrganizationAccountFactory
    // slither-disable-next-line missing-zero-check
    function setAccountImplementation(address newImplementation, AdminAuthParams calldata authParams)
        external
        override
        onlyGuardian
    {
        // Validate admin authorization (isApproval = true for execution)
        bytes memory operationData = abi.encode(newImplementation);
        uint256 nonce = LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.UpgradeAccount,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        // Execute via low-level self-call so that a revert does not bubble up.
        /* solhint-disable avoid-low-level-calls */
        // forgefmt: disable-start
        // slither-disable-next-line low-level-calls,reentrancy-events,missing-zero-check
        (bool success, bytes memory revertData) =
            address(this).call(abi.encodeCall(this.executeSetAccountImplementation, (newImplementation)));
        // forgefmt: disable-end
        /* solhint-enable avoid-low-level-calls */

        if (!success) {
            emit IOrganizationAdmin.AdminOperationExecutionReverted(OperationType.UpgradeAccount, nonce, revertData);
        }
    }

    /// @inheritdoc IOrganizationAccountFactory
    function executeSetAccountImplementation(address newImplementation) external onlySelf {
        LibOrganizationAccountFactory.setAccountImplementation(newImplementation);
        emit AccountImplementationUpdated(newImplementation);
    }

    /// @inheritdoc IOrganizationAccountFactory
    function computeAccountAddress(bytes32 salt) external view override returns (address) {
        return LibOrganizationAccountFactory.computeAccountAddress(salt);
    }

    /**
     * @dev Returns the current implementation address for all Account BeaconProxies.
     *      Required by IBeacon interface (inherited via IOrganization in the final contract).
     * @return The current account implementation address
     */
    function implementation() public view virtual returns (address) {
        address impl = LibOrganizationAccountFactoryStorage.layout().accountImplementation;
        if (impl == address(0)) {
            revert IOrganization.AccountImplementationNotSet();
        }
        if (impl.code.length == 0) {
            revert ERC1967Utils.ERC1967InvalidImplementation(impl);
        }
        return impl;
    }
}
