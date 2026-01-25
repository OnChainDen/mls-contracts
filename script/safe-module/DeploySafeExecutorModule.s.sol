// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Script} from "forge-std/Script.sol";

import {SafeExecutorModule} from "../../src/safe-module/SafeExecutorModule.sol";
import {DeploymentConfig} from "script/config/DeploymentConfig.sol";
import {Create2Utils} from "script/libraries/Create2Utils.sol";
import {Logger} from "script/libraries/Logger.sol";
import {ScriptUtils} from "script/libraries/ScriptUtils.sol";
import {StringUtils} from "script/libraries/StringUtils.sol";

/**
 * @title DeploySafeExecutorModule
 * @notice Deploys a SafeExecutorModule for the Guardian or Deployer Safe via CREATE2
 * @dev This script deploys a minimal Safe module that allows a designated EOA (the "Safe Executor EOA")
 *      to execute contract calls on behalf of a Safe multisig.
 *
 *      Usage:
 *        forge script script/safe-module/DeploySafeExecutorModule.s.sol:DeploySafeExecutorModule \
 *          --sig "run(address,string,address)" <FACTORY_ADDRESS> <TARGET> <EXECUTOR_ADDRESS> \
 *          --rpc-url $RPC_URL \
 *          --broadcast \
 *          -vvvv
 *
 *      Where:
 *        - FACTORY_ADDRESS: The CREATE2 factory to use (Arachnid or Den Singleton Factory)
 *        - TARGET: "guardian" or "deployer" - which Safe to deploy the module for
 *        - EXECUTOR_ADDRESS: The Safe Executor EOA that will be authorized to execute transactions
 *
 *      SAFETY CHECKS:
 *      1. Verifies the provided CREATE2 factory address is not zero
 *      2. Verifies the provided CREATE2 factory address is deployed
 *      3. Verifies the target is valid ("guardian" or "deployer")
 *      4. Verifies the executor address matches the expected address in DeploymentConfig
 *      5. Verifies the Safe is deployed at the expected address
 *      6. Verifies the deployer is not the production Den Factory deployer
 *      7. Requires interactive confirmation when broadcasting
 *
 * @author Den Technologies Inc
 */
contract DeploySafeExecutorModule is Script {
    /**
     * @notice Main entry point - deploys a SafeExecutorModule via CREATE2
     * @param factoryAddress Address of the CREATE2 factory to use for deployment
     * @param target "guardian" or "deployer" - which Safe to deploy the module for
     * @param executorAddress The Safe Executor EOA that will be authorized to execute transactions
     */
    function run(address factoryAddress, string calldata target, address executorAddress) external {
        // Validate the provided CREATE2 factory address
        require(factoryAddress != address(0), "Factory address cannot be zero");
        require(
            Create2Utils.isContractDeployedAtAddress(factoryAddress), "CREATE2 factory not deployed at provided address"
        );

        // Validate target is "guardian" or "deployer"
        bool isGuardian = _isGuardianTarget(target);

        // Validate executor address matches expected configuration
        require(executorAddress != address(0), "Executor address cannot be zero");
        _validateExecutorAddressOrRevert(block.chainid, isGuardian, executorAddress);

        // Get the Safe address for this target
        address safeAddress = _getSafeAddress(factoryAddress, isGuardian);
        require(Create2Utils.isContractDeployedAtAddress(safeAddress), "Safe not deployed at expected address");

        // Prompt for confirmation when running with --broadcast
        ScriptUtils.confirmBroadcastOrDryRun(vm, "DeploySafeExecutorModule");

        // Prevent using the production Den Factory deployer for this script
        Create2Utils.validateNotProductionDenFactoryDeployerOrRevert();

        // Log the deployment header
        Logger.logBoxHeader("Safe Executor Module Deployment");
        Logger.logKeyValue("Chain ID", block.chainid);
        Logger.logKeyValue("CREATE2 Factory", factoryAddress);
        Logger.logKeyValue("Deployer EOA", msg.sender);
        Logger.logKeyValue("Target", target);
        Logger.logKeyValue("Safe Address", safeAddress);
        Logger.logKeyValue("Safe Executor EOA", executorAddress);
        Logger.logEmptyLine();

        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy the module
        address moduleAddress = _deployModule(factoryAddress, isGuardian, safeAddress, executorAddress);

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Log the result
        Logger.logDeploymentComplete();
        Logger.logBoxHeader("Deployed Module Address");
        Logger.logKeyValue("SafeExecutorModule", moduleAddress);
        Logger.logEmptyLine();
        Logger.logBoxFooter();

        // Log next steps
        _logNextSteps(target, safeAddress, moduleAddress);
    }

    /**
     * @notice Compute and print module address without deploying
     * @param factoryAddress Address of the CREATE2 factory to use for address computation
     * @param target "guardian" or "deployer" - which Safe to compute the module address for
     * @param executorAddress The Safe Executor EOA that will be authorized to execute transactions
     */
    function computeAddress(address factoryAddress, string calldata target, address executorAddress) external view {
        // Validate the provided CREATE2 factory address
        require(factoryAddress != address(0), "Factory address cannot be zero");
        require(
            Create2Utils.isContractDeployedAtAddress(factoryAddress), "CREATE2 factory not deployed at provided address"
        );

        // Validate target
        bool isGuardian = _isGuardianTarget(target);

        // Validate executor address
        require(executorAddress != address(0), "Executor address cannot be zero");

        // Get the Safe address for this target
        address safeAddress = _getSafeAddress(factoryAddress, isGuardian);

        // Compute the module address
        bytes memory initCode = _getInitCode(safeAddress, executorAddress);
        bytes32 salt = _getSalt(isGuardian);
        address expectedAddress = Create2Utils.computeAddress(factoryAddress, salt, initCode);

        // Log the computed address
        Logger.logBoxHeader("Computed SafeExecutorModule Address");
        Logger.logKeyValue("Chain ID", block.chainid);
        Logger.logKeyValue("CREATE2 Factory", factoryAddress);
        Logger.logKeyValue("Target", target);
        Logger.logKeyValue("Safe Address", safeAddress);
        Logger.logKeyValue("Safe Executor EOA", executorAddress);
        Logger.logEmptyLine();
        Logger.logKeyValue("Expected Module Address", expectedAddress);

        // Check if already deployed
        if (Create2Utils.isContractDeployedAtAddress(expectedAddress)) {
            Logger.logKeyValue("Status", "ALREADY DEPLOYED");
        } else {
            Logger.logKeyValue("Status", "NOT DEPLOYED");
        }

        Logger.logEmptyLine();
        Logger.logBoxFooter();
    }

    /// @dev Validates that the provided executor address matches the expected address for the target
    /// @param chainId The target chain ID
    /// @param isGuardian True if validating for Guardian Safe, false for Deployer Safe
    /// @param executorAddress The executor address to validate
    function _validateExecutorAddressOrRevert(uint256 chainId, bool isGuardian, address executorAddress) internal pure {
        (address expectedGuardian, address expectedDeployer) = DeploymentConfig.getExpectedExecutorEOAAddresses(chainId);

        address expected = isGuardian ? expectedGuardian : expectedDeployer;
        require(executorAddress == expected, "Invalid executor address for target");
    }

    /// @dev Validates and parses the target string
    /// @param target The target string ("guardian" or "deployer")
    /// @return isGuardian True if target is "guardian", false if "deployer"
    function _isGuardianTarget(string calldata target) internal pure returns (bool isGuardian) {
        bytes32 targetHash = keccak256(bytes(target));
        if (targetHash == keccak256("guardian")) {
            return true;
        }
        if (targetHash == keccak256("deployer")) {
            return false;
        }
        revert("Invalid target - must be 'guardian' or 'deployer'");
    }

    /// @dev Gets the Safe address for the given target and factory
    /// @param factoryAddress The CREATE2 factory address
    /// @param isGuardian True for Guardian Safe, false for Deployer Safe
    /// @return safeAddress The Safe address
    function _getSafeAddress(address factoryAddress, bool isGuardian) internal pure returns (address safeAddress) {
        if (isGuardian) {
            return DeploymentConfig.getExpectedGuardianSafeAddress(factoryAddress);
        }
        return DeploymentConfig.getExpectedDeployerSafeAddress(factoryAddress);
    }

    /// @dev Gets the salt for the given target
    /// @param isGuardian True for Guardian Safe module, false for Deployer Safe module
    /// @return salt The CREATE2 salt
    function _getSalt(bool isGuardian) internal pure returns (bytes32 salt) {
        if (isGuardian) {
            return DeploymentConfig.GUARDIAN_SAFE_EXECUTOR_MODULE_SALT;
        }
        return DeploymentConfig.DEPLOYER_SAFE_EXECUTOR_MODULE_SALT;
    }

    /// @dev Constructs the init code for the module deployment
    /// @param safeAddress The Safe address
    /// @param executorAddress The Safe Executor EOA address
    /// @return initCode The init code (creation code + constructor args)
    function _getInitCode(address safeAddress, address executorAddress) internal pure returns (bytes memory initCode) {
        return abi.encodePacked(type(SafeExecutorModule).creationCode, abi.encode(safeAddress, executorAddress));
    }

    /// @dev Deploys the SafeExecutorModule via CREATE2
    /// @param factoryAddress The CREATE2 factory address
    /// @param isGuardian True for Guardian Safe module, false for Deployer Safe module
    /// @param safeAddress The Safe address
    /// @param executorAddress The Safe Executor EOA address
    /// @return moduleAddress The deployed module address
    function _deployModule(address factoryAddress, bool isGuardian, address safeAddress, address executorAddress)
        internal
        returns (address moduleAddress)
    {
        bytes32 salt = _getSalt(isGuardian);
        bytes memory initCode = _getInitCode(safeAddress, executorAddress);
        string memory name = isGuardian ? "Guardian SafeExecutorModule" : "Deployer SafeExecutorModule";

        Logger.logSection("SafeExecutorModule (CREATE2)");

        (moduleAddress,) = Create2Utils.deployIfNotExists(factoryAddress, salt, initCode, name);

        return moduleAddress;
    }

    /// @dev Logs the next steps after deployment
    /// @param target The target ("guardian" or "deployer")
    /// @param safeAddress The Safe address
    /// @param moduleAddress The deployed module address
    function _logNextSteps(string calldata target, address safeAddress, address moduleAddress) internal pure {
        Logger.logBoxHeader("NEXT STEP: Add the module to the Safe");
        Logger.logIndented("Safe owners must approve adding the module. Run:");
        Logger.logEmptyLine();
        Logger.logIndented(
            string(
                abi.encodePacked(
                    "make safe-add-module TARGET=", target, " EXECUTE=true NETWORK=<network> ACCOUNT=<safe-owner>"
                )
            )
        );
        Logger.logEmptyLine();
        Logger.logIndented(string(abi.encodePacked("Safe: ", StringUtils.toHexString(safeAddress))));
        Logger.logIndented(string(abi.encodePacked("Module: ", StringUtils.toHexString(moduleAddress))));
        Logger.logEmptyLine();
        Logger.logBoxFooter();
    }
}
