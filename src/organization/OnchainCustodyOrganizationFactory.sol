// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./OnchainCustodyOrganizationDiamond.sol";
import "../diamond/interfaces/IDiamondCut.sol";
import "../diamond/Diamond.sol";

/**
 * @title Onchain Custody Organization Factory
 * @notice Factory contract for deploying OnchainCustodyOrganizationDiamond contracts at deterministic addresses across
 * chains
 * @author Den Technologies Inc
 */
contract OnchainCustodyOrganizationFactory {
    /**
     * @notice The address authorized to deploy organization diamonds
     */
    address public immutable deployerAddress;

    /**
     * @notice Emitted when a new organization diamond is deployed
     * @param organizationAddress The address of the deployed organization diamond
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
     * @param _deployerAddress The address authorized to deploy organization diamonds
     */
    constructor(address _deployerAddress) {
        deployerAddress = _deployerAddress;
    }

    /**
     * @notice Deploys a new OnchainCustodyOrganizationDiamond at a deterministic address
     * @dev Uses CREATE2 to ensure the same address across different chains
     * @param salt The salt for CREATE2 deployment
     * @param _diamondCut The initial diamond cuts to apply during deployment
     * @param whitelistSetId The ID of the whitelisted facet set to validate against
     * @return organizationAddress The address of the deployed organization diamond
     */
    function deployOrganization(
        bytes32 salt,
        IDiamondCut.FacetCut[] memory _diamondCut,
        address _facetWhitelistAddress,
        uint256 whitelistSetId
    )
        external
        returns (address organizationAddress)
    {
        // Only the authorized deployer can deploy organizations
        if (msg.sender != deployerAddress) {
            revert UnauthorizedDeployer();
        }

        // Deploy the organization diamond using CREATE2
        bytes memory bytecode = abi.encodePacked(
            type(OnchainCustodyOrganizationDiamond).creationCode,
            abi.encode(_diamondCut, deployerAddress, _facetWhitelistAddress, whitelistSetId)
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
            organizationAddress != computeOrganizationAddress(salt, _diamondCut, _facetWhitelistAddress, whitelistSetId)
        ) {
            revert DeploymentAddressMismatch();
        }

        emit OrganizationDeployed(organizationAddress, salt, deployerAddress);
    }

    /**
     * @notice Computes the address where an organization diamond would be deployed
     * @param salt The salt for CREATE2 deployment
     * @param _diamondCut The initial diamond cuts to apply during deployment
     * @param whitelistSetId The ID of the whitelisted facet set to validate against
     * @return The computed address
     */
    function computeOrganizationAddress(
        bytes32 salt,
        IDiamondCut.FacetCut[] memory _diamondCut,
        address _facetWhitelistAddress,
        uint256 whitelistSetId
    )
        public
        view
        returns (address)
    {
        bytes memory bytecode = abi.encodePacked(
            type(OnchainCustodyOrganizationDiamond).creationCode,
            abi.encode(_diamondCut, deployerAddress, _facetWhitelistAddress, whitelistSetId)
        );

        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));

        return address(uint160(uint256(hash)));
    }
}
