// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAccountFactory} from "interfaces/organization/IOrganizationAccountFactory.sol";
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
        LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.DeployAccount,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        return LibOrganizationAccountFactory.deployAccount(create2Salt);
    }

    /// @inheritdoc IOrganizationAccountFactory
    function setAccountImplementation(address newImplementation, AdminAuthParams calldata authParams)
        external
        override
        onlyGuardian
    {
        // 1. Validate admin authorization (isApproval = true for execution)
        bytes memory operationData = abi.encode(newImplementation);
        LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.UpgradeAccount,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        // 2. Validate implementation against whitelist and set storage
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
     *
     *      Invariant: by the time this Organization exists on-chain, the stored
     *      implementation is guaranteed to be a non-zero address with runtime code.
     *      `OrganizationFactory.deployOrganization` deploys the OrganizationProxy and
     *      runs `initialize` atomically, and initialization sets the account
     *      implementation via `LibOrganizationAccountFactory.setAccountImplementation`,
     *      which rejects the zero address and any address without runtime code.
     *      Subsequent updates go through the same library function, preserving the
     *      invariant.
     * @return The current account implementation address
     */
    function implementation() public view virtual returns (address) {
        return LibOrganizationAccountFactoryStorage.layout().accountImplementation;
    }
}
