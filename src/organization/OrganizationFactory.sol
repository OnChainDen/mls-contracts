// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./OrganizationProxy.sol";
import { OrganizationImplementation } from "./OrganizationImplementation.sol";
import { IAdminFacet, AdminType } from "../interfaces/IAdminFacet.sol";

/**
 * @title Organization Factory
 * @notice Factory contract for deploying OrganizationProxy contracts at deterministic addresses across chains
 * @author Den Technologies Inc
 */
contract OrganizationFactory {
    /**
     * @notice The address authorized to deploy organization proxies
     */
    address public immutable deployerAddress;

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
     * @notice Error thrown when caller is not the authorized deployer
     */
    error UnauthorizedDeployer();

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
        deployerAddress = _deployerAddress;
    }

    /**
     * @notice Deploys a new OrganizationProxy at a deterministic address
     * @dev Uses CREATE2 to ensure the same address across different chains
     * @param salt The salt for CREATE2 deployment
     * @param implementationAddress The address of the OrganizationImplementation contract
     * @param whitelistAddress The address of the implementation whitelist contract
     * @param adminType Type of admin (Member or Group)
     * @param adminAddresses Array of addresses to be added as admin members
     * @param votingThreshold Voting threshold (only used for Group admin type)
     * @param guardian Guardian address for the organization
     * @return organizationAddress The address of the deployed organization proxy
     */
    function deployOrganization(
        bytes32 salt,
        address implementationAddress,
        address whitelistAddress,
        AdminType adminType,
        address[] memory adminAddresses,
        uint256 votingThreshold,
        address guardian
    )
        external
        returns (address organizationAddress)
    {
        // Only the authorized deployer can deploy organizations
        if (msg.sender != deployerAddress) {
            revert UnauthorizedDeployer();
        }

        // Encode initialization data
        bytes memory initData = abi.encodeWithSelector(
            OrganizationImplementation.initialize.selector,
            whitelistAddress,
            deployerAddress,
            adminType,
            adminAddresses,
            votingThreshold,
            guardian
        );

        // Deploy the organization proxy using CREATE2
        bytes memory bytecode = abi.encodePacked(
            type(OrganizationProxy).creationCode, abi.encode(implementationAddress, initData, deployerAddress)
        );

        assembly {
            organizationAddress := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }

        // Check if deployment was successful
        if (organizationAddress == address(0)) {
            revert DeploymentFailed();
        }

        // Check if the deployed address matches the computed address
        if (
            organizationAddress
                != computeOrganizationAddress(
                    salt, implementationAddress, whitelistAddress, adminType, adminAddresses, votingThreshold, guardian
                )
        ) {
            revert DeploymentAddressMismatch();
        }

        emit OrganizationDeployed(organizationAddress, salt, deployerAddress);
    }

    /**
     * @notice Computes the address where an organization proxy would be deployed
     * @param salt The salt for CREATE2 deployment
     * @param implementationAddress The address of the OrganizationImplementation contract
     * @param whitelistAddress The address of the implementation whitelist contract
     * @param adminType Type of admin (Member or Group)
     * @param adminAddresses Array of addresses to be added as admin members
     * @param votingThreshold Voting threshold (only used for Group admin type)
     * @param guardian Guardian address for the organization
     * @return The computed address
     */
    function computeOrganizationAddress(
        bytes32 salt,
        address implementationAddress,
        address whitelistAddress,
        AdminType adminType,
        address[] memory adminAddresses,
        uint256 votingThreshold,
        address guardian
    )
        public
        view
        returns (address)
    {
        // Encode initialization data
        bytes memory initData = abi.encodeWithSelector(
            OrganizationImplementation.initialize.selector,
            whitelistAddress,
            deployerAddress,
            adminType,
            adminAddresses,
            votingThreshold,
            guardian
        );

        bytes memory bytecode = abi.encodePacked(
            type(OrganizationProxy).creationCode, abi.encode(implementationAddress, initData, deployerAddress)
        );

        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));

        return address(uint160(uint256(hash)));
    }
}
