// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Vm} from "forge-std/Vm.sol";

import {DeploymentConfig} from "script/config/DeploymentConfig.sol";
import {ICreate2Factory, ISafeSingletonFactory} from "script/interfaces/ICreate2Factory.sol";
import {Logger} from "script/libraries/Logger.sol";

/**
 * @title Create2Deployer
 * @notice Helper library for deterministic CREATE2 deployments
 * @dev Abstracts differences between Arachnid and Safe Singleton Factory.
 *      Provides utilities for computing addresses, checking deployment status, and deploying.
 * @author Den Technologies Inc
 */
library Create2Deployer {
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
            Logger.logDeploymentSkipped(name, predicted);
            return (predicted, false);
        }

        // Deploy using appropriate factory interface
        deployedAtAddress = _deploy(factory, salt, initCode);

        // Case: Deployment failed
        require(deployedAtAddress != address(0), string.concat("Deployment failed: ", name));

        // Case: Deployment address mismatch
        require(deployedAtAddress == predicted, "Deployed address does not match predicted address");

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

    /// @dev Retrieves the CREATE2 factory address from environment variable
    ///      Requires CREATE2_FACTORY_ADDRESS to be explicitly set
    /// @param vm The Forge Vm interface for accessing environment variables
    /// @return factory Address of the CREATE2 factory
    function getCreate2Factory(Vm vm) internal view returns (address factory) {
        // Require explicit factory address from environment variable
        try vm.envAddress("CREATE2_FACTORY_ADDRESS") returns (address provided) {
            require(provided != address(0), "CREATE2_FACTORY_ADDRESS is set to zero address");
            require(isContractDeployedAtAddress(provided), "CREATE2 factory not deployed at provided address");
            return provided;
        } catch {
            revert("CREATE2_FACTORY_ADDRESS environment variable not set");
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
        Logger.logCheckStart(checkNumber, string.concat("Checking if ", factoryName, " already deployed..."));
        if (isContractDeployedAtAddress(factoryAddress)) {
            Logger.logCheckInfo(string.concat("Factory already deployed at ", _addressToString(factoryAddress)));
            Logger.logCheckDetail("No deployment needed. Set CREATE2_FACTORY_ADDRESS to use it.");
            return true;
        } else {
            Logger.logCheckPass("Factory not yet deployed");
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
        Logger.logCheckStart(checkNumber, "Checking deployer ETH balance...");
        uint256 balance = deployer.balance;
        if (balance >= requiredBalance) {
            Logger.logCheckPass(string.concat("Deployer has sufficient ETH (", _uintToString(balance), " wei)"));
            return true;
        } else {
            Logger.logCheckFail("Deployer needs more ETH");
            Logger.logCheckDetail(string.concat("Current: ", _uintToString(balance), " wei"));
            Logger.logCheckDetail(string.concat("Required: ", _uintToString(requiredBalance), " wei"));
            Logger.logEmptyLine();
            Logger.logCheckDetail("Fund the deployer by running:");
            Logger.logCheckDetail(string.concat("  forge script ", scriptName, " --sig \"fundDeployer()\" \\"));
            Logger.logCheckDetail("    --rpc-url $RPC_URL --broadcast");
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
        Logger.logBoxHeader("Den Multi-layer Security (MLS) Wallet - Contract Deployment");
        Logger.logKeyUint("Chain ID", chainId);
        Logger.logKeyAddress("CREATE2 Factory", factory);

        if (factory == DeploymentConfig.ARACHNID_CREATE2_FACTORY) {
            Logger.logKeyValue("Factory Type", "Arachnid Deterministic Deployment Proxy");
        } else if (factory == DeploymentConfig.SAFE_SINGLETON_FACTORY) {
            Logger.logKeyValue("Factory Type", "Safe Singleton Factory");
        } else {
            Logger.logKeyValue("Factory Type", "Custom");
        }

        Logger.logBoxFooter();
        Logger.logEmptyLine();
    }

    /// @dev Logs a section header for organized console output
    /// @param sectionName The name of the deployment section
    function logSection(string memory sectionName) internal pure {
        Logger.logSection(sectionName);
    }

    /// @dev Logs deployment completion summary
    function logDeploymentComplete() internal pure {
        Logger.logDeploymentComplete();
    }

    // =========================================================================
    // Factory Deployment Helpers
    // =========================================================================

    /// @dev Logs a factory deployment script header
    /// @param factoryName Human-readable name of the factory being deployed
    function logFactoryDeploymentHeader(string memory factoryName) internal pure {
        Logger.logBoxHeader(string.concat(factoryName, " - Factory Deployment"));
        Logger.logEmptyLine();
    }

    /// @dev Logs the dry run mode message with script-specific instructions
    /// @param scriptName Name of the script for the CONFIRM_DEPLOYMENT command
    /// @param additionalNotes Optional additional notes to display (can be empty string)
    function logDryRunMode(string memory scriptName, string memory additionalNotes) internal pure {
        Logger.logDryRunMode(scriptName, additionalNotes);
    }

    /// @dev Logs a successful factory deployment with next steps
    /// @param factoryName Human-readable name of the deployed factory
    /// @param factoryAddress Address where the factory was deployed
    function logFactoryDeploymentSuccess(string memory factoryName, address factoryAddress) internal pure {
        Logger.logDeploymentSuccess(factoryName, factoryAddress, "CREATE2_FACTORY_ADDRESS");
    }

    /// @dev Logs safety checks failed message
    function logSafetyChecksFailed() internal pure {
        Logger.logSafetyChecksFailed();
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

    /// @dev Converts an address to a string for logging
    /// @param addr The address to convert
    /// @return The address as a hex string
    function _addressToString(address addr) private pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 20; ++i) {
            str[2 + i * 2] = alphabet[uint8(uint160(addr) >> (8 * (19 - i)) >> 4)];
            str[3 + i * 2] = alphabet[uint8(uint160(addr) >> (8 * (19 - i))) & 0x0f];
        }
        return string(str);
    }

    /// @dev Converts a uint256 to a string for logging
    /// @param value The value to convert
    /// @return The value as a decimal string
    function _uintToString(uint256 value) private pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            ++digits;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            --digits;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
