// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

import {DeploymentConfig} from "script/config/DeploymentConfig.sol";
import {Logger} from "script/libraries/Logger.sol";
import {ScriptUtils} from "script/libraries/ScriptUtils.sol";
import {StringUtils} from "script/libraries/StringUtils.sol";

/**
 * @title Create2Utils
 * @notice Helper library for deterministic CREATE2 deployments
 * @dev Abstracts differences between Arachnid and Den Singleton Factory.
 *      Provides utilities for computing addresses, checking deployment status, and deploying.
 *
 *      This library uses a floating pragma (>=0.7.0 <0.9.0) to allow reuse by both
 *      platform scripts (0.8.33) and Safe deployment scripts (0.7.6).
 *
 * @author Den Technologies Inc
 */
library Create2Utils {
    /// @dev Deploys a contract using CREATE2 if not already deployed
    ///      Handles differences between Arachnid and Den Singleton Factory parameter ordering
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
        require(deployedAtAddress != address(0), string(abi.encodePacked("Deployment failed: ", name)));

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
        // Use assembly for 0.7.x compatibility (address.code was added in 0.8.0)
        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            size := extcodesize(contractAddress)
        }
        return size > 0;
    }

    /// @dev Validates that a factory is NOT deployed at the given address, reverts if it is
    /// @param factoryAddress The factory address to check
    /// @param factoryName Human-readable name for logging
    function validateFactoryNotDeployedOrRevert(address factoryAddress, string memory factoryName) internal view {
        Logger.logCheckStart(string(abi.encodePacked("Checking if ", factoryName, " already deployed...")));

        require(
            !isContractDeployedAtAddress(factoryAddress),
            string(abi.encodePacked(factoryName, " already deployed at ", StringUtils.toHexString(factoryAddress)))
        );

        Logger.logCheckPass(string(abi.encodePacked(factoryName, " not deployed")));
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
            Logger.logCheckPass(
                string(abi.encodePacked("Deployer has sufficient ETH (", StringUtils.toString(balance), " wei)"))
            );
            return;
        }

        // Case: Deployer does not have sufficient balance
        Logger.logCheckFail("Deployer needs more ETH");
        Logger.logCheckDetail(string(abi.encodePacked("Current: ", StringUtils.toString(balance), " wei")));
        Logger.logCheckDetail(string(abi.encodePacked("Required: ", StringUtils.toString(requiredBalance), " wei")));
        Logger.logEmptyLine();
        Logger.logCheckDetail("Fund the deployer by running:");
        Logger.logCheckDetail(string(abi.encodePacked("  forge script ", scriptName, " --sig \"fundDeployer()\" \\")));
        Logger.logCheckDetail("    --rpc-url $RPC_URL --broadcast");
        revert("Deployer has insufficient ETH");
    }

    /// @dev Validates that the deployer is NOT the production Den Factory deployer
    function validateNotProductionDenFactoryDeployerOrRevert() internal view {
        // Log the check start
        Logger.logCheckStart("Checking deployer is not production Den Factory deployer...");

        // Case: Deployer is the production Den Factory deployer
        if (msg.sender == DeploymentConfig.PROD_DEN_FACTORY_DEPLOYER_ADDRESS) {
            Logger.logCheckFail("Deployer is the production Den Factory deployer");
            Logger.logCheckDetail("This EOA should ONLY be used by DeployDenSingletonFactory.");
            Logger.logCheckDetail("Use a different deployer for this script.");
            revert("Cannot use production Den Factory deployer for this script");
        }

        // Case: Deployer is not the production Den Factory deployer
        Logger.logCheckPass("Deployer is not production Den Factory deployer");
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
        return ScriptUtils.computeCreate2Address(salt, keccak256(initCode), factoryAddress);
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
        } else if (factoryAddress == DeploymentConfig.PROD_DEN_SINGLETON_FACTORY_ADDRESS) {
            Logger.logKeyValue("Factory Type", "Den Singleton Factory (Production)");
        } else if (factoryAddress == DeploymentConfig.NON_PROD_DEN_SINGLETON_FACTORY_ADDRESS) {
            Logger.logKeyValue("Factory Type", "Den Singleton Factory (Non-Production)");
        } else {
            Logger.logKeyValue("Factory Type", "Custom");
        }

        Logger.logBoxFooter();
        Logger.logEmptyLine();
    }

    /// @dev Deploys using a minimal CREATE2 factory
    ///      All supported factories (Arachnid, Den Singleton Factory) expect raw calldata: salt (32 bytes) + initCode
    ///      They return the deployed address as raw 20 bytes (not ABI-encoded)
    /// @param factoryAddress The CREATE2 factory address
    /// @param salt The deployment salt
    /// @param initCode The contract creation bytecode
    /// @return deployedAtAddress The deployed contract address
    function _deploy(address factoryAddress, bytes32 salt, bytes memory initCode)
        private
        returns (address deployedAtAddress)
    {
        // Validate factory address upfront
        require(
            factoryAddress == DeploymentConfig.ARACHNID_CREATE2_FACTORY_ADDRESS
                || factoryAddress == DeploymentConfig.PROD_DEN_SINGLETON_FACTORY_ADDRESS
                || factoryAddress == DeploymentConfig.NON_PROD_DEN_SINGLETON_FACTORY_ADDRESS,
            "Invalid factory address"
        );

        // All supported factories are minimal CREATE2 factories that expect raw calldata: salt (32 bytes) + initCode
        // They do NOT have function selectors - data is sent directly via low-level call
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory result) = factoryAddress.call(abi.encodePacked(salt, initCode));
        require(success, "CREATE2 factory deployment failed");
        require(result.length == 20, "CREATE2 factory returned invalid address");

        // Convert raw 20-byte return to address
        // Memory layout: [32-byte length][20-byte address data][12 bytes junk]
        // We load 32 bytes from the data section (offset 0x20), then shift right 96 bits (12 bytes)
        // to align the 20-byte address to the lower bytes
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let rawData := mload(add(result, 0x20))
            deployedAtAddress := shr(96, rawData)
        }
    }
}
