// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity >=0.7.0 <0.9.0;

import {Vm} from "forge-std/Vm.sol";

import {PlatformLibraries, SafeInfrastructure} from "script/libraries/Types.sol";

/**
 * @title DeploymentConfig
 * @notice Configuration for deterministic contract deployment
 * @dev Contains deployment salts and runtime TOML parsing for addresses.
 *      All addresses are read from deployment.toml at runtime using Foundry's vm.parseTomlAddress().
 *      This ensures deployment.toml is the single source of truth for all addresses.
 * @author Den Technologies Inc
 */
library DeploymentConfig {
    // ==================== TOML Configuration ====================
    // Path to the deployment configuration file (relative to project root)
    // ==============================================================================
    string internal constant DEPLOYMENT_TOML_PATH = "deployment.toml";

    // ==================== Hardcoded Salts ====================
    // These are the hardcoded salts for deploying contracts and linked-libraries via CREATE2 to achieve deterministic
    // addresses. These salts are not expected to change, so they are hardcoded in the library.
    // ==============================================================================
    /// @dev Salt for Safe Singleton (master copy) deployment
    bytes32 internal constant SAFE_SINGLETON_SALT = keccak256("den.external.safe.singleton.v1");

    /// @dev Salt for Safe Proxy Factory deployment
    bytes32 internal constant SAFE_PROXY_FACTORY_SALT = keccak256("den.external.safe.proxy-factory.v1");

    /// @dev Salt for Safe Compatibility Fallback Handler deployment
    bytes32 internal constant SAFE_FALLBACK_HANDLER_SALT = keccak256("den.external.safe.fallback-handler.v1");

    /// @dev Salt for Safe MultiSend deployment
    bytes32 internal constant SAFE_MULTISEND_SALT = keccak256("den.external.safe.multisend.v1");

    /// @dev Salt for Safe MultiSendCallOnly deployment
    bytes32 internal constant SAFE_MULTISEND_CALL_ONLY_SALT = keccak256("den.external.safe.multisend-call-only.v1");

    /// @dev Salt for Safe CreateCall library deployment
    bytes32 internal constant SAFE_CREATE_CALL_SALT = keccak256("den.external.safe.create-call.v1");

    /// @dev Salt for Safe SimulateTxAccessor deployment
    bytes32 internal constant SAFE_SIMULATE_TX_ACCESSOR_SALT = keccak256("den.external.safe.simulate-tx-accessor.v1");

    /// @dev Salt for Guardian Safe (used as Organization guardian)
    bytes32 internal constant GUARDIAN_SAFE_SALT = keccak256("den.mls-wallet.safe.guardian.v1");

    /// @dev Salt for Deployer Safe (used as factory deployer)
    bytes32 internal constant DEPLOYER_SAFE_SALT = keccak256("den.mls-wallet.safe.deployer.v1");

    /// @dev Salt for LibOrganizationPolicy library deployment
    bytes32 internal constant LIB_ORG_POLICY_SALT = keccak256("den.mls-wallet.organization.lib.policy.v1");

    /// @dev Salt for LibOrganizationAdmin library deployment
    bytes32 internal constant LIB_ORG_ADMIN_SALT = keccak256("den.mls-wallet.organization.lib.admin.v1");

    /// @dev Salt for LibOrganizationInitialization library deployment
    bytes32 internal constant LIB_ORG_INIT_SALT = keccak256("den.mls-wallet.organization.lib.initialization.v1");

    /// @dev Salt for LibOrganizationAccountSignature library deployment
    bytes32 internal constant LIB_ORG_ACCOUNT_SIG_SALT =
        keccak256("den.mls-wallet.organization.lib.account-signature.v1");

    /// @dev Salt for OrganizationImplementation deployment
    bytes32 internal constant ORG_IMPL_SALT = keccak256("den.mls-wallet.organization.implementation.v1");

    /// @dev Salt for AccountImplementation deployment
    bytes32 internal constant ACCOUNT_IMPL_SALT = keccak256("den.mls-wallet.account.implementation.v1");

    /// @dev Salt for ImplementationWhitelistImplementation deployment
    bytes32 internal constant WHITELIST_IMPL_SALT = keccak256("den.mls-wallet.whitelist.implementation.v1");

    /// @dev Salt for OrganizationFactory deployment
    bytes32 internal constant ORG_FACTORY_SALT = keccak256("den.mls-wallet.organization.factory.v1");

    /// @dev Salt for ImplementationWhitelistProxy deployment (via factory)
    bytes32 internal constant WHITELIST_PROXY_SALT = keccak256("den.mls-wallet.whitelist.proxy.v1");

    /// @dev Salt for Guardian Safe Executor Module deployment
    bytes32 internal constant GUARDIAN_SAFE_EXECUTOR_MODULE_SALT =
        keccak256("den.mls-wallet.safe-module.eoa-executor.guardian.v1");

    /// @dev Salt for Deployer Safe Executor Module deployment
    bytes32 internal constant DEPLOYER_SAFE_EXECUTOR_MODULE_SALT =
        keccak256("den.mls-wallet.safe-module.eoa-executor.deployer.v1");

    /// @dev Salt for BatchedTransaction deployment
    bytes32 internal constant BATCHED_TRANSACTION_SALT = keccak256("den.mls-wallet.batched-transaction.v1");

    // ==================== Hardcoded Library Paths ====================
    // These are the hardcoded paths for the platform libraries that are used when deploying contracts that
    // link to the platform libraries. These paths are used to print the foundry --libraries flag that should
    // be used when running DeployContracts.s.sol.
    //
    // These paths are not expected to change, so they are hardcoded.
    //
    // IMPORTANT: These paths must be updated if library paths change.
    // ==============================================================================

    /// @dev Library path for LibOrganizationPolicy (used when deploying libraries to print the
    ///      foundry --libraries flag that should be used when running DeployContracts.s.sol)
    string internal constant LIB_ORG_POLICY_PATH =
        "src/organization/libraries/LibOrganizationPolicy.sol:LibOrganizationPolicy";

    /// @dev Library path for LibOrganizationAdmin (used when deploying libraries to print the
    ///      foundry --libraries flag that should be used when running DeployContracts.s.sol)
    string internal constant LIB_ORG_ADMIN_PATH =
        "src/organization/libraries/LibOrganizationAdmin.sol:LibOrganizationAdmin";

    /// @dev Library path for LibOrganizationInitialization (used when deploying libraries to print the
    ///      foundry --libraries flag that should be used when running DeployContracts.s.sol)
    string internal constant LIB_ORG_INIT_PATH =
        "src/organization/libraries/LibOrganizationInitialization.sol:LibOrganizationInitialization";

    /// @dev Library path for LibOrganizationAccountSignature (used when deploying libraries to print the
    ///      foundry --libraries flag that should be used when running DeployContracts.s.sol)
    string internal constant LIB_ORG_ACCOUNT_SIG_PATH =
        "src/organization/libraries/LibOrganizationAccountSignature.sol:LibOrganizationAccountSignature";

    // ==================== Factory Name Constants ====================
    // These are used to build TOML key paths for address lookups
    // ==============================================================================
    string internal constant FACTORY_ARACHNID = "arachnid";
    string internal constant FACTORY_DEN_PROD = "den-prod";
    string internal constant FACTORY_DEN_NONPROD = "den-nonprod";

    // ==================== Production Deployer Safety Check ====================
    // This is the only hardcoded address constant needed - used for safety checks to prevent
    // accidentally using the production deployer EOA for non-factory deployments.
    // ==============================================================================
    /// @dev Production Den Factory deployer EOA address (used for safety checks)
    ///      This EOA should ONLY be used by DeployDenSingletonFactory.s.sol
    address internal constant PROD_DEN_FACTORY_DEPLOYER_ADDRESS = 0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7;

    // ==================== Helper Functions ====================
    // These are helper functions for chain ID checks and TOML parsing
    // ==============================================================================

    /// @dev Returns true if the given chain ID is a production network
    /// @param chainId The chain ID to check
    /// @return True if the chain is a production network
    function isProductionChain(uint256 chainId) internal pure returns (bool) {
        return chainId == 1 // Ethereum Mainnet
            || chainId == 10 // Optimism
            || chainId == 56 // BNB Smart Chain
            || chainId == 137 // Polygon
            || chainId == 8453 // Base
            || chainId == 42_161 // Arbitrum One
            || chainId == 43_114; // Avalanche C-Chain
    }

    /// @dev Returns the factory name for a given factory address
    /// @param vm The Foundry VM instance for TOML parsing
    /// @param factoryAddress The factory address to look up
    /// @return factoryName The factory name (arachnid, den-prod, or den-nonprod)
    function getFactoryName(Vm vm, address factoryAddress) internal view returns (string memory factoryName) {
        string memory toml = vm.readFile(DEPLOYMENT_TOML_PATH);

        // Check each factory namespace
        if (factoryAddress == vm.parseTomlAddress(toml, ".factory.arachnid.factory")) {
            return FACTORY_ARACHNID;
        }
        if (factoryAddress == vm.parseTomlAddress(toml, ".factory.den-prod.factory")) {
            return FACTORY_DEN_PROD;
        }
        if (factoryAddress == vm.parseTomlAddress(toml, ".factory.den-nonprod.factory")) {
            return FACTORY_DEN_NONPROD;
        }

        revert("Unknown factory address - not found in deployment.toml");
    }

    /// @dev Returns the factory address for a given factory name
    /// @param vm The Foundry VM instance for TOML parsing
    /// @param factoryName The factory name (arachnid, den-prod, or den-nonprod)
    /// @return factoryAddress The factory address
    function getFactoryAddress(Vm vm, string memory factoryName) internal view returns (address factoryAddress) {
        string memory toml = vm.readFile(DEPLOYMENT_TOML_PATH);
        string memory key = string.concat(".factory.", factoryName, ".factory");
        return vm.parseTomlAddress(toml, key);
    }

    /// @dev Returns the factory deployer address for a given factory name
    /// @param vm The Foundry VM instance for TOML parsing
    /// @param factoryName The factory name (arachnid, den-prod, or den-nonprod)
    /// @return deployerAddress The factory deployer address
    function getFactoryDeployerAddress(Vm vm, string memory factoryName)
        internal
        view
        returns (address deployerAddress)
    {
        string memory toml = vm.readFile(DEPLOYMENT_TOML_PATH);
        string memory key = string.concat(".factory.", factoryName, ".factory_deployer");
        return vm.parseTomlAddress(toml, key);
    }

    // ==================== Library Address Getters ====================
    // Read library addresses from deployment.toml based on factory
    // ==============================================================================

    /// @dev Returns expected library addresses based on which CREATE2 factory was used for deployment
    /// @param vm The Foundry VM instance for TOML parsing
    /// @param factoryAddress The CREATE2 factory address used to deploy the libraries
    /// @return libs Struct containing expected library addresses
    function getExpectedLibraryAddresses(Vm vm, address factoryAddress)
        internal
        view
        returns (PlatformLibraries memory libs)
    {
        string memory factoryName = getFactoryName(vm, factoryAddress);
        string memory toml = vm.readFile(DEPLOYMENT_TOML_PATH);
        string memory prefix = string.concat(".factory.", factoryName);

        libs = PlatformLibraries({
            policyAddress: vm.parseTomlAddress(toml, string.concat(prefix, ".lib_org_policy")),
            adminAddress: vm.parseTomlAddress(toml, string.concat(prefix, ".lib_org_admin")),
            initializationAddress: vm.parseTomlAddress(toml, string.concat(prefix, ".lib_org_init")),
            accountSignatureAddress: vm.parseTomlAddress(toml, string.concat(prefix, ".lib_org_account_sig"))
        });
    }

    // ==================== Safe Infrastructure Address Getters ====================
    // Read Safe 1.3.0 infrastructure addresses from deployment.toml based on factory
    // ==============================================================================

    /// @dev Returns expected Safe infrastructure addresses based on which CREATE2 factory was used for deployment
    /// @param vm The Foundry VM instance for TOML parsing
    /// @param factoryAddress The CREATE2 factory address used to deploy the Safe infrastructure
    /// @return safeInfra Struct containing expected Safe infrastructure addresses
    function getExpectedSafeInfrastructureAddresses(Vm vm, address factoryAddress)
        internal
        view
        returns (SafeInfrastructure memory safeInfra)
    {
        string memory factoryName = getFactoryName(vm, factoryAddress);
        string memory toml = vm.readFile(DEPLOYMENT_TOML_PATH);
        string memory prefix = string.concat(".factory.", factoryName);

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

    /// @dev Returns expected Guardian Safe address based on which CREATE2 factory was used for deployment
    /// @param vm The Foundry VM instance for TOML parsing
    /// @param factoryAddress The CREATE2 factory address used to deploy the Safe
    /// @return guardianSafeAddress The expected Guardian Safe address
    function getExpectedGuardianSafeAddress(Vm vm, address factoryAddress)
        internal
        view
        returns (address guardianSafeAddress)
    {
        string memory factoryName = getFactoryName(vm, factoryAddress);
        string memory toml = vm.readFile(DEPLOYMENT_TOML_PATH);
        string memory key = string.concat(".factory.", factoryName, ".guardian_safe");
        return vm.parseTomlAddress(toml, key);
    }

    /// @dev Returns expected Deployer Safe address based on which CREATE2 factory was used for deployment
    /// @param vm The Foundry VM instance for TOML parsing
    /// @param factoryAddress The CREATE2 factory address used to deploy the Safe
    /// @return deployerSafeAddress The expected Deployer Safe address
    function getExpectedDeployerSafeAddress(Vm vm, address factoryAddress)
        internal
        view
        returns (address deployerSafeAddress)
    {
        string memory factoryName = getFactoryName(vm, factoryAddress);
        string memory toml = vm.readFile(DEPLOYMENT_TOML_PATH);
        string memory key = string.concat(".factory.", factoryName, ".deployer_safe");
        return vm.parseTomlAddress(toml, key);
    }

    // ==================== Safe Executor Module Address Getters ====================
    // Read Safe Executor Module addresses from deployment.toml based on factory
    // ==============================================================================

    /// @dev Returns expected Safe Executor Module addresses based on which CREATE2 factory was used
    /// @param vm The Foundry VM instance for TOML parsing
    /// @param factoryAddress The CREATE2 factory address used to deploy the modules
    /// @return guardianModuleAddress Expected Guardian Safe Executor Module address
    /// @return deployerModuleAddress Expected Deployer Safe Executor Module address
    function getExpectedSafeExecutorModuleAddresses(Vm vm, address factoryAddress)
        internal
        view
        returns (address guardianModuleAddress, address deployerModuleAddress)
    {
        string memory factoryName = getFactoryName(vm, factoryAddress);
        string memory toml = vm.readFile(DEPLOYMENT_TOML_PATH);
        string memory prefix = string.concat(".factory.", factoryName);

        guardianModuleAddress = vm.parseTomlAddress(toml, string.concat(prefix, ".guardian_safe_executor_module"));
        deployerModuleAddress = vm.parseTomlAddress(toml, string.concat(prefix, ".deployer_safe_executor_module"));

        // Validate addresses are set (not zero) for production deployments
        require(guardianModuleAddress != address(0), "Guardian Safe Executor Module address not set in deployment.toml");
        require(deployerModuleAddress != address(0), "Deployer Safe Executor Module address not set in deployment.toml");
    }

    // ==================== BatchedTransaction Address Getter ====================
    // Read BatchedTransaction address from deployment.toml based on factory
    // ==============================================================================

    /// @dev Returns expected BatchedTransaction address based on which CREATE2 factory was used for deployment
    /// @param vm The Foundry VM instance for TOML parsing
    /// @param factoryAddress The CREATE2 factory address used to deploy the BatchedTransaction
    /// @return batchedTransactionAddress The expected BatchedTransaction address
    function getExpectedBatchedTransactionAddress(Vm vm, address factoryAddress)
        internal
        view
        returns (address batchedTransactionAddress)
    {
        string memory factoryName = getFactoryName(vm, factoryAddress);
        string memory toml = vm.readFile(DEPLOYMENT_TOML_PATH);
        string memory key = string.concat(".factory.", factoryName, ".batched_transaction");
        batchedTransactionAddress = vm.parseTomlAddress(toml, key);

        require(batchedTransactionAddress != address(0), "BatchedTransaction address not set in deployment.toml");
    }

    // ==================== Safe Configuration Getters ====================
    // Read Safe multisig configurations from deployment.toml based on environment (prod/nonprod)
    // ==============================================================================

    /// @dev Returns Guardian Safe configuration based on chain ID (prod vs nonprod)
    /// @param vm The Foundry VM instance for TOML parsing
    /// @param chainId The target chain ID
    /// @return ownerAddresses Array of owner addresses for the Guardian Safe
    /// @return threshold Required number of signatures
    function getGuardianSafeConfig(Vm vm, uint256 chainId)
        internal
        view
        returns (address[] memory ownerAddresses, uint256 threshold)
    {
        string memory toml = vm.readFile(DEPLOYMENT_TOML_PATH);
        string memory env = isProductionChain(chainId) ? "prod" : "nonprod";
        string memory prefix = string.concat(".safe.", env);

        threshold = vm.parseTomlUint(toml, string.concat(prefix, ".guardian_safe_threshold"));

        // For production, we have 3 owners; for non-production, we have 1 owner
        if (isProductionChain(chainId)) {
            ownerAddresses = new address[](3);
            ownerAddresses[0] = vm.parseTomlAddress(toml, string.concat(prefix, ".guardian_safe_owner_1"));
            ownerAddresses[1] = vm.parseTomlAddress(toml, string.concat(prefix, ".guardian_safe_owner_2"));
            ownerAddresses[2] = vm.parseTomlAddress(toml, string.concat(prefix, ".guardian_safe_owner_3"));
        } else {
            ownerAddresses = new address[](1);
            ownerAddresses[0] = vm.parseTomlAddress(toml, string.concat(prefix, ".guardian_safe_owner_1"));
        }
    }

    /// @dev Returns Deployer Safe configuration based on chain ID (prod vs nonprod)
    /// @param vm The Foundry VM instance for TOML parsing
    /// @param chainId The target chain ID
    /// @return ownerAddresses Array of owner addresses for the Deployer Safe
    /// @return threshold Required number of signatures
    function getDeployerSafeConfig(Vm vm, uint256 chainId)
        internal
        view
        returns (address[] memory ownerAddresses, uint256 threshold)
    {
        string memory toml = vm.readFile(DEPLOYMENT_TOML_PATH);
        string memory env = isProductionChain(chainId) ? "prod" : "nonprod";
        string memory prefix = string.concat(".safe.", env);

        threshold = vm.parseTomlUint(toml, string.concat(prefix, ".deployer_safe_threshold"));

        // For production, we have 3 owners; for non-production, we have 1 owner
        if (isProductionChain(chainId)) {
            ownerAddresses = new address[](3);
            ownerAddresses[0] = vm.parseTomlAddress(toml, string.concat(prefix, ".deployer_safe_owner_1"));
            ownerAddresses[1] = vm.parseTomlAddress(toml, string.concat(prefix, ".deployer_safe_owner_2"));
            ownerAddresses[2] = vm.parseTomlAddress(toml, string.concat(prefix, ".deployer_safe_owner_3"));
        } else {
            ownerAddresses = new address[](1);
            ownerAddresses[0] = vm.parseTomlAddress(toml, string.concat(prefix, ".deployer_safe_owner_1"));
        }
    }

    /// @dev Returns the expected Safe Executor EOA addresses based on chain ID (prod vs nonprod)
    /// @param vm The Foundry VM instance for TOML parsing
    /// @param chainId The target chain ID
    /// @return guardianExecutor Expected Safe Executor EOA address for Guardian Safe module
    /// @return deployerExecutor Expected Safe Executor EOA address for Deployer Safe module
    function getExpectedExecutorEOAAddresses(Vm vm, uint256 chainId)
        internal
        view
        returns (address guardianExecutor, address deployerExecutor)
    {
        string memory toml = vm.readFile(DEPLOYMENT_TOML_PATH);
        string memory env = isProductionChain(chainId) ? "prod" : "nonprod";
        string memory prefix = string.concat(".safe.", env);

        guardianExecutor = vm.parseTomlAddress(toml, string.concat(prefix, ".guardian_executor_eoa"));
        deployerExecutor = vm.parseTomlAddress(toml, string.concat(prefix, ".deployer_executor_eoa"));

        // Validate addresses are set for production chains
        if (isProductionChain(chainId)) {
            require(guardianExecutor != address(0), "Guardian Executor EOA not set in deployment.toml for production");
            require(deployerExecutor != address(0), "Deployer Executor EOA not set in deployment.toml for production");
        }
    }
}
