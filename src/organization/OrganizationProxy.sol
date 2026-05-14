// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {IImplementationWhitelist} from "interfaces/IImplementationWhitelist.sol";
import {IOrganizationFactory} from "interfaces/IOrganizationFactory.sol";
import {IOrganizationInitialization} from "interfaces/organization/IOrganizationInitialization.sol";
import {
    LibOrganizationDeployerAddressStorage
} from "organization/libraries/storage/LibOrganizationDeployerAddressStorage.sol";
import {LibOrganizationUpgradeStorage} from "organization/libraries/storage/LibOrganizationUpgradeStorage.sol";
import {ContractType} from "types/CommonTypes.sol";

/**
 * @title Organization Proxy
 * @notice ERC-1967 proxy for Organization with deferred implementation binding
 * @dev The implementation is bound post-construction via `setInitialImplementation`, so
 *      the proxy's CREATE2 init code does not depend on the implementation version.
 * @author Den Technologies Inc
 */
contract OrganizationProxy is Proxy {
    /**
     * @notice Constructor for the proxy
     * @param whitelistAddress The address of the implementation whitelist contract
     * @dev The deployer (msg.sender) is stored for authorization when setting the implementation and initializing.
     *      The factory deploys and initializes atomically in a single transaction.
     *
     */
    constructor(address whitelistAddress) {
        // Case: Whitelist contract is a zero address
        if (whitelistAddress == address(0)) {
            revert IOrganizationFactory.ZeroAddress();
        }

        // Case: Whitelist contract is not a deployed contract
        if (whitelistAddress.code.length == 0) {
            revert Address.AddressEmptyCode(whitelistAddress);
        }

        // Store deployer address (the factory) in storage for initialization authorization
        LibOrganizationDeployerAddressStorage.layout().deployerAddress = msg.sender;

        // Store whitelist address in storage for upgrade validation
        LibOrganizationUpgradeStorage.layout().whitelistAddress = whitelistAddress;
    }

    /**
     * @notice Bind the implementation address to this proxy. Deployer-gated, one-shot.
     * @param implementation The OrganizationImplementation address to bind
     * @dev Reverts with `UnauthorizedDeployer`, `ImplementationAlreadySet`, `ZeroAddress`,
     *      whitelist rejection, or `ERC1967InvalidImplementation` (no code).
     */
    function setInitialImplementation(address implementation) external {
        // Case: Caller is not the recorded deployer
        if (msg.sender != LibOrganizationDeployerAddressStorage.layout().deployerAddress) {
            revert IOrganizationInitialization.UnauthorizedDeployer();
        }

        // Case: Implementation slot already populated (one-shot guard)
        if (ERC1967Utils.getImplementation() != address(0)) {
            revert IOrganizationInitialization.ImplementationAlreadySet();
        }

        // Case: Zero implementation address
        if (implementation == address(0)) {
            revert IOrganizationFactory.ZeroAddress();
        }

        // Validate implementation is whitelisted for Organization
        IImplementationWhitelist(LibOrganizationUpgradeStorage.layout().whitelistAddress)
            .validateIsImplementationWhitelistedOrRevert(ContractType.Organization, implementation);

        // Set the implementation slot. Rejects EOA targets and emits `Upgraded`.
        ERC1967Utils.upgradeToAndCall(implementation, "");
    }

    /// @dev Returns the current implementation from the ERC-1967 slot
    function _implementation() internal view override returns (address) {
        return ERC1967Utils.getImplementation();
    }
}
