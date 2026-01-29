// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.7.6;

// Safe 1.3.0 imports
import {GnosisSafe} from "@safe/GnosisSafe.sol";
import {SimulateTxAccessor} from "@safe/accessors/SimulateTxAccessor.sol";
import {CompatibilityFallbackHandler} from "@safe/handler/CompatibilityFallbackHandler.sol";
import {CreateCall} from "@safe/libraries/CreateCall.sol";
import {MultiSend} from "@safe/libraries/MultiSend.sol";
import {MultiSendCallOnly} from "@safe/libraries/MultiSendCallOnly.sol";
import {GnosisSafeProxyFactory} from "@safe/proxies/GnosisSafeProxyFactory.sol";

// Shared script utilities
import {BaseDeployScript} from "script/base/BaseDeployScript.sol";
import {Create2Utils} from "script/libraries/Create2Utils.sol";
import {Logger} from "script/libraries/Logger.sol";
import {SafeInfrastructure} from "script/libraries/Types.sol";

/**
 * @title DeploySafeInfrastructure
 * @notice Deploys Safe 1.3.0 infrastructure contracts (singleton, proxy factory, handlers, libraries)
 * @dev This script deploys Safe infrastructure contracts using Solidity 0.7.6 for deterministic
 *      addresses that match official Safe 1.3.0 deployments.
 *
 *      IMPORTANT: This script must be compiled with the [profile.safe] foundry profile:
 *        FOUNDRY_PROFILE=safe forge script script/safe/DeploySafeInfrastructure.s.sol:DeploySafeInfrastructure \
 *          --sig "run(address)" <CREATE2_FACTORY_ADDRESS> \
 *          --rpc-url $RPC_URL \
 *          --broadcast \
 *          -vvvv
 *
 *      This script deploys the following infrastructure contracts:
 *      - GnosisSafe singleton (master copy)
 *      - GnosisSafeProxyFactory
 *      - CompatibilityFallbackHandler
 *      - MultiSend
 *      - MultiSendCallOnly
 *      - CreateCall
 *      - SimulateTxAccessor
 *
 *      NOTE: This script only deploys infrastructure. To deploy Safe multisigs (Guardian and
 *      Deployer Safes), use DeploySafeMultisigs.s.sol AFTER running this script.
 *
 *      SAFETY CHECKS:
 *      1. Verifies the provided CREATE2 factory is a known factory from deployment.toml
 *      2. Verifies the provided CREATE2 factory is deployed
 *      3. Verifies that the deployer is not the production Den Factory deployer
 *      4. Warns and requires confirmation when targeting production chains
 *      5. Requires interactive confirmation when broadcasting
 *
 * @author Den Technologies Inc
 */
contract DeploySafeInfrastructure is BaseDeployScript {
    /**
     * @notice Main entry point for the deployment script
     * @param factoryAddress Address of the CREATE2 factory to use for deployments
     */
    function run(address factoryAddress) external {
        // Common deployment initialization (factory validation, confirmations, header logging)
        validateAndInitializeDeploymentOrRevert(factoryAddress, "DeploySafeInfrastructure");

        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy Safe Infrastructure
        SafeInfrastructure memory safeInfra = _deploySafeInfrastructure();

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Log deployed addresses
        _logDeployedAddresses(safeInfra);
    }

    /// @dev Deploys all Safe 1.3.0 infrastructure contracts via CREATE2 if not already deployed
    /// @return safeInfra Struct containing all deployed Safe infrastructure addresses
    function _deploySafeInfrastructure() internal returns (SafeInfrastructure memory safeInfra) {
        Logger.logSection("Safe 1.3.0 Infrastructure (CREATE2)");

        // Deploy Safe Singleton (master copy) - GnosisSafe for 1.3.0
        (safeInfra.singletonAddress,) = Create2Utils.deployIfNotExists(
            _factoryAddress, SAFE_SINGLETON_SALT, type(GnosisSafe).creationCode, "GnosisSafe Singleton"
        );

        // Deploy Safe Proxy Factory - GnosisSafeProxyFactory for 1.3.0
        (safeInfra.proxyFactoryAddress,) = Create2Utils.deployIfNotExists(
            _factoryAddress,
            SAFE_PROXY_FACTORY_SALT,
            type(GnosisSafeProxyFactory).creationCode,
            "GnosisSafeProxyFactory"
        );

        // Deploy Compatibility Fallback Handler
        (safeInfra.fallbackHandlerAddress,) = Create2Utils.deployIfNotExists(
            _factoryAddress,
            SAFE_FALLBACK_HANDLER_SALT,
            type(CompatibilityFallbackHandler).creationCode,
            "CompatibilityFallbackHandler"
        );

        // Deploy MultiSend
        (safeInfra.multiSendAddress,) = Create2Utils.deployIfNotExists(
            _factoryAddress, SAFE_MULTISEND_SALT, type(MultiSend).creationCode, "MultiSend"
        );

        // Deploy MultiSendCallOnly
        (safeInfra.multiSendCallOnlyAddress,) = Create2Utils.deployIfNotExists(
            _factoryAddress, SAFE_MULTISEND_CALL_ONLY_SALT, type(MultiSendCallOnly).creationCode, "MultiSendCallOnly"
        );

        // Deploy CreateCall
        (safeInfra.createCallAddress,) = Create2Utils.deployIfNotExists(
            _factoryAddress, SAFE_CREATE_CALL_SALT, type(CreateCall).creationCode, "CreateCall"
        );

        // Deploy SimulateTxAccessor
        (safeInfra.simulateTxAccessorAddress,) = Create2Utils.deployIfNotExists(
            _factoryAddress, SAFE_SIMULATE_TX_ACCESSOR_SALT, type(SimulateTxAccessor).creationCode, "SimulateTxAccessor"
        );
    }

    /**
     * @notice Computes and displays expected Safe infrastructure addresses without deploying
     * @dev Use this to preview addresses before deployment. Does not require RPC connection.
     * @param factoryAddress Address of the CREATE2 factory to use for address computation
     */
    function computeAddresses(address factoryAddress) external pure {
        // Validate the provided CREATE2 factory address
        require(factoryAddress != address(0), "Factory address cannot be zero");

        // Log header
        Logger.logBoxHeader("Computed Safe 1.3.0 Infrastructure Addresses");
        Logger.logKeyValue("CREATE2 Factory", factoryAddress);
        Logger.logEmptyLine();

        // Compute and log Safe Infrastructure addresses
        SafeInfrastructure memory safeInfra = _computeSafeInfrastructureAddresses(factoryAddress);

        // Log footer
        Logger.logBoxFooter();

        // Suppress unused variable warning
        safeInfra;
    }

    /// @dev Computes all Safe 1.3.0 infrastructure contract addresses without deploying
    /// @param factoryAddress Address of the CREATE2 factory to use for address computation
    /// @return safeInfra Struct containing all computed Safe infrastructure addresses
    function _computeSafeInfrastructureAddresses(address factoryAddress)
        internal
        pure
        returns (SafeInfrastructure memory safeInfra)
    {
        Logger.logSection("Safe 1.3.0 Infrastructure");

        // Compute Safe Singleton address
        safeInfra.singletonAddress =
            Create2Utils.computeAddress(factoryAddress, SAFE_SINGLETON_SALT, type(GnosisSafe).creationCode);
        Logger.logKeyValue("GnosisSafe Singleton", safeInfra.singletonAddress);

        // Compute Safe Proxy Factory address
        safeInfra.proxyFactoryAddress = Create2Utils.computeAddress(
            factoryAddress, SAFE_PROXY_FACTORY_SALT, type(GnosisSafeProxyFactory).creationCode
        );
        Logger.logKeyValue("GnosisSafeProxyFactory", safeInfra.proxyFactoryAddress);

        // Compute Compatibility Fallback Handler address
        safeInfra.fallbackHandlerAddress = Create2Utils.computeAddress(
            factoryAddress, SAFE_FALLBACK_HANDLER_SALT, type(CompatibilityFallbackHandler).creationCode
        );
        Logger.logKeyValue("CompatibilityFallbackHandler", safeInfra.fallbackHandlerAddress);

        // Compute MultiSend address
        safeInfra.multiSendAddress =
            Create2Utils.computeAddress(factoryAddress, SAFE_MULTISEND_SALT, type(MultiSend).creationCode);
        Logger.logKeyValue("MultiSend", safeInfra.multiSendAddress);

        // Compute MultiSendCallOnly address
        safeInfra.multiSendCallOnlyAddress = Create2Utils.computeAddress(
            factoryAddress, SAFE_MULTISEND_CALL_ONLY_SALT, type(MultiSendCallOnly).creationCode
        );
        Logger.logKeyValue("MultiSendCallOnly", safeInfra.multiSendCallOnlyAddress);

        // Compute CreateCall address
        safeInfra.createCallAddress =
            Create2Utils.computeAddress(factoryAddress, SAFE_CREATE_CALL_SALT, type(CreateCall).creationCode);
        Logger.logKeyValue("CreateCall", safeInfra.createCallAddress);

        // Compute SimulateTxAccessor address
        safeInfra.simulateTxAccessorAddress = Create2Utils.computeAddress(
            factoryAddress, SAFE_SIMULATE_TX_ACCESSOR_SALT, type(SimulateTxAccessor).creationCode
        );
        Logger.logKeyValue("SimulateTxAccessor", safeInfra.simulateTxAccessorAddress);
    }

    /// @dev Logs all deployed contract addresses in a formatted summary
    /// @param safeInfra Deployed Safe infrastructure addresses
    function _logDeployedAddresses(SafeInfrastructure memory safeInfra) internal pure {
        Logger.logBoxHeader(unicode"✅ Deployed Safe 1.3.0 Infrastructure Addresses");
        Logger.logKeyValue("GnosisSafe Singleton", safeInfra.singletonAddress);
        Logger.logKeyValue("GnosisSafeProxyFactory", safeInfra.proxyFactoryAddress);
        Logger.logKeyValue("FallbackHandler", safeInfra.fallbackHandlerAddress);
        Logger.logKeyValue("MultiSend", safeInfra.multiSendAddress);
        Logger.logKeyValue("MultiSendCallOnly", safeInfra.multiSendCallOnlyAddress);
        Logger.logKeyValue("CreateCall", safeInfra.createCallAddress);
        Logger.logKeyValue("SimulateTxAccessor", safeInfra.simulateTxAccessorAddress);
        Logger.logBoxFooter();
    }
}
