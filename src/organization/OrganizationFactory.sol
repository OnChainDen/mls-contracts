// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

import {IOrganizationFactory} from "interfaces/IOrganizationFactory.sol";
import {IOrganizationInitialization} from "interfaces/organization/IOrganizationInitialization.sol";
import {OrganizationImplementation} from "organization/OrganizationImplementation.sol";
import {OrganizationProxy} from "organization/OrganizationProxy.sol";
import {InitializationParams} from "types/CommonTypes.sol";

/**
 * @title Organization Factory
 * @notice Factory contract for deploying OrganizationProxy contracts at deterministic addresses across chains
 * @author Den Technologies Inc
 */
contract OrganizationFactory is IOrganizationFactory {
    /// @inheritdoc IOrganizationFactory
    address public immutable override DEPLOYER_ADDRESS;

    /**
     * @notice Constructor to set the deployer address
     * @param _deployerAddress The address authorized to deploy organization proxies
     */
    constructor(address _deployerAddress) {
        if (_deployerAddress == address(0)) {
            revert ZeroAddress();
        }
        DEPLOYER_ADDRESS = _deployerAddress;
    }

    /// @inheritdoc IOrganizationFactory
    function deployOrganization(
        bytes32 salt,
        address implementationAddress,
        address whitelistAddress,
        InitializationParams calldata initParams
    ) external override returns (address organizationAddress) {
        // Only the authorized deployer can deploy organizations
        if (msg.sender != DEPLOYER_ADDRESS) {
            revert IOrganizationInitialization.UnauthorizedDeployer();
        }

        bytes memory bytecode = _getOrganizationProxyBytecode(whitelistAddress);

        // Deploy the organization proxy using CREATE2
        organizationAddress = Create2.deploy(0, salt, bytecode);

        // Case: The deployed address does not match the address we expected
        if (organizationAddress != computeOrganizationAddress(salt, whitelistAddress)) {
            revert DeploymentAddressMismatch();
        }

        // Emit event before external calls (CEI pattern) - if any subsequent call fails the whole tx reverts
        emit OrganizationDeployed(organizationAddress, salt, DEPLOYER_ADDRESS);

        // Bind the implementation contract to the proxy
        OrganizationProxy(payable(organizationAddress)).setInitialImplementation(implementationAddress);

        // Initialize the organization atomically - reverts the entire transaction if initialization fails
        OrganizationImplementation(organizationAddress).initialize(initParams);
    }

    /// @inheritdoc IOrganizationFactory
    function computeOrganizationAddress(bytes32 salt, address whitelistAddress) public view override returns (address) {
        return Create2.computeAddress(salt, keccak256(_getOrganizationProxyBytecode(whitelistAddress)));
    }

    /// @dev Returns the creation bytecode for deploying an OrganizationProxy
    /// @param whitelistAddress The address of the implementation whitelist contract
    /// @return bytecode The creation bytecode to deploy via CREATE2
    function _getOrganizationProxyBytecode(address whitelistAddress) internal pure returns (bytes memory bytecode) {
        return abi.encodePacked(type(OrganizationProxy).creationCode, abi.encode(whitelistAddress));
    }
}
