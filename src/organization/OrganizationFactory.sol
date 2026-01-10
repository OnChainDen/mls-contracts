// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IImplementationWhitelist} from "../implementation-whitelist/interfaces/IImplementationWhitelist.sol";
import {InitializationParams} from "../interfaces/IOrganization.sol";
import {OrganizationImplementation} from "./OrganizationImplementation.sol";
import {OrganizationProxy} from "./OrganizationProxy.sol";
import {LibOrganizationInitialization} from "./libraries/LibOrganizationInitialization.sol";

/**
 * @title Organization Factory
 * @notice Factory contract for deploying OrganizationProxy contracts at deterministic addresses across chains
 * @author Den Technologies Inc
 */
contract OrganizationFactory {
    /**
     * @notice The address authorized to deploy organization proxies
     */
    address public immutable DEPLOYER_ADDRESS;

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
     * @notice Error thrown when deployment fails
     */
    error DeploymentFailed();

    /**
     * @notice Error thrown when the deployed address does not match the computed address
     */
    error DeploymentAddressMismatch();

    /**
     * @notice Constructor to set the deployer address
     * @param _deployerAddress The address authorized to deploy organization proxies
     */
    constructor(address _deployerAddress) {
        DEPLOYER_ADDRESS = _deployerAddress;
    }

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
    ) external returns (address organizationAddress) {
        // Only the authorized deployer can deploy organizations
        if (msg.sender != DEPLOYER_ADDRESS) {
            revert LibOrganizationInitialization.UnauthorizedDeployer();
        }

        // Validate that the implementation is whitelisted
        IImplementationWhitelist(whitelistAddress).validateIsImplementationWhitelistedOrRevert(
            IImplementationWhitelist.ContractType.Organization, implementationAddress
        );

        // Generate the bytecode to deploy the OrganizationProxy (which is a ERC1967Proxy)
        // with the OrganizationImplementation as the implementation and the whitelist address
        bytes memory bytecode =
            abi.encodePacked(type(OrganizationProxy).creationCode, abi.encode(implementationAddress, whitelistAddress));

        // Deploy the organization proxy using CREATE2
        assembly {
            organizationAddress := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }

        // Case: Deployment failed
        if (organizationAddress == address(0)) {
            revert DeploymentFailed();
        }

        // Case: The deployed address does not match the address we expected
        if (organizationAddress != computeOrganizationAddress(salt, implementationAddress, whitelistAddress)) {
            revert DeploymentAddressMismatch();
        }

        // Initialize the organization atomically - reverts the entire transaction if initialization fails
        OrganizationImplementation(organizationAddress).initialize(initParams);

        emit OrganizationDeployed(organizationAddress, salt, DEPLOYER_ADDRESS);
    }

    /**
     * @notice Computes the address where an organization proxy would be deployed
     * @param salt The salt for CREATE2 deployment
     * @param implementationAddress The address of the OrganizationImplementation contract
     * @param whitelistAddress The address of the implementation whitelist contract
     * @return The computed address
     */
    function computeOrganizationAddress(bytes32 salt, address implementationAddress, address whitelistAddress)
        public
        view
        returns (address)
    {
        bytes memory bytecode =
            abi.encodePacked(type(OrganizationProxy).creationCode, abi.encode(implementationAddress, whitelistAddress));

        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));

        return address(uint160(uint256(hash)));
    }
}
