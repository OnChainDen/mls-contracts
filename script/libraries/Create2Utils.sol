// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {DeploymentConfig} from "script/config/DeploymentConfig.sol";
import {ISafeSingletonFactory} from "script/interfaces/ISafeSingletonFactory.sol";
import {Logger} from "script/libraries/Logger.sol";

/**
 * @title Create2Utils
 * @notice Helper library for deterministic CREATE2 deployments
 * @dev Abstracts differences between Arachnid and Safe Singleton Factory.
 *      Provides utilities for computing addresses, checking deployment status, and deploying.
 * @author Den Technologies Inc
 */
library Create2Utils {
    /// @dev Deploys a contract using CREATE2 if not already deployed
    ///      Handles differences between Arachnid and Safe Singleton Factory parameter ordering
    /// @param factoryAddress The CREATE2 factory address
    /// @param salt The deployment salt
    /// @param initCode The contract creation bytecode
    /// @param name Human-readable name for logging
    /// @return deployedAtAddress The address of the deployed (or existing) contract
    /// @return wasDeployed True if newly deployed, false if already existed
    function deployIfNotExists(address factoryAddress, bytes32 salt, bytes memory initCode, string memory name)
        internal
        returns (address deployedAtAddress, bool wasDeployed)
    {
        // Compute the predicted deployment address
        address predictedAddress = computeAddress(factoryAddress, salt, initCode);

        // Case: Contract already deployed
        // Log message and skip deployment
        if (isContractDeployedAtAddress(predictedAddress)) {
            Logger.logDeploymentSkipped(name, predictedAddress);
            return (predictedAddress, false);
        }

        // Deploy using appropriate factory interface
        deployedAtAddress = _deploy(factoryAddress, salt, initCode);

        // Case: Deployment failed
        require(deployedAtAddress != address(0), string.concat("Deployment failed: ", name));

        // Case: Deployment address mismatch
        require(deployedAtAddress == predictedAddress, "Deployed address does not match predicted address");

        // Log success
        Logger.logDeployed(name, deployedAtAddress);
        return (deployedAtAddress, true);
    }

    /// @dev Checks if a contract is deployed at the given address
    /// @param contractAddress The address to check
    /// @return deployed True if there is code at the address
    function isContractDeployedAtAddress(address contractAddress) internal view returns (bool deployed) {
        return contractAddress.code.length > 0;
    }

    /// @dev Validates that a factory is NOT deployed at the given address, reverts if it is
    /// @param factoryAddress The factory address to check
    /// @param factoryName Human-readable name for logging
    function validateFactoryNotDeployedOrRevert(address factoryAddress, string memory factoryName) internal view {
        Logger.logCheckStart(string.concat("Checking if ", factoryName, " already deployed..."));

        require(
            !isContractDeployedAtAddress(factoryAddress),
            string.concat(factoryName, " already deployed at ", Strings.toHexString(factoryAddress))
        );

        Logger.logCheckPass(string.concat(factoryName, " not deployed"));
    }

    /// @dev Validates that the deployer has sufficient ETH balance for deployment, reverts if not
    /// @param deployerAddress The address to check
    /// @param requiredBalance The minimum required balance in wei
    /// @param scriptName Name of the script for the fund command (e.g., "DeployArachnidFactory")
    function validateDeployerHasSufficientEthOrRevert(
        address deployerAddress,
        uint256 requiredBalance,
        string memory scriptName
    ) internal view {
        // Log the check start
        Logger.logCheckStart("Checking deployer ETH balance...");

        // Get the deployer's balance
        uint256 balance = deployerAddress.balance;

        // Case: Deployer has sufficient balance
        if (balance >= requiredBalance) {
            Logger.logCheckPass(string.concat("Deployer has sufficient ETH (", Strings.toString(balance), " wei)"));
            return;
        }

        // Case: Deployer does not have sufficient balance
        Logger.logCheckFail("Deployer needs more ETH");
        Logger.logCheckDetail(string.concat("Current: ", Strings.toString(balance), " wei"));
        Logger.logCheckDetail(string.concat("Required: ", Strings.toString(requiredBalance), " wei"));
        Logger.logEmptyLine();
        Logger.logCheckDetail("Fund the deployer by running:");
        Logger.logCheckDetail(string.concat("  forge script ", scriptName, " --sig \"fundDeployer()\" \\"));
        Logger.logCheckDetail("    --rpc-url $RPC_URL --broadcast");
        revert("Deployer has insufficient ETH");
    }

    /// @dev Validates that the deployer is NOT the production Safe Factory deployer
    function validateNotProductionSafeFactoryDeployerOrRevert() internal view {
        // Log the check start
        Logger.logCheckStart("Checking deployer is not production Safe Factory deployer...");

        // Case: Deployer is the production Safe Factory deployer
        if (msg.sender == DeploymentConfig.PROD_SAFE_FACTORY_DEPLOYER_ADDRESS) {
            Logger.logCheckFail("Deployer is the production Safe Factory deployer");
            Logger.logCheckDetail("This EOA should ONLY be used by DeploySafeSingletonFactory.");
            Logger.logCheckDetail("Use a different deployer for this script.");
            revert("Cannot use production Safe Factory deployer for this script");
        }

        // Case: Deployer is not the production Safe Factory deployer
        Logger.logCheckPass("Deployer is not production Safe Factory deployer");
    }

    /// @dev Computes the CREATE2 address for a contract deployment
    /// @param factoryAddress The CREATE2 factory address
    /// @param salt The deployment salt
    /// @param initCode The contract creation bytecode (including constructor args)
    /// @return The predicted deployment address
    function computeAddress(address factoryAddress, bytes32 salt, bytes memory initCode)
        internal
        pure
        returns (address)
    {
        return Create2.computeAddress(salt, keccak256(initCode), factoryAddress);
    }

    /// @dev Logs deployment summary header with factory and chain info
    /// @param factoryAddress The factory being used
    /// @param chainId The chain ID
    function logDeploymentHeader(address factoryAddress, uint256 chainId) internal pure {
        Logger.logBoxHeader("Den Multi-layer Security (MLS) Wallet - Contract Deployment");
        Logger.logKeyValue("Chain ID", chainId);
        Logger.logKeyValue("CREATE2 Factory", factoryAddress);

        if (factoryAddress == DeploymentConfig.ARACHNID_CREATE2_FACTORY_ADDRESS) {
            Logger.logKeyValue("Factory Type", "Arachnid Deterministic Deployment Proxy");
        } else if (factoryAddress == DeploymentConfig.PROD_SAFE_SINGLETON_FACTORY_ADDRESS) {
            Logger.logKeyValue("Factory Type", "Safe Singleton Factory (Production)");
        } else if (factoryAddress == DeploymentConfig.NON_PROD_SAFE_SINGLETON_FACTORY_ADDRESS) {
            Logger.logKeyValue("Factory Type", "Safe Singleton Factory (Non-Production)");
        } else {
            Logger.logKeyValue("Factory Type", "Custom");
        }

        Logger.logBoxFooter();
        Logger.logEmptyLine();
    }

    /// @dev Deploys using the appropriate factory interface based on factory address
    ///      Detects factory type and uses correct parameter ordering
    /// @param factoryAddress The CREATE2 factory address
    /// @param salt The deployment salt
    /// @param initCode The contract creation bytecode
    /// @return deployedAtAddress The deployed contract address
    function _deploy(address factoryAddress, bytes32 salt, bytes memory initCode)
        private
        returns (address deployedAtAddress)
    {
        // Case: using Safe Singleton Factory (prod or non-prod)
        if (
            factoryAddress == DeploymentConfig.PROD_SAFE_SINGLETON_FACTORY_ADDRESS
                || factoryAddress == DeploymentConfig.NON_PROD_SAFE_SINGLETON_FACTORY_ADDRESS
        ) {
            deployedAtAddress = address(ISafeSingletonFactory(factoryAddress).deploy(initCode, salt));
            return deployedAtAddress;
        }

        // Case: using Arachnid Deterministic Deployment Proxy
        // The Arachnid factory is a minimal proxy that expects raw calldata: salt (32 bytes) + initCode
        // It does NOT have a function selector - data is sent directly via low-level call
        // Returns the deployed address as raw 20 bytes (not ABI-encoded)
        if (factoryAddress == DeploymentConfig.ARACHNID_CREATE2_FACTORY_ADDRESS) {
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, bytes memory result) = factoryAddress.call(abi.encodePacked(salt, initCode));
            require(success, "Arachnid CREATE2 deployment failed");
            require(result.length == 20, "Arachnid CREATE2 returned invalid address");
            // Convert raw 20-byte return to address
            // Memory layout: [32-byte length][20-byte address data][12 bytes junk]
            // We load 32 bytes from the data section (offset 0x20), then shift right 96 bits (12 bytes)
            // to align the 20-byte address to the lower bytes
            // solhint-disable-next-line no-inline-assembly
            assembly {
                let rawData := mload(add(result, 0x20))
                deployedAtAddress := shr(96, rawData)
            }
            return deployedAtAddress;
        }

        // Case: using custom factory
        revert("Invalid factory address");
    }
}
