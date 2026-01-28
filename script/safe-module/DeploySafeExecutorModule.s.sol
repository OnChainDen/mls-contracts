// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {SafeExecutorModule} from "../../src/safe-module/SafeExecutorModule.sol";
import {BaseDeployScript} from "script/BaseDeployScript.sol";
import {Create2Utils} from "script/libraries/Create2Utils.sol";
import {Logger} from "script/libraries/Logger.sol";
import {StringUtils} from "script/libraries/StringUtils.sol";

/**
 * @title DeploySafeExecutorModule
 * @notice Deploys a SafeExecutorModule for the Guardian or Deployer Safe via CREATE2
 * @dev This script deploys a minimal Safe module that allows a designated EOA (the "Safe Executor EOA")
 *      to execute contract calls on behalf of a Safe multisig.
 *
 *      Usage:
 *        forge script script/safe-module/DeploySafeExecutorModule.s.sol:DeploySafeExecutorModule \
 *          --sig "run(address,string,address)" <FACTORY_ADDRESS> <SAFE_TYPE> <EXECUTOR_ADDRESS> \
 *          --rpc-url $RPC_URL \
 *          --broadcast \
 *          -vvvv
 *
 *      Where:
 *        - FACTORY_ADDRESS: The CREATE2 factory to use (Arachnid or Den Singleton Factory)
 *        - SAFE_TYPE: "guardian" or "deployer" - which Safe to deploy the module for
 *        - EXECUTOR_ADDRESS: The Safe Executor EOA that will be authorized to execute transactions
 *
 *      SAFETY CHECKS:
 *      1. Verifies the provided CREATE2 factory is a known factory from deployment.toml
 *      2. Verifies the provided CREATE2 factory is deployed
 *      3. Verifies the safeType is valid ("guardian" or "deployer")
 *      4. Verifies the executor address matches the expected address in deployment.toml
 *      5. Verifies the Safe is deployed at the expected address
 *      6. Verifies the BatchedTransaction is deployed at the expected address
 *      7. Verifies the deployer is not the production Den Factory deployer
 *      8. Requires interactive confirmation when broadcasting
 *
 * @author Den Technologies Inc
 */
contract DeploySafeExecutorModule is BaseDeployScript {
    /**
     * @notice Main entry point - deploys a SafeExecutorModule via CREATE2
     * @param factoryAddress Address of the CREATE2 factory to use for deployment
     * @param safeType "guardian" or "deployer" - which Safe to deploy the module for
     * @param executorAddress The Safe Executor EOA that will be authorized to execute transactions
     */
    function run(address factoryAddress, string calldata safeType, address executorAddress) external {
        // Initialize and validate the factory (stores address/name for use throughout)
        validateAndInitializeFactoryOrRevert(factoryAddress);

        // Validate safeType is "guardian" or "deployer"
        bool isGuardian = _isGuardianSafeType(safeType);

        // Validate executor address matches expected configuration
        require(executorAddress != address(0), "Executor address cannot be zero");
        _validateExecutorAddressOrRevert(isGuardian, executorAddress);

        // Get the Safe address for this safeType
        address safeAddress = _getSafeAddress(isGuardian);
        require(Create2Utils.isContractDeployedAtAddress(safeAddress), "Safe not deployed at expected address");

        // Get and verify BatchedTransaction address
        address batchedTransaction = getExpectedBatchedTransactionAddress();
        require(
            Create2Utils.isContractDeployedAtAddress(batchedTransaction),
            "BatchedTransaction not deployed at expected address"
        );

        // Prompt for confirmation when running with --broadcast
        confirmBroadcastOrDryRun("DeploySafeExecutorModule");

        // Prevent using the production Den Factory deployer for this script
        validateNotProductionDenFactoryDeployerOrRevert();

        // Log the deployment header
        Logger.logBoxHeader("Safe Executor Module Deployment");
        Logger.logKeyValue("CREATE2 Factory", _factoryAddress);
        Logger.logKeyValue("Deployer EOA", msg.sender);
        Logger.logKeyValue("Safe Type", safeType);
        Logger.logKeyValue("Safe Address", safeAddress);
        Logger.logKeyValue("Safe Executor EOA", executorAddress);
        Logger.logKeyValue("BatchedTransaction", batchedTransaction);
        Logger.logEmptyLine();

        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy the module
        address moduleAddress = _deployModule(isGuardian, safeAddress, executorAddress, batchedTransaction);

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Log the result
        Logger.logBoxHeader(unicode"✅ Deployed Module Address");
        Logger.logKeyValue("SafeExecutorModule", moduleAddress);
        Logger.logBoxFooter();

        // Log next steps
        _logNextSteps(safeType, safeAddress, moduleAddress);
    }

    /**
     * @notice Compute and print module address without deploying
     * @dev Does not require RPC connection.
     * @param factoryAddress Address of the CREATE2 factory to use for address computation
     * @param safeType "guardian" or "deployer" - which Safe to compute the module address for
     * @param executorAddress The Safe Executor EOA that will be authorized to execute transactions
     * @param safeAddress The Safe address (computed by DeploySafe.s.sol)
     * @param batchedTransactionAddress The BatchedTransaction address (computed by DeployBatchedTransaction.s.sol)
     */
    function computeAddress(
        address factoryAddress,
        string calldata safeType,
        address executorAddress,
        address safeAddress,
        address batchedTransactionAddress
    ) external pure {
        // Validate inputs
        require(factoryAddress != address(0), "Factory address cannot be zero");
        require(executorAddress != address(0), "Executor address cannot be zero");
        require(safeAddress != address(0), "Safe address cannot be zero");
        require(batchedTransactionAddress != address(0), "BatchedTransaction address cannot be zero");

        // Validate safeType and get guardian flag
        bool isGuardian = _isGuardianSafeType(safeType);

        // Compute the module address
        bytes memory initCode = _getInitCode(safeAddress, executorAddress, batchedTransactionAddress);
        bytes32 salt = _getSalt(isGuardian);
        address expectedAddress = Create2Utils.computeAddress(factoryAddress, salt, initCode);

        // Log the computed address
        Logger.logBoxHeader("Computed SafeExecutorModule Address");
        Logger.logKeyValue("CREATE2 Factory", factoryAddress);
        Logger.logKeyValue("Safe Type", safeType);
        Logger.logKeyValue("Safe Address", safeAddress);
        Logger.logKeyValue("Safe Executor EOA", executorAddress);
        Logger.logKeyValue("BatchedTransaction", batchedTransactionAddress);
        Logger.logEmptyLine();
        Logger.logKeyValue("SafeExecutorModule", expectedAddress);
        Logger.logBoxFooter();
    }

    /// @dev Deploys the SafeExecutorModule via CREATE2
    /// @param isGuardian True for Guardian Safe module, false for Deployer Safe module
    /// @param safeAddress The Safe address
    /// @param executorAddress The Safe Executor EOA address
    /// @param batchedTransaction The BatchedTransaction address
    /// @return moduleAddress The deployed module address
    function _deployModule(bool isGuardian, address safeAddress, address executorAddress, address batchedTransaction)
        internal
        returns (address moduleAddress)
    {
        bytes32 salt = _getSalt(isGuardian);
        bytes memory initCode = _getInitCode(safeAddress, executorAddress, batchedTransaction);
        string memory name = isGuardian ? "Guardian SafeExecutorModule" : "Deployer SafeExecutorModule";

        Logger.logSection("SafeExecutorModule (CREATE2)");

        (moduleAddress,) = Create2Utils.deployIfNotExists(_factoryAddress, salt, initCode, name);

        return moduleAddress;
    }

    /// @dev Validates that the provided executor address matches the expected address for the target
    /// @param isGuardian True if validating for Guardian Safe, false for Deployer Safe
    /// @param executorAddress The executor address to validate
    function _validateExecutorAddressOrRevert(bool isGuardian, address executorAddress) internal {
        (address expectedGuardian, address expectedDeployer) = getExpectedExecutorEOAAddresses();

        address expected = isGuardian ? expectedGuardian : expectedDeployer;
        require(executorAddress == expected, "Invalid executor address for target");
    }

    /// @dev Validates and parses the safeType string
    /// @param safeType The safeType string ("guardian" or "deployer")
    /// @return isGuardian True if safeType is "guardian", false if "deployer"
    function _isGuardianSafeType(string calldata safeType) internal pure returns (bool isGuardian) {
        bytes32 safeTypeHash = keccak256(bytes(safeType));
        if (safeTypeHash == keccak256("guardian")) {
            return true;
        }
        if (safeTypeHash == keccak256("deployer")) {
            return false;
        }
        revert("Invalid safeType - must be 'guardian' or 'deployer'");
    }

    /// @dev Gets the Safe address for the given safeType
    /// @param isGuardian True for Guardian Safe, false for Deployer Safe
    /// @return safeAddress The Safe address
    function _getSafeAddress(bool isGuardian) internal returns (address safeAddress) {
        if (isGuardian) {
            return getExpectedGuardianSafeAddress();
        }
        return getExpectedDeployerSafeAddress();
    }

    /// @dev Gets the salt for the given safeType
    /// @param isGuardian True for Guardian Safe module, false for Deployer Safe module
    /// @return salt The CREATE2 salt
    function _getSalt(bool isGuardian) internal pure returns (bytes32 salt) {
        if (isGuardian) {
            return GUARDIAN_SAFE_EXECUTOR_MODULE_SALT;
        }
        return DEPLOYER_SAFE_EXECUTOR_MODULE_SALT;
    }

    /// @dev Constructs the init code for the module deployment
    /// @param safeAddress The Safe address
    /// @param executorAddress The Safe Executor EOA address
    /// @param batchedTransaction The BatchedTransaction address
    /// @return initCode The init code (creation code + constructor args)
    function _getInitCode(address safeAddress, address executorAddress, address batchedTransaction)
        internal
        pure
        returns (bytes memory initCode)
    {
        return abi.encodePacked(
            type(SafeExecutorModule).creationCode, abi.encode(safeAddress, executorAddress, batchedTransaction)
        );
    }

    /// @dev Logs the next steps after deployment
    /// @param safeType The safeType ("guardian" or "deployer")
    /// @param safeAddress The Safe address
    /// @param moduleAddress The deployed module address
    function _logNextSteps(string calldata safeType, address safeAddress, address moduleAddress) internal pure {
        Logger.logBoxHeader("NEXT STEP: Add the module to the Safe");
        Logger.logIndented("Safe owners must approve adding the module. Run:");
        Logger.logEmptyLine();
        Logger.logIndented(
            string(
                abi.encodePacked(
                    "make safe-add-module SAFE_TYPE=", safeType, " EXECUTE=true NETWORK=<network> ACCOUNT=<safe-owner>"
                )
            )
        );
        Logger.logEmptyLine();
        Logger.logIndented(string(abi.encodePacked("Safe: ", StringUtils.toHexString(safeAddress))));
        Logger.logIndented(string(abi.encodePacked("Module: ", StringUtils.toHexString(moduleAddress))));
        Logger.logBoxFooter();
    }
}
