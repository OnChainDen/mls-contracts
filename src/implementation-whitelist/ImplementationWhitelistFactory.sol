// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

import {
    ImplementationWhitelistImplementation
} from "implementation-whitelist/ImplementationWhitelistImplementation.sol";
import {ImplementationWhitelistProxy} from "implementation-whitelist/ImplementationWhitelistProxy.sol";

/**
 * @title Implementation Whitelist Factory
 * @notice Factory contract for deploying ImplementationWhitelistProxy contracts at deterministic addresses across
 * chains
 * @author Den Technologies Inc
 */
contract ImplementationWhitelistFactory {
    /**
     * @notice The address authorized to deploy implementation whitelist proxies
     */
    address public immutable DEPLOYER_ADDRESS;

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
     * @notice Constructor to set the deployer address
     * @param _deployerAddress The address authorized to deploy implementation whitelist proxies
     */
    constructor(address _deployerAddress) {
        if (_deployerAddress == address(0)) {
            revert ZeroAddress();
        }
        DEPLOYER_ADDRESS = _deployerAddress;
    }

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
        returns (address whitelistAddress)
    {
        // Only the authorized deployer can deploy implementation whitelists
        if (msg.sender != DEPLOYER_ADDRESS) {
            revert UnauthorizedDeployer();
        }

        bytes memory bytecode = _getImplementationWhitelistProxyBytecode(implementationAddress);

        // Deploy the implementation whitelist proxy using CREATE2
        whitelistAddress = Create2.deploy(0, salt, bytecode);

        // Case: The deployed address does not match the address we expected
        if (whitelistAddress != computeImplementationWhitelistAddress(salt, implementationAddress)) {
            revert DeploymentAddressMismatch();
        }

        // Emit event before external call (CEI pattern) - if initialize fails, transaction reverts
        emit ImplementationWhitelistDeployed(whitelistAddress, salt, DEPLOYER_ADDRESS, initialOwner);

        // Initialize the implementation whitelist atomically - reverts the entire transaction if initialization fails
        ImplementationWhitelistImplementation(whitelistAddress).initialize(initialOwner);
    }

    /**
     * @notice Computes the address where an implementation whitelist proxy would be deployed
     * @param salt The salt for CREATE2 deployment
     * @param implementationAddress The address of the ImplementationWhitelistImplementation contract
     * @return The computed address
     */
    function computeImplementationWhitelistAddress(bytes32 salt, address implementationAddress)
        public
        view
        returns (address)
    {
        return Create2.computeAddress(salt, keccak256(_getImplementationWhitelistProxyBytecode(implementationAddress)));
    }

    /// @dev Returns the creation bytecode for deploying an ImplementationWhitelistProxy
    /// @param implementationAddress The address of the ImplementationWhitelistImplementation contract
    /// @return bytecode The creation bytecode to deploy via CREATE2
    function _getImplementationWhitelistProxyBytecode(address implementationAddress)
        private
        pure
        returns (bytes memory bytecode)
    {
        // Generate the bytecode to deploy the ImplementationWhitelistProxy (which is a ERC1967Proxy)
        // with the ImplementationWhitelistImplementation as the implementation
        return abi.encodePacked(type(ImplementationWhitelistProxy).creationCode, abi.encode(implementationAddress));
    }
}
