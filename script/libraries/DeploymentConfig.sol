// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity >=0.7.0 <0.9.0;

import {Script} from "forge-std/Script.sol";

import {DeploymentConstants} from "script/libraries/DeploymentConstants.sol";
import {FactoryState} from "script/libraries/FactoryState.sol";
import {PlatformLibraries, SafeInfrastructure} from "script/libraries/Types.sol";

/**
 * @title DeploymentConfig
 * @notice Configuration reading utilities for deployment scripts
 * @dev This abstract contract provides:
 *      - Cached TOML reading for addresses from deployment.toml
 *      - Factory, library, and Safe infrastructure address getters
 *      - Safe multisig configuration getters
 *      - Chain ID utilities for environment detection
 *
 *      This contract uses a floating pragma (>=0.7.0 <0.9.0) to allow reuse by both
 *      platform scripts (0.8.33) and Safe deployment scripts (0.7.6).
 *
 * @author Den Technologies Inc
 */
abstract contract DeploymentConfig is Script, DeploymentConstants, FactoryState {
    /// @dev The TOML content is read once and cached for subsequent reads
    string private _tomlContent;

    /// @dev Lazily reads and caches the TOML content
    /// @return The cached TOML content
    function _toml() internal returns (string memory) {
        if (bytes(_tomlContent).length == 0) {
            _tomlContent = vm.readFile("deployment.toml");
        }
        return _tomlContent;
    }

    /// @dev Gets the current chain ID using inline assembly for 0.7.x compatibility
    /// @return chainId The chain ID of the current network
    function _getChainId() internal view returns (uint256 chainId) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            chainId := chainid()
        }
    }

    /// @dev Returns true if the current chain is a production network
    /// @return True if the chain is a production network
    function _isProductionChain() internal view returns (bool) {
        uint256 chainId = _getChainId();
        return chainId == 1 // Ethereum Mainnet
            || chainId == 10 // Optimism
            || chainId == 56 // BNB Smart Chain
            || chainId == 137 // Polygon
            || chainId == 8453 // Base
            || chainId == 42_161 // Arbitrum One
            || chainId == 43_114; // Avalanche C-Chain
    }

    /// @dev Returns the factory address for a given factory name
    /// @param factoryName The factory name (arachnid, den-prod, or den-nonprod)
    /// @return factoryAddress The factory address
    function getFactoryAddress(string memory factoryName) internal returns (address factoryAddress) {
        string memory toml = _toml();
        string memory key = string.concat(".factory.", factoryName, ".factory");
        return vm.parseTomlAddress(toml, key);
    }

    /// @dev Returns the factory deployer address for a given factory name
    /// @param factoryName The factory name (arachnid, den-prod, or den-nonprod)
    /// @return deployerAddress The factory deployer address
    function getFactoryDeployerAddress(string memory factoryName) internal returns (address deployerAddress) {
        string memory toml = _toml();
        string memory key = string.concat(".factory.", factoryName, ".factory_deployer");
        return vm.parseTomlAddress(toml, key);
    }

    /// @dev Returns expected library addresses based on the initialized factory
    ///      NOTE: validateAndInitializeFactoryOrRevert() must be called first
    /// @return libs Struct containing expected library addresses
    function getExpectedLibraryAddresses() internal returns (PlatformLibraries memory libs) {
        require(
            _factoryAddress != address(0), "Factory not initialized - call validateAndInitializeFactoryOrRevert() first"
        );

        string memory toml = _toml();
        string memory prefix = string.concat(".factory.", _factoryName);

        libs = PlatformLibraries({
            policyAddress: vm.parseTomlAddress(toml, string.concat(prefix, ".lib_org_policy")),
            adminAddress: vm.parseTomlAddress(toml, string.concat(prefix, ".lib_org_admin")),
            initializationAddress: vm.parseTomlAddress(toml, string.concat(prefix, ".lib_org_init")),
            accountSignatureAddress: vm.parseTomlAddress(toml, string.concat(prefix, ".lib_org_account_sig"))
        });
    }

    /// @dev Returns expected Safe infrastructure addresses based on the initialized factory
    ///      NOTE: validateAndInitializeFactoryOrRevert() must be called first
    /// @return safeInfra Struct containing expected Safe infrastructure addresses
    function getExpectedSafeInfrastructureAddresses() internal returns (SafeInfrastructure memory safeInfra) {
        require(
            _factoryAddress != address(0), "Factory not initialized - call validateAndInitializeFactoryOrRevert() first"
        );

        string memory toml = _toml();
        string memory prefix = string.concat(".factory.", _factoryName);

        safeInfra = SafeInfrastructure({
            singletonAddress: vm.parseTomlAddress(toml, string.concat(prefix, ".safe_singleton")),
            proxyFactoryAddress: vm.parseTomlAddress(toml, string.concat(prefix, ".safe_proxy_factory")),
            fallbackHandlerAddress: vm.parseTomlAddress(toml, string.concat(prefix, ".safe_fallback_handler")),
            multiSendAddress: vm.parseTomlAddress(toml, string.concat(prefix, ".safe_multisend")),
            multiSendCallOnlyAddress: vm.parseTomlAddress(toml, string.concat(prefix, ".safe_multisend_call_only")),
            createCallAddress: vm.parseTomlAddress(toml, string.concat(prefix, ".safe_create_call")),
            simulateTxAccessorAddress: vm.parseTomlAddress(toml, string.concat(prefix, ".safe_simulate_tx_accessor"))
        });
    }

    /// @dev Returns expected Guardian Safe address based on the initialized factory
    ///      NOTE: validateAndInitializeFactoryOrRevert() must be called first
    /// @return guardianSafeAddress The expected Guardian Safe address
    function getExpectedGuardianSafeAddress() internal returns (address guardianSafeAddress) {
        require(
            _factoryAddress != address(0), "Factory not initialized - call validateAndInitializeFactoryOrRevert() first"
        );

        string memory toml = _toml();
        string memory key = string.concat(".factory.", _factoryName, ".guardian_safe");
        return vm.parseTomlAddress(toml, key);
    }

    /// @dev Returns expected Deployer Safe address based on the initialized factory
    ///      NOTE: validateAndInitializeFactoryOrRevert() must be called first
    /// @return deployerSafeAddress The expected Deployer Safe address
    function getExpectedDeployerSafeAddress() internal returns (address deployerSafeAddress) {
        require(
            _factoryAddress != address(0), "Factory not initialized - call validateAndInitializeFactoryOrRevert() first"
        );

        string memory toml = _toml();
        string memory key = string.concat(".factory.", _factoryName, ".deployer_safe");
        return vm.parseTomlAddress(toml, key);
    }

    /// @dev Returns expected Safe Executor Module addresses based on the initialized factory
    ///      NOTE: validateAndInitializeFactoryOrRevert() must be called first
    /// @return guardianModuleAddress Expected Guardian Safe Executor Module address
    /// @return deployerModuleAddress Expected Deployer Safe Executor Module address
    function getExpectedSafeExecutorModuleAddresses()
        internal
        returns (address guardianModuleAddress, address deployerModuleAddress)
    {
        require(
            _factoryAddress != address(0), "Factory not initialized - call validateAndInitializeFactoryOrRevert() first"
        );

        string memory toml = _toml();
        string memory prefix = string.concat(".factory.", _factoryName);

        guardianModuleAddress = vm.parseTomlAddress(toml, string.concat(prefix, ".guardian_safe_executor_module"));
        deployerModuleAddress = vm.parseTomlAddress(toml, string.concat(prefix, ".deployer_safe_executor_module"));

        require(guardianModuleAddress != address(0), "Guardian Safe Executor Module address not set in deployment.toml");
        require(deployerModuleAddress != address(0), "Deployer Safe Executor Module address not set in deployment.toml");
    }

    /// @dev Returns expected BatchedTransaction address based on the initialized factory
    ///      NOTE: validateAndInitializeFactoryOrRevert() must be called first
    /// @return batchedTransactionAddress The expected BatchedTransaction address
    function getExpectedBatchedTransactionAddress() internal returns (address batchedTransactionAddress) {
        require(
            _factoryAddress != address(0), "Factory not initialized - call validateAndInitializeFactoryOrRevert() first"
        );

        string memory toml = _toml();
        string memory key = string.concat(".factory.", _factoryName, ".batched_transaction");
        batchedTransactionAddress = vm.parseTomlAddress(toml, key);

        require(batchedTransactionAddress != address(0), "BatchedTransaction address not set in deployment.toml");
    }

    /// @dev Returns Guardian Safe configuration based on current chain (prod vs nonprod)
    /// @return ownerAddresses Array of owner addresses for the Guardian Safe
    /// @return threshold Required number of signatures
    function getGuardianSafeConfig() internal returns (address[] memory ownerAddresses, uint256 threshold) {
        string memory toml = _toml();
        string memory env = _isProductionChain() ? "prod" : "nonprod";
        string memory prefix = string.concat(".safe.", env);

        threshold = vm.parseTomlUint(toml, string.concat(prefix, ".guardian_safe_threshold"));

        // For production, we have 3 owners; for non-production, we have 1 owner
        if (_isProductionChain()) {
            ownerAddresses = new address[](3);
            ownerAddresses[0] = vm.parseTomlAddress(toml, string.concat(prefix, ".guardian_safe_owner_1"));
            ownerAddresses[1] = vm.parseTomlAddress(toml, string.concat(prefix, ".guardian_safe_owner_2"));
            ownerAddresses[2] = vm.parseTomlAddress(toml, string.concat(prefix, ".guardian_safe_owner_3"));
        } else {
            ownerAddresses = new address[](1);
            ownerAddresses[0] = vm.parseTomlAddress(toml, string.concat(prefix, ".guardian_safe_owner_1"));
        }
    }

    /// @dev Returns Deployer Safe configuration based on current chain (prod vs nonprod)
    /// @return ownerAddresses Array of owner addresses for the Deployer Safe
    /// @return threshold Required number of signatures
    function getDeployerSafeConfig() internal returns (address[] memory ownerAddresses, uint256 threshold) {
        string memory toml = _toml();
        string memory env = _isProductionChain() ? "prod" : "nonprod";
        string memory prefix = string.concat(".safe.", env);

        threshold = vm.parseTomlUint(toml, string.concat(prefix, ".deployer_safe_threshold"));

        // For production, we have 3 owners; for non-production, we have 1 owner
        if (_isProductionChain()) {
            ownerAddresses = new address[](3);
            ownerAddresses[0] = vm.parseTomlAddress(toml, string.concat(prefix, ".deployer_safe_owner_1"));
            ownerAddresses[1] = vm.parseTomlAddress(toml, string.concat(prefix, ".deployer_safe_owner_2"));
            ownerAddresses[2] = vm.parseTomlAddress(toml, string.concat(prefix, ".deployer_safe_owner_3"));
        } else {
            ownerAddresses = new address[](1);
            ownerAddresses[0] = vm.parseTomlAddress(toml, string.concat(prefix, ".deployer_safe_owner_1"));
        }
    }

    /// @dev Returns the expected Safe Executor EOA addresses based on current chain (prod vs nonprod)
    /// @return guardianExecutor Expected Safe Executor EOA address for Guardian Safe module
    /// @return deployerExecutor Expected Safe Executor EOA address for Deployer Safe module
    function getExpectedExecutorEOAAddresses() internal returns (address guardianExecutor, address deployerExecutor) {
        string memory toml = _toml();
        string memory env = _isProductionChain() ? "prod" : "nonprod";
        string memory prefix = string.concat(".safe.", env);

        guardianExecutor = vm.parseTomlAddress(toml, string.concat(prefix, ".guardian_executor_eoa"));
        deployerExecutor = vm.parseTomlAddress(toml, string.concat(prefix, ".deployer_executor_eoa"));

        // Validate addresses are set for production chains
        if (_isProductionChain()) {
            require(guardianExecutor != address(0), "Guardian Executor EOA not set in deployment.toml for production");
            require(deployerExecutor != address(0), "Deployer Executor EOA not set in deployment.toml for production");
        }
    }
}
