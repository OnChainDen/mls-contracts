// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity >=0.7.0 <0.9.0;

import {Script} from "forge-std/Script.sol";

import {DeploymentConstants} from "script/base/DeploymentConstants.sol";
import {FactoryState} from "script/base/FactoryState.sol";
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
        string memory key = string(abi.encodePacked(".factory.", factoryName, ".factory"));
        return vm.parseTomlAddress(toml, key);
    }

    /// @dev Returns the factory deployer address for a given factory name
    /// @param factoryName The factory name (arachnid, den-prod, or den-nonprod)
    /// @return deployerAddress The factory deployer address
    function getFactoryDeployerAddress(string memory factoryName) internal returns (address deployerAddress) {
        string memory toml = _toml();
        string memory key = string(abi.encodePacked(".factory.", factoryName, ".factory_deployer"));
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
        string memory prefix = string(abi.encodePacked(".factory.", _factoryName));

        libs = PlatformLibraries({
            policyAddress: vm.parseTomlAddress(toml, string(abi.encodePacked(prefix, ".lib_org_policy"))),
            adminAddress: vm.parseTomlAddress(toml, string(abi.encodePacked(prefix, ".lib_org_admin"))),
            initializationAddress: vm.parseTomlAddress(toml, string(abi.encodePacked(prefix, ".lib_org_init"))),
            accountSignatureAddress: vm.parseTomlAddress(
                toml, string(abi.encodePacked(prefix, ".lib_org_account_sig"))
            ),
            txRecoveryAddress: vm.parseTomlAddress(toml, string(abi.encodePacked(prefix, ".lib_org_tx_recovery"))),
            // forgefmt: disable-next-item
            guardianRecoveryAddress: vm.parseTomlAddress(
                toml, string(abi.encodePacked(prefix, ".lib_org_guardian_recovery"))
            )
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
        string memory prefix = string(abi.encodePacked(".factory.", _factoryName));

        safeInfra = SafeInfrastructure({
            singletonAddress: vm.parseTomlAddress(toml, string(abi.encodePacked(prefix, ".safe_singleton"))),
            proxyFactoryAddress: vm.parseTomlAddress(toml, string(abi.encodePacked(prefix, ".safe_proxy_factory"))),
            fallbackHandlerAddress: vm.parseTomlAddress(
                toml, string(abi.encodePacked(prefix, ".safe_fallback_handler"))
            ),
            multiSendAddress: vm.parseTomlAddress(toml, string(abi.encodePacked(prefix, ".safe_multisend"))),
            multiSendCallOnlyAddress: vm.parseTomlAddress(
                toml, string(abi.encodePacked(prefix, ".safe_multisend_call_only"))
            ),
            createCallAddress: vm.parseTomlAddress(toml, string(abi.encodePacked(prefix, ".safe_create_call"))),
            simulateTxAccessorAddress: vm.parseTomlAddress(
                toml, string(abi.encodePacked(prefix, ".safe_simulate_tx_accessor"))
            )
        });
    }

    /// @dev Returns expected Guardian Safe address based on the initialized factory and chain (prod vs nonprod)
    ///      NOTE: validateAndInitializeFactoryOrRevert() must be called first
    /// @return guardianSafeAddress The expected Guardian Safe address
    function getExpectedGuardianSafeAddress() internal returns (address guardianSafeAddress) {
        require(
            _factoryAddress != address(0), "Factory not initialized - call validateAndInitializeFactoryOrRevert() first"
        );

        string memory toml = _toml();
        string memory variant = _isProductionChain() ? "prod" : "nonprod";
        string memory key = string(abi.encodePacked(".factory.", _factoryName, ".env.", variant, ".guardian_safe"));
        return vm.parseTomlAddress(toml, key);
    }

    /// @dev Returns expected Admin Safe address based on the initialized factory and chain (prod vs nonprod)
    ///      NOTE: validateAndInitializeFactoryOrRevert() must be called first
    /// @return adminSafeAddress The expected Admin Safe address
    function getExpectedAdminSafeAddress() internal returns (address adminSafeAddress) {
        require(
            _factoryAddress != address(0), "Factory not initialized - call validateAndInitializeFactoryOrRevert() first"
        );

        string memory toml = _toml();
        string memory variant = _isProductionChain() ? "prod" : "nonprod";
        string memory key = string(abi.encodePacked(".factory.", _factoryName, ".env.", variant, ".admin_safe"));
        return vm.parseTomlAddress(toml, key);
    }

    /// @dev Returns expected OrganizationFactory address based on the initialized factory and chain (prod vs nonprod)
    ///      NOTE: validateAndInitializeFactoryOrRevert() must be called first
    /// @return orgFactoryAddress The expected OrganizationFactory address
    function getExpectedOrgFactoryAddress() internal returns (address orgFactoryAddress) {
        require(
            _factoryAddress != address(0), "Factory not initialized - call validateAndInitializeFactoryOrRevert() first"
        );

        string memory toml = _toml();
        string memory variant = _isProductionChain() ? "prod" : "nonprod";
        string memory key = string(abi.encodePacked(".factory.", _factoryName, ".env.", variant, ".org_factory"));
        return vm.parseTomlAddress(toml, key);
    }

    /// @dev Returns expected ImplementationWhitelistProxy address based on the initialized factory and chain
    ///      NOTE: validateAndInitializeFactoryOrRevert() must be called first
    /// @return whitelistProxyAddress The expected ImplementationWhitelistProxy address
    function getExpectedWhitelistProxyAddress() internal returns (address whitelistProxyAddress) {
        require(
            _factoryAddress != address(0), "Factory not initialized - call validateAndInitializeFactoryOrRevert() first"
        );

        string memory toml = _toml();
        string memory variant = _isProductionChain() ? "prod" : "nonprod";
        string memory key = string(abi.encodePacked(".factory.", _factoryName, ".env.", variant, ".whitelist_proxy"));
        return vm.parseTomlAddress(toml, key);
    }

    /// @dev Returns expected Guardian Safe Executor Module address based on the initialized factory and chain
    ///      NOTE: validateAndInitializeFactoryOrRevert() must be called first
    /// @return guardianModuleAddress Expected Guardian Safe Executor Module address
    function getExpectedGuardianSafeModuleAddress() internal returns (address guardianModuleAddress) {
        require(
            _factoryAddress != address(0), "Factory not initialized - call validateAndInitializeFactoryOrRevert() first"
        );

        string memory toml = _toml();
        string memory variant = _isProductionChain() ? "prod" : "nonprod";
        string memory key =
            string(abi.encodePacked(".factory.", _factoryName, ".env.", variant, ".guardian_safe_executor_module"));

        guardianModuleAddress = vm.parseTomlAddress(toml, key);

        require(guardianModuleAddress != address(0), "Guardian Safe Executor Module address not set in deployment.toml");
    }

    /// @dev Returns expected BatchedTransaction address based on the initialized factory
    ///      NOTE: validateAndInitializeFactoryOrRevert() must be called first
    /// @return batchedTransactionAddress The expected BatchedTransaction address
    function getExpectedBatchedTransactionAddress() internal returns (address batchedTransactionAddress) {
        require(
            _factoryAddress != address(0), "Factory not initialized - call validateAndInitializeFactoryOrRevert() first"
        );

        string memory toml = _toml();
        string memory key = string(abi.encodePacked(".factory.", _factoryName, ".batched_transaction"));
        batchedTransactionAddress = vm.parseTomlAddress(toml, key);

        require(batchedTransactionAddress != address(0), "BatchedTransaction address not set in deployment.toml");
    }

    /// @dev Returns Guardian Safe configuration for a specific variant
    /// @param variant The Safe variant ("prod" or "nonprod")
    /// @return ownerAddresses Array of owner addresses for the Guardian Safe
    /// @return threshold Required number of signatures
    function getGuardianSafeConfig(string memory variant)
        internal
        returns (address[] memory ownerAddresses, uint256 threshold)
    {
        string memory toml = _toml();
        string memory prefix = string(abi.encodePacked(".safe.", variant));

        threshold = vm.parseTomlUint(toml, string(abi.encodePacked(prefix, ".guardian_safe_threshold")));

        // Check if this is prod variant (has 3 owners) or nonprod (has 1 owner)
        bool isProd = keccak256(bytes(variant)) == keccak256(bytes("prod"));
        if (isProd) {
            ownerAddresses = new address[](3);
            ownerAddresses[0] = vm.parseTomlAddress(toml, string(abi.encodePacked(prefix, ".guardian_safe_owner_1")));
            ownerAddresses[1] = vm.parseTomlAddress(toml, string(abi.encodePacked(prefix, ".guardian_safe_owner_2")));
            ownerAddresses[2] = vm.parseTomlAddress(toml, string(abi.encodePacked(prefix, ".guardian_safe_owner_3")));
        } else {
            ownerAddresses = new address[](1);
            ownerAddresses[0] = vm.parseTomlAddress(toml, string(abi.encodePacked(prefix, ".guardian_safe_owner_1")));
        }
    }

    /// @dev Returns Admin Safe configuration for a specific variant
    /// @param variant The Safe variant ("prod" or "nonprod")
    /// @return ownerAddresses Array of owner addresses for the Admin Safe
    /// @return threshold Required number of signatures
    function getAdminSafeConfig(string memory variant)
        internal
        returns (address[] memory ownerAddresses, uint256 threshold)
    {
        string memory toml = _toml();
        string memory prefix = string(abi.encodePacked(".safe.", variant));

        threshold = vm.parseTomlUint(toml, string(abi.encodePacked(prefix, ".admin_safe_threshold")));

        // Check if this is prod variant (has 3 owners) or nonprod (has 1 owner)
        bool isProd = keccak256(bytes(variant)) == keccak256(bytes("prod"));
        if (isProd) {
            ownerAddresses = new address[](3);
            ownerAddresses[0] = vm.parseTomlAddress(toml, string(abi.encodePacked(prefix, ".admin_safe_owner_1")));
            ownerAddresses[1] = vm.parseTomlAddress(toml, string(abi.encodePacked(prefix, ".admin_safe_owner_2")));
            ownerAddresses[2] = vm.parseTomlAddress(toml, string(abi.encodePacked(prefix, ".admin_safe_owner_3")));
        } else {
            ownerAddresses = new address[](1);
            ownerAddresses[0] = vm.parseTomlAddress(toml, string(abi.encodePacked(prefix, ".admin_safe_owner_1")));
        }
    }

    /// @dev Returns the expected Guardian Executor EOA address based on current chain (prod vs nonprod)
    /// @return guardianExecutor Expected Guardian Executor EOA address for Guardian Safe module
    function getExpectedGuardianExecutorEOAAddress() internal returns (address guardianExecutor) {
        string memory toml = _toml();
        string memory env = _isProductionChain() ? "prod" : "nonprod";
        string memory key = string(abi.encodePacked(".safe.", env, ".guardian_executor_eoa"));

        guardianExecutor = vm.parseTomlAddress(toml, key);

        // Validate address is set for production chains
        if (_isProductionChain()) {
            require(guardianExecutor != address(0), "Guardian Executor EOA not set in deployment.toml for production");
        }
    }
}
