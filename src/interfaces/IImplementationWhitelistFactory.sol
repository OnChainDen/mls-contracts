// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IImplementationWhitelistFactory
 * @notice Interface for the Implementation Whitelist Factory contract
 * @dev Factory contract for deploying ImplementationWhitelistProxy contracts at deterministic addresses across chains
 * @author Den Technologies Inc
 */
interface IImplementationWhitelistFactory {
    /**
     * @notice Emitted when a new implementation whitelist proxy is deployed
     * @param whitelistAddress The address of the deployed implementation whitelist proxy
     * @param salt The salt used for CREATE2 deployment
     * @param deployerAddress The address that deployed the whitelist
     * @param owner The initial owner of the whitelist
     */
    event ImplementationWhitelistDeployed(
        address indexed whitelistAddress, bytes32 indexed salt, address indexed deployerAddress, address owner
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
     * @notice Error thrown when caller is not the authorized deployer
     */
    error UnauthorizedDeployer();

    /**
     * @notice Deploys and initializes a new ImplementationWhitelistProxy at a deterministic address
     * @dev Uses CREATE2 to ensure the same address across different chains.
     *      Deployment and initialization are atomic - if initialization fails, the entire transaction reverts.
     * @param salt The salt for CREATE2 deployment
     * @param implementationAddress The address of the ImplementationWhitelistImplementation contract
     * @param initialOwner The initial owner address for the whitelist contract
     * @return whitelistAddress The address of the deployed implementation whitelist proxy
     */
    function deployImplementationWhitelist(bytes32 salt, address implementationAddress, address initialOwner)
        external
        returns (address whitelistAddress);

    /**
     * @notice Computes the address where an implementation whitelist proxy would be deployed
     * @param salt The salt for CREATE2 deployment
     * @param implementationAddress The address of the ImplementationWhitelistImplementation contract
     * @return The computed address
     */
    function computeImplementationWhitelistAddress(bytes32 salt, address implementationAddress)
        external
        view
        returns (address);

    /**
     * @notice The address authorized to deploy implementation whitelist proxies
     * @return The deployer address
     */
    function DEPLOYER_ADDRESS() external view returns (address);
}
