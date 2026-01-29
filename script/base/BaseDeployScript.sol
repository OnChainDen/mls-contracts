// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity >=0.7.0 <0.9.0;

import {VmSafe} from "forge-std/Script.sol";

import {DeploymentConfig} from "script/base/DeploymentConfig.sol";
import {Create2Utils} from "script/libraries/Create2Utils.sol";
import {Logger} from "script/libraries/Logger.sol";
import {StringUtils} from "script/libraries/StringUtils.sol";
import {SafeInfrastructure} from "script/libraries/Types.sol";

/**
 * @title BaseDeployScript
 * @notice Base contract for all deployment scripts providing validation, prompts, and orchestration
 * @dev This abstract contract provides:
 *      - Factory initialization and validation
 *      - Confirmation prompts for broadcast and production chains
 *      - Common deployment orchestration utilities
 *
 *      Inherits from DeploymentConfig which provides:
 *      - All deployment constants (salts, factory names) via DeploymentConstants
 *      - Factory state variables via FactoryState
 *      - Cached TOML reading for addresses from deployment.toml
 *      - Chain ID utilities for environment detection
 *
 *      This contract uses a floating pragma (>=0.7.0 <0.9.0) to allow reuse by both
 *      platform scripts (0.8.33) and Safe deployment scripts (0.7.6).
 *
 * @author Den Technologies Inc
 */
abstract contract BaseDeployScript is DeploymentConfig {
    /// @dev Initializes the factory by validating it against known factories and storing the address/name
    /// @param factoryAddress The CREATE2 factory address to use for deployments
    function validateAndInitializeFactoryOrRevert(address factoryAddress) internal {
        require(factoryAddress != address(0), "Factory address cannot be zero");

        // Read factory addresses from TOML
        string memory toml = _toml();
        address arachnidFactory = vm.parseTomlAddress(toml, ".factory.arachnid.factory");
        address denProdFactory = vm.parseTomlAddress(toml, ".factory.den-prod.factory");
        address denNonprodFactory = vm.parseTomlAddress(toml, ".factory.den-nonprod.factory");

        // Determine factory name based on address
        if (factoryAddress == arachnidFactory) {
            _factoryName = FACTORY_ARACHNID;
            _factoryDisplayName = "Arachnid Deterministic Deployment Proxy";
        } else if (factoryAddress == denProdFactory) {
            _factoryName = FACTORY_DEN_PROD;
            _factoryDisplayName = "Den Singleton Factory (Production)";
        } else if (factoryAddress == denNonprodFactory) {
            _factoryName = FACTORY_DEN_NONPROD;
            _factoryDisplayName = "Den Singleton Factory (Non-Production)";
        } else {
            revert(
                string(
                    abi.encodePacked(
                        "Unknown factory address: ",
                        StringUtils.toHexString(factoryAddress),
                        ". Must be one of the factories defined in deployment.toml"
                    )
                )
            );
        }

        // Validate factory is deployed
        require(
            Create2Utils.isContractDeployedAtAddress(factoryAddress),
            string(abi.encodePacked(_factoryDisplayName, " not deployed at ", StringUtils.toHexString(factoryAddress)))
        );

        // Store the factory address
        _factoryAddress = factoryAddress;

        // Log success
        Logger.logCheckStart("Validating CREATE2 factory...");
        Logger.logCheckPass(string(abi.encodePacked(_factoryDisplayName, " deployed at expected address")));
    }

    /// @dev Prompts the user for confirmation with context and reverts if they don't type "yes"
    /// @param context Context message to display before the prompt
    function _promptForConfirmationOrRevert(string memory context) internal {
        string memory promptMessage = string(abi.encodePacked(context, "\nType 'yes' to continue: "));
        string memory response = vm.prompt(promptMessage);
        string memory trimmedResponse = vm.trim(response);
        require(StringUtils.stringEquals(trimmedResponse, "yes"), "Confirmation not received");
    }

    /// @dev Logs the execution mode and prompts for confirmation when broadcasting
    /// @param scriptName Human-readable script name for logging
    function confirmBroadcastOrDryRun(string memory scriptName) internal {
        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            // solhint-disable-next-line func-named-parameters
            string memory context = string(
                abi.encodePacked(
                    "\n",
                    "  !! BROADCAST MODE DETECTED !!\n",
                    "  Script: ",
                    scriptName,
                    "\n",
                    "  Transactions WILL be sent to the network."
                )
            );
            _promptForConfirmationOrRevert(context);
            Logger.logEmptyLine();
        } else {
            Logger.logInfo("DRY RUN MODE - No transactions will be broadcast");
            Logger.logEmptyLine();
        }
    }

    /// @dev Logs whether a production chain is detected and prompts for confirmation if so
    /// @param scriptName Human-readable script name for logging
    function warnAndConfirmIfProductionChain(string memory scriptName) internal {
        if (_isProductionChain()) {
            // solhint-disable-next-line func-named-parameters
            string memory context = string(
                abi.encodePacked(
                    "\n",
                    "  !! PRODUCTION CHAIN DETECTED !!\n",
                    "  Script: ",
                    scriptName,
                    "\n",
                    "  Chain ID: ",
                    StringUtils.toString(_getChainId())
                )
            );
            _promptForConfirmationOrRevert(context);
            Logger.logEmptyLine();
        } else {
            Logger.logInfo("NON-PRODUCTION CHAIN DETECTED");
            Logger.logKeyValue("Script", scriptName);
            Logger.logEmptyLine();
        }
    }

    /// @dev Validates that the deployer is NOT the production Den Factory deployer
    function validateNotProductionDenFactoryDeployerOrRevert() internal {
        Logger.logCheckStart("Checking deployer is not production Den Factory deployer...");

        // Read production deployer from TOML
        string memory toml = _toml();
        address prodDeployer = vm.parseTomlAddress(toml, ".factory.den-prod.factory_deployer");

        if (msg.sender == prodDeployer) {
            Logger.logCheckFail("Deployer is the production Den Factory deployer");
            Logger.logCheckDetail("This EOA should ONLY be used by DeployDenSingletonFactory.");
            Logger.logCheckDetail("Use a different deployer for this script.");
            revert("Cannot use production Den Factory deployer for this script");
        }

        Logger.logCheckPass("Deployer is not production Den Factory deployer");
    }

    /// @dev Common deployment initialization sequence - validates factory, confirms broadcast, and logs header
    /// @param factoryAddress The CREATE2 factory to validate and use
    /// @param scriptName Human-readable script name for logging/confirmation prompts
    function validateAndInitializeDeploymentOrRevert(address factoryAddress, string memory scriptName) internal {
        // 1. Initialize and validate factory
        validateAndInitializeFactoryOrRevert(factoryAddress);

        // 2. Warn and confirm if on production chain
        warnAndConfirmIfProductionChain(scriptName);

        // 3. Confirm broadcast/dry run
        confirmBroadcastOrDryRun(scriptName);

        // 4. Ensure not using production deployer
        validateNotProductionDenFactoryDeployerOrRevert();

        // 5. Log standard deployment header
        Logger.logBoxHeader("Den Multi-layer Security (MLS) Wallet - Contract Deployment");
        Logger.logKeyValue("Chain ID", _getChainId());
        Logger.logKeyValue("CREATE2 Factory", _factoryAddress);
        Logger.logKeyValue("Factory Type", _factoryDisplayName);
        Logger.logBoxFooter();
        Logger.logKeyValue("Deployer EOA", msg.sender);
        Logger.logEmptyLine();
    }

    /// @dev Verifies that Safe infrastructure is deployed at the expected addresses from deployment.toml
    ///      NOTE: validateAndInitializeFactoryOrRevert() must be called first
    function validateSafeInfrastructureDeployedOrRevert() internal {
        Logger.logSection("Verify Safe 1.3.0 Infrastructure");

        // Get expected Safe infrastructure addresses from deployment.toml
        SafeInfrastructure memory expectedSafeInfra = getExpectedSafeInfrastructureAddresses();

        bool allDeployed = true;

        // Check if Safe singleton is deployed
        if (!Create2Utils.isContractDeployedAtAddress(expectedSafeInfra.singletonAddress)) {
            Logger.logFail("GnosisSafe Singleton NOT DEPLOYED at expected address");
            Logger.logKeyValue("  Expected", expectedSafeInfra.singletonAddress);
            allDeployed = false;
        } else {
            Logger.logPass("GnosisSafe Singleton deployed at expected address");
        }

        // Check if Safe proxy factory is deployed
        if (!Create2Utils.isContractDeployedAtAddress(expectedSafeInfra.proxyFactoryAddress)) {
            Logger.logFail("GnosisSafeProxyFactory NOT DEPLOYED at expected address");
            Logger.logKeyValue("  Expected", expectedSafeInfra.proxyFactoryAddress);
            allDeployed = false;
        } else {
            Logger.logPass("GnosisSafeProxyFactory deployed at expected address");
        }

        // Check if fallback handler is deployed
        if (!Create2Utils.isContractDeployedAtAddress(expectedSafeInfra.fallbackHandlerAddress)) {
            Logger.logFail("CompatibilityFallbackHandler NOT DEPLOYED at expected address");
            Logger.logKeyValue("  Expected", expectedSafeInfra.fallbackHandlerAddress);
            allDeployed = false;
        } else {
            Logger.logPass("CompatibilityFallbackHandler deployed at expected address");
        }

        // Check if MultiSend is deployed
        if (!Create2Utils.isContractDeployedAtAddress(expectedSafeInfra.multiSendAddress)) {
            Logger.logFail("MultiSend NOT DEPLOYED at expected address");
            Logger.logKeyValue("  Expected", expectedSafeInfra.multiSendAddress);
            allDeployed = false;
        } else {
            Logger.logPass("MultiSend deployed at expected address");
        }

        // Check if MultiSendCallOnly is deployed
        if (!Create2Utils.isContractDeployedAtAddress(expectedSafeInfra.multiSendCallOnlyAddress)) {
            Logger.logFail("MultiSendCallOnly NOT DEPLOYED at expected address");
            Logger.logKeyValue("  Expected", expectedSafeInfra.multiSendCallOnlyAddress);
            allDeployed = false;
        } else {
            Logger.logPass("MultiSendCallOnly deployed at expected address");
        }

        // Check if CreateCall is deployed
        if (!Create2Utils.isContractDeployedAtAddress(expectedSafeInfra.createCallAddress)) {
            Logger.logFail("CreateCall NOT DEPLOYED at expected address");
            Logger.logKeyValue("  Expected", expectedSafeInfra.createCallAddress);
            allDeployed = false;
        } else {
            Logger.logPass("CreateCall deployed at expected address");
        }

        // Check if SimulateTxAccessor is deployed
        if (!Create2Utils.isContractDeployedAtAddress(expectedSafeInfra.simulateTxAccessorAddress)) {
            Logger.logFail("SimulateTxAccessor NOT DEPLOYED at expected address");
            Logger.logKeyValue("  Expected", expectedSafeInfra.simulateTxAccessorAddress);
            allDeployed = false;
        } else {
            Logger.logPass("SimulateTxAccessor deployed at expected address");
        }

        if (!allDeployed) {
            Logger.logEmptyLine();
            Logger.logWarn("WARNING: Safe infrastructure is not deployed!");
            Logger.logIndented(
                "Run DeploySafeInfrastructure.s.sol first (FOUNDRY_PROFILE=safe), then re-run this script."
            );
            Logger.logEmptyLine();
            revert("Safe infrastructure is not deployed at expected addresses");
        }
    }
}
