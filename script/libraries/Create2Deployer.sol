// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Vm} from "forge-std/Vm.sol";
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

    /// @dev Error thrown when no CREATE2 factory is available
    error NoCreate2FactoryAvailable();

    /// @dev Error thrown when CREATE2_FACTORY_ADDRESS env var is not set
    error Create2FactoryEnvNotSet();

    /// @dev Error thrown when factory address from env var has no code deployed
    error Create2FactoryNotDeployed(address attempted);

    /// @dev Error thrown when safety checks fail during factory deployment
    error SafetyChecksFailed();

    /// @dev Error thrown when factory deployment fails
    error FactoryDeploymentFailed();

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

        // Case: Contract already deployed
        // Log message and skip deployment
        if (isContractDeployedAtAddress(predicted)) {
            console.log(unicode"  ⏭️  SKIPPED: %s (already deployed at %s)", name, predicted);
            return (predicted, false);
        }

        // Deploy using appropriate factory interface
        deployedAtAddress = _deploy(factory, salt, initCode);

        // Case: Deployment failed
        // Revert with error
        if (deployedAtAddress == address(0)) {
            revert DeploymentFailed(name, salt);
        }

        // Case: Deployment address mismatch
        // Revert with error
        if (deployedAtAddress != predicted) {
            revert AddressMismatch(predicted, deployedAtAddress);
        }

        // Log success
        console.log(unicode"  ✅ DEPLOYED: %s at %s", name, deployedAtAddress);
        return (deployedAtAddress, true);
    }

    /// @dev Checks if a contract is deployed at the given address
    /// @param contractAddress The address to check
    /// @return deployed True if there is code at the address
    function isContractDeployedAtAddress(address contractAddress) internal view returns (bool deployed) {
        return contractAddress.code.length > 0;
    }

    /// @dev Retrieves the CREATE2 factory address from environment variable
    ///      Requires CREATE2_FACTORY_ADDRESS to be explicitly set
    /// @param vm The Forge Vm interface for accessing environment variables
    /// @return factory Address of the CREATE2 factory
    function getCreate2Factory(Vm vm) internal view returns (address factory) {
        // Require explicit factory address from environment variable
        try vm.envAddress("CREATE2_FACTORY_ADDRESS") returns (address provided) {
            if (provided == address(0)) {
                revert NoCreate2FactoryAvailable();
            }
            if (!isContractDeployedAtAddress(provided)) {
                revert Create2FactoryNotDeployed(provided);
            }
            return provided;
        } catch {
            revert Create2FactoryEnvNotSet();
        }
    }

    /// @dev Checks if a factory is already deployed and logs the result
    /// @param factoryAddress The factory address to check
    /// @param factoryName Human-readable name for logging
    /// @param checkNumber The check number for logging (e.g., "1/2")
    /// @return alreadyDeployed True if factory exists at the address
    function checkFactoryNotDeployed(address factoryAddress, string memory factoryName, string memory checkNumber)
        internal
        view
        returns (bool alreadyDeployed)
    {
        console.log("  [%s] Checking if %s already deployed...", checkNumber, factoryName);
        if (isContractDeployedAtAddress(factoryAddress)) {
            console.log(unicode"       ⏭️  INFO: Factory already deployed at %s", factoryAddress);
            console.log("              No deployment needed. Set CREATE2_FACTORY_ADDRESS to use it.");
            return true;
        } else {
            console.log(unicode"       ✅ PASS: Factory not yet deployed");
            return false;
        }
    }

    /// @dev Checks if an address has sufficient ETH balance and logs the result
    /// @param deployer The address to check
    /// @param requiredBalance The minimum required balance in wei
    /// @param checkNumber The check number for logging (e.g., "2/2")
    /// @param scriptName Name of the script for the fund command (e.g., "DeployArachnidFactory")
    /// @return hasSufficientBalance True if balance is sufficient
    function checkDeployerBalance(
        address deployer,
        uint256 requiredBalance,
        string memory checkNumber,
        string memory scriptName
    ) internal view returns (bool hasSufficientBalance) {
        console.log("  [%s] Checking deployer ETH balance...", checkNumber);
        uint256 balance = deployer.balance;
        if (balance >= requiredBalance) {
            console.log(unicode"       ✅ PASS: Deployer has sufficient ETH (%s wei)", balance);
            return true;
        } else {
            console.log(unicode"       ❌ FAIL: Deployer needs more ETH");
            console.log("              Current: %s wei", balance);
            console.log("              Required: %s wei", requiredBalance);
            console.log("");
            console.log("              Fund the deployer by running:");
            console.log("                forge script %s --sig \"fundDeployer()\" \\", scriptName);
            console.log("                  --rpc-url $RPC_URL --broadcast");
            return false;
        }
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

    // =========================================================================
    // Factory Deployment Helpers
    // =========================================================================

    /// @dev Logs a factory deployment script header
    /// @param factoryName Human-readable name of the factory being deployed
    function logFactoryDeploymentHeader(string memory factoryName) internal pure {
        console.log("");
        console.log("================================================================================");
        console.log("  %s - Factory Deployment", factoryName);
        console.log("================================================================================");
        console.log("");
    }

    /// @dev Logs the dry run mode message with script-specific instructions
    /// @param scriptName Name of the script for the CONFIRM_DEPLOYMENT command
    /// @param additionalNotes Optional additional notes to display (can be empty string)
    function logDryRunMode(string memory scriptName, string memory additionalNotes) internal pure {
        console.log("");
        console.log("--------------------------------------------------------------------------------");
        console.log("  DRY RUN MODE");
        console.log("--------------------------------------------------------------------------------");
        console.log("");
        console.log("  All safety checks passed. To deploy, run with:");
        console.log("");
        console.log("    CONFIRM_DEPLOYMENT=true forge script %s ...", scriptName);
        console.log("");
        if (bytes(additionalNotes).length > 0) {
            console.log("  %s", additionalNotes);
            console.log("");
        }
    }

    /// @dev Logs a successful factory deployment with next steps
    /// @param factoryName Human-readable name of the deployed factory
    /// @param factoryAddress Address where the factory was deployed
    function logFactoryDeploymentSuccess(string memory factoryName, address factoryAddress) internal pure {
        console.log("");
        console.log(unicode"  ✅ %s deployed successfully!", factoryName);
        console.log("     Address: %s", factoryAddress);
        console.log("");
        console.log("  Next step: Set the factory address in your environment:");
        console.log("    export CREATE2_FACTORY_ADDRESS=%s", factoryAddress);
        console.log("");
    }

    /// @dev Logs safety checks failed message
    function logSafetyChecksFailed() internal pure {
        console.log("");
        console.log(unicode"  ❌ SAFETY CHECKS FAILED - Deployment aborted");
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
