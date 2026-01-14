// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {InitializationParams} from "../types/CommonTypes.sol";

/**
 * @title IOrganizationFactory
 * @notice Interface for the Organization Factory contract
 * @dev Factory contract for deploying OrganizationProxy contracts at deterministic addresses across chains
 * @author Den Technologies Inc
 */
interface IOrganizationFactory {
    /**
     * @notice Emitted when a new organization proxy is deployed
     * @param organizationAddress The address of the deployed organization proxy
     * @param salt The salt used for CREATE2 deployment
     * @param deployerAddress The address that deployed the organization
     */
    event OrganizationDeployed(
        address indexed organizationAddress, bytes32 indexed salt, address indexed deployerAddress
    );

    /**
     * @notice Error thrown when the deployed address does not match the computed address
     */
    error DeploymentAddressMismatch();

    /**
     * @notice Error thrown when a zero address is provided where a valid address is required
     */
    error ZeroAddress();

    /**
     * @notice Deploys and initializes a new OrganizationProxy at a deterministic address
     * @dev Uses CREATE2 to ensure the same address across different chains.
     *      Deployment and initialization are atomic - if initialization fails, the entire transaction reverts.
     * @param salt The salt for CREATE2 deployment
     * @param implementationAddress The address of the OrganizationImplementation contract
     * @param whitelistAddress The address of the implementation whitelist contract
     * @param initParams The initialization parameters for the organization
     * @return organizationAddress The address of the deployed organization proxy
     */
    function deployOrganization(
        bytes32 salt,
        address implementationAddress,
        address whitelistAddress,
        InitializationParams calldata initParams
    ) external returns (address organizationAddress);

    /**
     * @notice Computes the address where an organization proxy would be deployed
     * @param salt The salt for CREATE2 deployment
     * @param implementationAddress The address of the OrganizationImplementation contract
     * @param whitelistAddress The address of the implementation whitelist contract
     * @return The computed address
     */
    function computeOrganizationAddress(bytes32 salt, address implementationAddress, address whitelistAddress)
        external
        view
        returns (address);

    /**
     * @notice The address authorized to deploy organization proxies
     * @return The deployer address
     */
    function DEPLOYER_ADDRESS() external view returns (address);
}
