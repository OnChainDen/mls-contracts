// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {console} from "forge-std/console.sol";

import {DeploymentConfig} from "script/config/DeploymentConfig.sol";
import {ICreate2Factory, ISafeSingletonFactory} from "script/interfaces/ICreate2Factory.sol";

/**
 * @title Create2Deployer
 * @notice Helper library for deterministic CREATE2 deployments
 * @dev Abstracts differences between Arachnid and Safe Singleton Factory.
 *      Provides utilities for computing addresses, checking deployment status, and deploying.
 * @author Den Technologies Inc
 */
library Create2Deployer {
    /// @dev Error thrown when deployment fails
    error DeploymentFailed(string name, bytes32 salt);

    /// @dev Error thrown when deployed address doesn't match predicted
    error AddressMismatch(address predicted, address actual);

    /// @dev Deploys a contract using CREATE2 if not already deployed
    ///      Handles differences between Arachnid and Safe Singleton Factory parameter ordering
    /// @param factory The CREATE2 factory address
    /// @param salt The deployment salt
    /// @param initCode The contract creation bytecode
    /// @param name Human-readable name for logging
    /// @return deployedAtAddress The address of the deployed (or existing) contract
    /// @return wasDeployed True if newly deployed, false if already existed
    function deployIfNotExists(address factory, bytes32 salt, bytes memory initCode, string memory name)
        internal
        returns (address deployedAtAddress, bool wasDeployed)
    {
        address predicted = computeAddress(factory, salt, initCode);

        // Check if already deployed
        if (isContractDeployedAtAddress(predicted)) {
            console.log(unicode"  ⏭️  SKIPPED: %s (already deployed at %s)", name, predicted);
            return (predicted, false);
        }

        // Deploy using appropriate factory interface
        deployedAtAddress = _deploy(factory, salt, initCode);

        // Verify deployment
        if (deployedAtAddress == address(0)) {
            revert DeploymentFailed(name, salt);
        }

        if (deployedAtAddress != predicted) {
            revert AddressMismatch(predicted, deployedAtAddress);
        }

        console.log(unicode"  ✅ DEPLOYED: %s at %s", name, deployedAtAddress);
        return (deployedAtAddress, true);
    }

    /// @dev Batch deploys multiple contracts via CREATE2
    /// @param factory The CREATE2 factory address
    /// @param salts Array of deployment salts
    /// @param initCodes Array of contract creation bytecodes
    /// @param names Array of human-readable names for logging
    /// @return addresses Array of deployed addresses
    function batchDeploy(address factory, bytes32[] memory salts, bytes[] memory initCodes, string[] memory names)
        internal
        returns (address[] memory addresses)
    {
        require(salts.length == initCodes.length && initCodes.length == names.length, "Array length mismatch");

        addresses = new address[](salts.length);
        for (uint256 i = 0; i < salts.length; ++i) {
            (addresses[i],) = deployIfNotExists(factory, salts[i], initCodes[i], names[i]);
        }
    }

    /// @dev Checks if a contract is already deployed at the predicted address
    /// @param factory The CREATE2 factory address
    /// @param salt The deployment salt
    /// @param initCode The contract creation bytecode
    /// @return isDeployedAtAddress True if contract exists at the predicted address
    /// @return predicted The predicted address
    function isDeployed(address factory, bytes32 salt, bytes memory initCode)
        internal
        view
        returns (bool isDeployedAtAddress, address predicted)
    {
        predicted = computeAddress(factory, salt, initCode);
        isDeployedAtAddress = isContractDeployedAtAddress(predicted);
    }

    /// @dev Checks if a contract is deployed at the given address
    /// @param contractAddress The address to check
    /// @return deployed True if there is code at the address
    function isContractDeployedAtAddress(address contractAddress) internal view returns (bool deployed) {
        return contractAddress.code.length > 0;
    }

    /// @dev Gets the best available CREATE2 factory
    ///      Prefers Arachnid factory, falls back to Safe Singleton Factory
    /// @return factory The available factory address (address(0) if none)
    /// @return factoryName Human-readable factory name
    function getAvailableFactory() internal view returns (address factory, string memory factoryName) {
        // Prefer Arachnid as it's more widely deployed
        if (isContractDeployedAtAddress(DeploymentConfig.ARACHNID_CREATE2_FACTORY)) {
            return (DeploymentConfig.ARACHNID_CREATE2_FACTORY, "Arachnid");
        }

        if (isContractDeployedAtAddress(DeploymentConfig.SAFE_SINGLETON_FACTORY)) {
            return (DeploymentConfig.SAFE_SINGLETON_FACTORY, "Safe Singleton Factory");
        }

        // No factory available
        return (address(0), "None");
    }

    /// @dev Computes the CREATE2 address for a contract deployment
    /// @param factory The CREATE2 factory address
    /// @param salt The deployment salt
    /// @param initCode The contract creation bytecode (including constructor args)
    /// @return The predicted deployment address
    function computeAddress(address factory, bytes32 salt, bytes memory initCode) internal pure returns (address) {
        return Create2.computeAddress(salt, keccak256(initCode), factory);
    }

    /// @dev Logs deployment summary header with factory and chain info
    /// @param factory The factory being used
    /// @param chainId The chain ID
    function logDeploymentHeader(address factory, uint256 chainId) internal pure {
        console.log("");
        console.log("================================================================================");
        console.log("  Den Multi-layer Security (MLS) Wallet - Contract Deployment");
        console.log("================================================================================");
        console.log("  Chain ID: %s", chainId);
        console.log("  CREATE2 Factory: %s", factory);

        if (factory == DeploymentConfig.ARACHNID_CREATE2_FACTORY) {
            console.log("  Factory Type: Arachnid Deterministic Deployment Proxy");
        } else if (factory == DeploymentConfig.SAFE_SINGLETON_FACTORY) {
            console.log("  Factory Type: Safe Singleton Factory");
        } else {
            console.log("  Factory Type: Custom");
        }

        console.log("================================================================================");
        console.log("");
    }

    /// @dev Logs a section header for organized console output
    /// @param sectionName The name of the deployment section
    function logSection(string memory sectionName) internal pure {
        console.log("");
        console.log("--------------------------------------------------------------------------------");
        console.log("  %s", sectionName);
        console.log("--------------------------------------------------------------------------------");
    }

    /// @dev Logs deployment completion summary
    function logDeploymentComplete() internal pure {
        console.log("");
        console.log("================================================================================");
        console.log(unicode"  ✅ Deployment Complete!");
        console.log("================================================================================");
        console.log("");
    }

    /// @dev Deploys using the appropriate factory interface based on factory address
    ///      Detects factory type and uses correct parameter ordering
    /// @param factory The CREATE2 factory address
    /// @param salt The deployment salt
    /// @param initCode The contract creation bytecode
    /// @return deployedAtAddress The deployed contract address
    function _deploy(address factory, bytes32 salt, bytes memory initCode) private returns (address deployedAtAddress) {
        // Safe Singleton Factory has different parameter order: deploy(bytes, bytes32)
        if (factory == DeploymentConfig.SAFE_SINGLETON_FACTORY) {
            deployedAtAddress = address(ISafeSingletonFactory(factory).deploy(initCode, salt));
        } else {
            // Arachnid and similar: deploy(bytes32, bytes)
            deployedAtAddress = ICreate2Factory(factory).deploy(salt, initCode);
        }
    }
}
