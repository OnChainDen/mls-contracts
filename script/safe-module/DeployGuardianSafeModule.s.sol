// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {SafeExecutorModule} from "../../src/safe-module/SafeExecutorModule.sol";
import {BaseDeployScript} from "script/base/BaseDeployScript.sol";
import {Create2Utils} from "script/libraries/Create2Utils.sol";
import {Logger} from "script/libraries/Logger.sol";
import {StringUtils} from "script/libraries/StringUtils.sol";

/**
 * @title DeployGuardianSafeModule
 * @notice Deploys a SafeExecutorModule for the Guardian Safe via CREATE2
 * @dev This script deploys a minimal Safe module that allows a designated EOA (the "Guardian Executor EOA")
 *      to execute contract calls on behalf of the Guardian Safe multisig.
 *
 *      Usage:
 *        forge script script/safe-module/DeployGuardianSafeModule.s.sol:DeployGuardianSafeModule \
 *          --sig "run(address,address)" <FACTORY_ADDRESS> <EXECUTOR_ADDRESS> \
 *          --rpc-url $RPC_URL \
 *          --broadcast \
 *          -vvvv
 *
 *      Where:
 *        - FACTORY_ADDRESS: The CREATE2 factory to use (Arachnid or Den Singleton Factory)
 *        - EXECUTOR_ADDRESS: The Guardian Executor EOA that will be authorized to execute transactions
 *
 *      SAFETY CHECKS:
 *      1. Verifies the provided CREATE2 factory is a known factory from deployment.toml
 *      2. Verifies the provided CREATE2 factory is deployed
 *      3. Verifies the executor address matches the expected Guardian executor in deployment.toml
 *      4. Verifies the Guardian Safe is deployed at the expected address
 *      5. Verifies the BatchedTransaction is deployed at the expected address
 *      6. Verifies the deployer is not the production Den Factory deployer
 *      7. Requires interactive confirmation when broadcasting
 *
 * @author Den Technologies Inc
 */
contract DeployGuardianSafeModule is BaseDeployScript {
    /**
     * @notice Main entry point - deploys a SafeExecutorModule for the Guardian Safe via CREATE2
     * @param factoryAddress Address of the CREATE2 factory to use for deployment
     * @param executorAddress The Guardian Executor EOA that will be authorized to execute transactions
     */
    function run(address factoryAddress, address executorAddress) external {
        // Common deployment initialization (factory validation, confirmations, header logging)
        validateAndInitializeDeploymentOrRevert(factoryAddress, "DeployGuardianSafeModule");

        // Script-specific validations
        require(executorAddress != address(0), "Executor address cannot be zero");
        _validateExecutorAddressOrRevert(executorAddress);
        address safeAddress = getExpectedGuardianSafeAddress();
        require(Create2Utils.isContractDeployedAtAddress(safeAddress), "Guardian Safe not deployed at expected address");
        address batchedTransaction = getExpectedBatchedTransactionAddress();
        require(
            Create2Utils.isContractDeployedAtAddress(batchedTransaction),
            "BatchedTransaction not deployed at expected address"
        );

        // Script-specific logging (standard header already logged by validateAndInitializeDeploymentOrRevert)
        Logger.logKeyValue("Guardian Safe", safeAddress);
        Logger.logKeyValue("Guardian Executor EOA", executorAddress);
        Logger.logKeyValue("BatchedTransaction", batchedTransaction);
        Logger.logEmptyLine();

        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy the module
        address moduleAddress = _deployModule(safeAddress, executorAddress, batchedTransaction);

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Log the result
        Logger.logBoxHeader(unicode"✅ Deployed Module Address");
        Logger.logKeyValue("Guardian SafeExecutorModule", moduleAddress);
        Logger.logBoxFooter();

        // Log next steps
        _logNextSteps(safeAddress, moduleAddress);
    }

    /**
     * @notice Compute and print module address without deploying
     * @dev Does not require RPC connection.
     * @param factoryAddress Address of the CREATE2 factory to use for address computation
     * @param executorAddress The Guardian Executor EOA that will be authorized to execute transactions
     * @param safeAddress The Guardian Safe address (computed by DeploySafe.s.sol)
     * @param batchedTransactionAddress The BatchedTransaction address (computed by DeployBatchedTransaction.s.sol)
     */
    function computeAddress(
        address factoryAddress,
        address executorAddress,
        address safeAddress,
        address batchedTransactionAddress
    ) external pure {
        // Validate inputs
        require(factoryAddress != address(0), "Factory address cannot be zero");
        require(executorAddress != address(0), "Executor address cannot be zero");
        require(safeAddress != address(0), "Guardian Safe address cannot be zero");
        require(batchedTransactionAddress != address(0), "BatchedTransaction address cannot be zero");

        // Compute the module address
        bytes memory initCode = _getInitCode(safeAddress, executorAddress, batchedTransactionAddress);
        address expectedAddress =
            Create2Utils.computeAddress(factoryAddress, GUARDIAN_SAFE_EXECUTOR_MODULE_SALT, initCode);

        // Log the computed address
        Logger.logBoxHeader("Computed Guardian SafeExecutorModule Address");
        Logger.logKeyValue("CREATE2 Factory", factoryAddress);
        Logger.logKeyValue("Guardian Safe", safeAddress);
        Logger.logKeyValue("Guardian Executor EOA", executorAddress);
        Logger.logKeyValue("BatchedTransaction", batchedTransactionAddress);
        Logger.logEmptyLine();
        Logger.logKeyValue("SafeExecutorModule", expectedAddress);
        Logger.logBoxFooter();
    }

    /// @dev Deploys the SafeExecutorModule for the Guardian Safe via CREATE2
    /// @param safeAddress The Guardian Safe address
    /// @param executorAddress The Guardian Executor EOA address
    /// @param batchedTransaction The BatchedTransaction address
    /// @return moduleAddress The deployed module address
    function _deployModule(address safeAddress, address executorAddress, address batchedTransaction)
        internal
        returns (address moduleAddress)
    {
        bytes memory initCode = _getInitCode(safeAddress, executorAddress, batchedTransaction);

        Logger.logSection("Guardian SafeExecutorModule (CREATE2)");

        (moduleAddress,) = Create2Utils.deployIfNotExists(
            _factoryAddress, GUARDIAN_SAFE_EXECUTOR_MODULE_SALT, initCode, "Guardian SafeExecutorModule"
        );

        return moduleAddress;
    }

    /// @dev Validates that the provided executor address matches the expected Guardian executor address
    /// @param executorAddress The executor address to validate
    function _validateExecutorAddressOrRevert(address executorAddress) internal {
        address expectedGuardian = getExpectedGuardianExecutorEoaAddress();
        require(
            executorAddress == expectedGuardian,
            "Invalid executor address - must match Guardian executor in deployment.toml"
        );
    }

    /// @dev Constructs the init code for the module deployment
    /// @param safeAddress The Guardian Safe address
    /// @param executorAddress The Guardian Executor EOA address
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
    /// @param safeAddress The Guardian Safe address
    /// @param moduleAddress The deployed module address
    function _logNextSteps(address safeAddress, address moduleAddress) internal pure {
        Logger.logBoxHeader("NEXT STEP: Add the module to the Guardian Safe");
        Logger.logIndented("Guardian Safe owners must approve adding the module. Run:");
        Logger.logEmptyLine();
        Logger.logIndented("make guardian-safe-add-module EXECUTE=true NETWORK=<network> ACCOUNT=<safe-owner>");
        Logger.logEmptyLine();
        Logger.logIndented(string(abi.encodePacked("Guardian Safe: ", StringUtils.toHexString(safeAddress))));
        Logger.logIndented(string(abi.encodePacked("Module: ", StringUtils.toHexString(moduleAddress))));
        Logger.logBoxFooter();
    }
}
