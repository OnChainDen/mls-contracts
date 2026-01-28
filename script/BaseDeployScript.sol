// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity >=0.7.0 <0.9.0;

import {Script, VmSafe} from "forge-std/Script.sol";

import {Create2Utils} from "script/libraries/Create2Utils.sol";
import {Logger} from "script/libraries/Logger.sol";
import {StringUtils} from "script/libraries/StringUtils.sol";
import {PlatformLibraries, SafeInfrastructure} from "script/libraries/Types.sol";

/**
 * @title BaseDeployScript
 * @notice Base contract for all deployment scripts providing config, utilities, and common functionality
 * @dev This abstract contract provides:
 *      - All deployment constants (salts, library paths)
 *      - Cached TOML reading for addresses from deployment.toml
 *      - Factory initialization and validation
 *      - Common deployment utilities (confirmation prompts, logging)
 *
 *      This contract uses a floating pragma (>=0.7.0 <0.9.0) to allow reuse by both
 *      platform scripts (0.8.33) and Safe deployment scripts (0.7.6).
 *
 * @author Den Technologies Inc
 */
abstract contract BaseDeployScript is Script {
    // ==================== Cached TOML ====================
    // The TOML content is read once and cached for subsequent reads
    // ==============================================================================
    string private _tomlContent;

    /// @dev Lazily reads and caches the TOML content
    /// @return The cached TOML content
    function _toml() internal returns (string memory) {
        if (bytes(_tomlContent).length == 0) {
            _tomlContent = vm.readFile("deployment.toml");
        }
        return _tomlContent;
    }

    // ==================== Factory Storage ====================
    // These are set by validateAndInitializeFactoryOrRevert() and used throughout the script
    // ==============================================================================

    /// @dev The CREATE2 factory address (set by validateAndInitializeFactoryOrRevert)
    address internal _factoryAddress;

    /// @dev The factory key for TOML lookups (e.g., "arachnid", "den-prod", "den-nonprod")
    string internal _factoryName;

    /// @dev The human-readable factory name for logging (e.g., "Arachnid Deterministic Deployment Proxy")
    string internal _factoryDisplayName;

    // ==================== Deployment Salts ====================
    // These are the hardcoded salts for deploying contracts via CREATE2 to achieve deterministic addresses.
    // These salts are not expected to change, so they are hardcoded.
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

    // ==================== Factory Name Constants ====================
    // These are used to build TOML key paths for address lookups
    // ==============================================================================

    string internal constant FACTORY_ARACHNID = "arachnid";
    string internal constant FACTORY_DEN_PROD = "den-prod";
    string internal constant FACTORY_DEN_NONPROD = "den-nonprod";

    // ==================== Factory Initialization ====================
    // Call this at the start of your script to validate and store the factory
    // ==============================================================================

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

    // ==================== Chain ID Utilities ====================
    // For 0.7.x compatibility (block.chainid was added in 0.8.0)
    // ==============================================================================

    /// @dev Gets the current chain ID using inline assembly for 0.7.x compatibility
    /// @return chainId The chain ID of the current network
    function _getChainId() internal view returns (uint256 chainId) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            chainId := chainid()
        }
    }

    /// @dev Returns true if the given chain ID is a production network
    /// @param chainId The chain ID to check
    /// @return True if the chain is a production network
    function _isProductionChain(uint256 chainId) internal pure returns (bool) {
        return chainId == 1 // Ethereum Mainnet
            || chainId == 10 // Optimism
            || chainId == 56 // BNB Smart Chain
            || chainId == 137 // Polygon
            || chainId == 8453 // Base
            || chainId == 42_161 // Arbitrum One
            || chainId == 43_114; // Avalanche C-Chain
    }

    // ==================== Confirmation Prompts ====================
    // ==============================================================================

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
        uint256 chainId = _getChainId();
        bool isProdChain = _isProductionChain(chainId);

        if (isProdChain) {
            // solhint-disable-next-line func-named-parameters
            string memory context = string(
                abi.encodePacked(
                    "\n",
                    "  !! PRODUCTION CHAIN DETECTED !!\n",
                    "  Script: ",
                    scriptName,
                    "\n",
                    "  Chain ID: ",
                    StringUtils.toString(chainId)
                )
            );
            _promptForConfirmationOrRevert(context);
            Logger.logEmptyLine();
        } else {
            Logger.logInfo("NON-PRODUCTION CHAIN DETECTED");
            Logger.logKeyValue("Script", scriptName);
            Logger.logKeyValue("Chain ID", chainId);
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

    /// @dev Logs deployment summary header with factory and chain info
    ///      NOTE: validateAndInitializeFactoryOrRevert() must be called first
    function logDeploymentHeader() internal {
        require(
            _factoryAddress != address(0), "Factory not initialized - call validateAndInitializeFactoryOrRevert() first"
        );

        Logger.logBoxHeader("Den Multi-layer Security (MLS) Wallet - Contract Deployment");
        Logger.logKeyValue("Chain ID", _getChainId());
        Logger.logKeyValue("CREATE2 Factory", _factoryAddress);
        Logger.logKeyValue("Factory Type", _factoryDisplayName);
        Logger.logBoxFooter();
        Logger.logEmptyLine();
    }

    // ==================== Factory Address Getters ====================
    // Read factory addresses from deployment.toml
    // ==============================================================================

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

    // ==================== Library Address Getters ====================
    // Read library addresses from deployment.toml based on initialized factory
    // ==============================================================================

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

    // ==================== Safe Infrastructure Address Getters ====================
    // Read Safe 1.3.0 infrastructure addresses from deployment.toml
    // ==============================================================================

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

    // ==================== Safe Executor Module Address Getters ====================
    // Read Safe Executor Module addresses from deployment.toml
    // ==============================================================================

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

    // ==================== BatchedTransaction Address Getter ====================
    // Read BatchedTransaction address from deployment.toml
    // ==============================================================================

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

    // ==================== Safe Configuration Getters ====================
    // Read Safe multisig configurations from deployment.toml based on environment (prod/nonprod)
    // ==============================================================================

    /// @dev Returns Guardian Safe configuration based on chain ID (prod vs nonprod)
    /// @param chainId The target chain ID
    /// @return ownerAddresses Array of owner addresses for the Guardian Safe
    /// @return threshold Required number of signatures
    function getGuardianSafeConfig(uint256 chainId)
        internal
        returns (address[] memory ownerAddresses, uint256 threshold)
    {
        string memory toml = _toml();
        string memory env = _isProductionChain(chainId) ? "prod" : "nonprod";
        string memory prefix = string.concat(".safe.", env);

        threshold = vm.parseTomlUint(toml, string.concat(prefix, ".guardian_safe_threshold"));

        // For production, we have 3 owners; for non-production, we have 1 owner
        if (_isProductionChain(chainId)) {
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
    /// @param chainId The target chain ID
    /// @return ownerAddresses Array of owner addresses for the Deployer Safe
    /// @return threshold Required number of signatures
    function getDeployerSafeConfig(uint256 chainId)
        internal
        returns (address[] memory ownerAddresses, uint256 threshold)
    {
        string memory toml = _toml();
        string memory env = _isProductionChain(chainId) ? "prod" : "nonprod";
        string memory prefix = string.concat(".safe.", env);

        threshold = vm.parseTomlUint(toml, string.concat(prefix, ".deployer_safe_threshold"));

        // For production, we have 3 owners; for non-production, we have 1 owner
        if (_isProductionChain(chainId)) {
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
    /// @param chainId The target chain ID
    /// @return guardianExecutor Expected Safe Executor EOA address for Guardian Safe module
    /// @return deployerExecutor Expected Safe Executor EOA address for Deployer Safe module
    function getExpectedExecutorEOAAddresses(uint256 chainId)
        internal
        returns (address guardianExecutor, address deployerExecutor)
    {
        string memory toml = _toml();
        string memory env = _isProductionChain(chainId) ? "prod" : "nonprod";
        string memory prefix = string.concat(".safe.", env);

        guardianExecutor = vm.parseTomlAddress(toml, string.concat(prefix, ".guardian_executor_eoa"));
        deployerExecutor = vm.parseTomlAddress(toml, string.concat(prefix, ".deployer_executor_eoa"));

        // Validate addresses are set for production chains
        if (_isProductionChain(chainId)) {
            require(guardianExecutor != address(0), "Guardian Executor EOA not set in deployment.toml for production");
            require(deployerExecutor != address(0), "Deployer Executor EOA not set in deployment.toml for production");
        }
    }
}
