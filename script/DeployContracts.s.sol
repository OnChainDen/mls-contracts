// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Safe} from "@safe/Safe.sol";
import {SimulateTxAccessor} from "@safe/accessors/SimulateTxAccessor.sol";
import {CompatibilityFallbackHandler} from "@safe/handler/CompatibilityFallbackHandler.sol";
import {CreateCall} from "@safe/libraries/CreateCall.sol";
import {MultiSend} from "@safe/libraries/MultiSend.sol";
import {MultiSendCallOnly} from "@safe/libraries/MultiSendCallOnly.sol";
import {SafeProxyFactory} from "@safe/proxies/SafeProxyFactory.sol";
import {Script} from "forge-std/Script.sol";

import {AccountImplementation} from "account/AccountImplementation.sol";
import {
    ImplementationWhitelistImplementation
} from "implementation-whitelist/ImplementationWhitelistImplementation.sol";
import {ImplementationWhitelistProxy} from "implementation-whitelist/ImplementationWhitelistProxy.sol";
import {OrganizationFactory} from "organization/OrganizationFactory.sol";
import {OrganizationImplementation} from "organization/OrganizationImplementation.sol";
import {DeploymentConfig} from "script/config/DeploymentConfig.sol";
import {Create2Utils} from "script/libraries/Create2Utils.sol";
import {LinkedLibrariesUtils} from "script/libraries/LinkedLibrariesUtils.sol";
import {Logger} from "script/libraries/Logger.sol";
import {SafeMultisigUtils} from "script/libraries/SafeMultisigUtils.sol";
import {ScriptUtils} from "script/libraries/ScriptUtils.sol";
import {PlatformLibraries, SafeInfrastructure} from "script/libraries/Types.sol";

/**
 * @title DeployContracts
 * @notice Deploys all platform contracts (Safe infrastructure, implementations, factories, proxies)
 * @dev This script must be run AFTER the DeployLibraries.s.sol script and must use the --libraries flags pointing
 *      to the library addresses outputted by the DeployLibraries.s.sol script.
 *
 *      This script also requires that the CREATE2 factory is already deployed and provided via the
 *      CREATE2_FACTORY_ADDRESS environment variable.
 *
 *      This script will revert if the libraries are not deployed at the expected addresses and if the
 *      script is not run with the --libraries flags pointing to the library addresses outputted by the
 *      DeployLibraries.s.sol script.
 *
 *      This script deploys the following contracts in the following order:
 *      1. Safe Infrastructure (Safe singleton, proxy factory, handlers, libraries)
 *      2. Safe Multisigs (Guardian Safe, Deployer Safe)
 *      3. Implementation Contracts (OrganizationImpl, AccountImpl, WhitelistImpl)
 *      4. Factory Contracts (OrganizationFactory)
 *      5. ImplementationWhitelistProxy
 *
 * @author Den Technologies Inc
 */
contract DeployContracts is Script {
    /// @dev Struct containing addresses for the deployed Safe multisig wallets
    struct SafeMultisigs {
        address guardianSafeAddress;
        address deployerSafeAddress;
    }

    /// @dev Struct containing addresses for the deployed platform implementation contracts
    struct PlatformImplementations {
        address organizationAddress;
        address accountAddress;
        address whitelistAddress;
    }

    /// @dev Struct containing addresses for all deployed contracts
    struct DeployedContracts {
        SafeInfrastructure safeInfra;
        SafeMultisigs safes;
        PlatformImplementations implementations;
        address organizationFactoryAddress;
        address whitelistProxyAddress;
    }

    /**
     * @notice Main entry point for the deployment script
     * @dev IMPORTANT: Run with --libraries flags pointing to CREATE2-deployed library addresses
     */
    function run() external {
        // Prompt for confirmation when running with --broadcast
        ScriptUtils.confirmBroadcastOrDryRun(vm, "DeployContracts");

        // Get the CREATE2 factory that will be used for deployments
        // The address of the factory is explicitly provided in the environment
        address factoryAddress = Create2Utils.getCreate2Factory(vm);

        // Validate that the script was run with --libraries flag (critical for determinism)
        _validateLibrariesLinkedOrRevert(factoryAddress);

        // Validate libraries are deployed at expected addresses (critical for determinism)
        _validateLibrariesDeployedOrRevert(factoryAddress);

        // Get the Guardian Safe configuration from environment
        // The Guardian Safe is a multisig wallet that will be used to deploy the contracts
        // The configuration must be explicitly provided via environment variables
        (address[] memory guardianOwnerAddresses, uint256 guardianThreshold) =
            SafeMultisigUtils.getGuardianSafeConfig(vm);

        // Get the Deployer Safe configuration from environment
        // The Deployer Safe is a multisig wallet that will be the owner of the ImplementationWhitelist contract
        // and OrganizationFactory contract.
        // The configuration must be explicitly provided via environment variables
        (address[] memory deployerOwnerAddresses, uint256 deployerThreshold) =
            SafeMultisigUtils.getDeployerSafeConfig(vm);

        // Validate Safe configurations and require explicit confirmation
        SafeMultisigUtils.validateSafeConfigsAndConfirm({
            vm: vm,
            guardianOwners: guardianOwnerAddresses,
            guardianThreshold: guardianThreshold,
            deployerOwners: deployerOwnerAddresses,
            deployerThreshold: deployerThreshold
        });

        // Prevent using the production Safe Factory deployer for this script
        Create2Utils.validateNotProductionSafeFactoryDeployerOrRevert();

        // Log the deployment header
        // This includes the factory type, chain ID, and deployer EOA address
        Create2Utils.logDeploymentHeader(factoryAddress, block.chainid);
        Logger.logKeyAddress("Deployer EOA", msg.sender);
        Logger.logEmptyLine();

        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy Safe Infrastructure
        // This includes the Safe Singleton, Safe Proxy Factory, Compatibility Fallback Handler,
        // MultiSend, MultiSendCallOnly, CreateCall, and SimulateTxAccessor contracts
        SafeInfrastructure memory safeInfra = _deploySafeInfrastructure(factoryAddress);

        // Deploy our two Safe Multisigs (Deployer and Guardian Safes)
        SafeMultisigs memory safes = _deploySafeMultisigs({
            safeInfra: safeInfra,
            guardianOwnerAddresses: guardianOwnerAddresses,
            guardianThreshold: guardianThreshold,
            deployerOwnerAddresses: deployerOwnerAddresses,
            deployerThreshold: deployerThreshold
        });

        // Deploy Implementation Contracts (OrganizationImpl, AccountImpl, WhitelistImpl)
        PlatformImplementations memory implementationContracts = _deployImplementationContracts(factoryAddress);

        // Deploy Factory Contracts (OrganizationFactory)
        address organizationFactoryAddress = _deployOrganizationFactory(factoryAddress, safes.deployerSafeAddress);

        // Deploy ImplementationWhitelistProxy (depends on implementationContracts, safes)
        address whitelistProxyAddress =
            _deployWhitelistProxy(factoryAddress, implementationContracts, safes.deployerSafeAddress);

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Build the complete deployed contracts struct for logging
        DeployedContracts memory contracts = DeployedContracts({
            safeInfra: safeInfra,
            safes: safes,
            implementations: implementationContracts,
            organizationFactoryAddress: organizationFactoryAddress,
            whitelistProxyAddress: whitelistProxyAddress
        });

        // Log deployment completion and print deployed addresses
        Logger.logDeploymentComplete();
        _logDeployedAddresses(contracts);
    }

    /// @dev Deploys all Safe infrastructure contracts via CREATE2 if not already deployed
    ///      Note that we deploy our own Safe infrastructure contracts, rather than the ones deployed by the Safe team,
    ///      because we need to ensure that the addresses of the deployed contracts are deterministic and consistent.
    /// @param factoryAddress Address of the CREATE2 factory to use for deployments
    /// @return safeInfra Struct containing all deployed Safe infrastructure addresses
    function _deploySafeInfrastructure(address factoryAddress) internal returns (SafeInfrastructure memory safeInfra) {
        Logger.logSection("Safe Infrastructure");

        // Deploy Safe Singleton (master copy) if not already deployed
        (safeInfra.singletonAddress,) = Create2Utils.deployIfNotExists(
            factoryAddress, DeploymentConfig.SAFE_SINGLETON_SALT, type(Safe).creationCode, "Safe Singleton"
        );

        // Deploy Safe Proxy Factory if not already deployed
        (safeInfra.proxyFactoryAddress,) = Create2Utils.deployIfNotExists(
            factoryAddress,
            DeploymentConfig.SAFE_PROXY_FACTORY_SALT,
            type(SafeProxyFactory).creationCode,
            "SafeProxyFactory"
        );

        // Deploy Compatibility Fallback Handler if not already deployed
        (safeInfra.fallbackHandlerAddress,) = Create2Utils.deployIfNotExists(
            factoryAddress,
            DeploymentConfig.SAFE_FALLBACK_HANDLER_SALT,
            type(CompatibilityFallbackHandler).creationCode,
            "CompatibilityFallbackHandler"
        );

        // Deploy MultiSend if not already deployed
        (safeInfra.multiSendAddress,) = Create2Utils.deployIfNotExists(
            factoryAddress, DeploymentConfig.SAFE_MULTISEND_SALT, type(MultiSend).creationCode, "MultiSend"
        );

        // Deploy MultiSendCallOnly if not already deployed
        (safeInfra.multiSendCallOnlyAddress,) = Create2Utils.deployIfNotExists(
            factoryAddress,
            DeploymentConfig.SAFE_MULTISEND_CALL_ONLY_SALT,
            type(MultiSendCallOnly).creationCode,
            "MultiSendCallOnly"
        );

        // Deploy CreateCall if not already deployed
        (safeInfra.createCallAddress,) = Create2Utils.deployIfNotExists(
            factoryAddress, DeploymentConfig.SAFE_CREATE_CALL_SALT, type(CreateCall).creationCode, "CreateCall"
        );

        // Deploy SimulateTxAccessor if not already deployed
        (safeInfra.simulateTxAccessorAddress,) = Create2Utils.deployIfNotExists(
            factoryAddress,
            DeploymentConfig.SAFE_SIMULATE_TX_ACCESSOR_SALT,
            type(SimulateTxAccessor).creationCode,
            "SimulateTxAccessor"
        );
    }

    /// @dev Deploys Guardian and Deployer Safe multisig wallets
    /// @param safeInfra Safe infrastructure addresses needed for Safe deployment
    /// @param guardianOwnerAddresses Array of owner addresses for the Guardian Safe
    /// @param guardianThreshold Required signatures threshold for Guardian Safe
    /// @param deployerOwnerAddresses Array of owner addresses for the Deployer Safe
    /// @param deployerThreshold Required signatures threshold for Deployer Safe
    /// @return safes Struct containing deployed Guardian and Deployer Safe addresses
    function _deploySafeMultisigs(
        SafeInfrastructure memory safeInfra,
        address[] memory guardianOwnerAddresses,
        uint256 guardianThreshold,
        address[] memory deployerOwnerAddresses,
        uint256 deployerThreshold
    ) internal returns (SafeMultisigs memory safes) {
        Logger.logSection("Safe Multisigs");

        // Deploy Guardian Safe
        safes.guardianSafeAddress = SafeMultisigUtils.deploySafeMultisig({
            safeInfra: safeInfra,
            ownerAddresses: guardianOwnerAddresses,
            threshold: guardianThreshold,
            salt: DeploymentConfig.GUARDIAN_SAFE_SALT,
            name: "Guardian Safe"
        });

        // Deploy Deployer Safe
        safes.deployerSafeAddress = SafeMultisigUtils.deploySafeMultisig({
            safeInfra: safeInfra,
            ownerAddresses: deployerOwnerAddresses,
            threshold: deployerThreshold,
            salt: DeploymentConfig.DEPLOYER_SAFE_SALT,
            name: "Deployer Safe"
        });
    }

    /// @dev Deploys all implementation contracts via CREATE2
    /// @param factoryAddress Address of the CREATE2 factory to use for deployments
    /// @return implementationContracts Struct containing all deployed implementation addresses
    function _deployImplementationContracts(address factoryAddress)
        internal
        returns (PlatformImplementations memory implementationContracts)
    {
        Logger.logSection("Implementation Contracts");

        // Deploy ImplementationWhitelistImplementation
        (implementationContracts.whitelistAddress,) = Create2Utils.deployIfNotExists(
            factoryAddress,
            DeploymentConfig.WHITELIST_IMPL_SALT,
            type(ImplementationWhitelistImplementation).creationCode,
            "ImplementationWhitelistImplementation"
        );

        // Deploy OrganizationImplementation
        // IMPORTANT: This script must be run with --libraries flag for deterministic deployment
        (implementationContracts.organizationAddress,) = Create2Utils.deployIfNotExists(
            factoryAddress,
            DeploymentConfig.ORG_IMPL_SALT,
            type(OrganizationImplementation).creationCode,
            "OrganizationImplementation"
        );

        // Deploy AccountImplementation
        (implementationContracts.accountAddress,) = Create2Utils.deployIfNotExists(
            factoryAddress,
            DeploymentConfig.ACCOUNT_IMPL_SALT,
            type(AccountImplementation).creationCode,
            "AccountImplementation"
        );
    }

    /// @dev Deploys the OrganizationFactory via CREATE2
    /// @param factoryAddress Address of the CREATE2 factory to use for deployments
    /// @param deployerSafeAddress Address of the Deployer Safe to authorize as factory deployer
    /// @return organizationFactoryAddress Address of the deployed OrganizationFactory
    function _deployOrganizationFactory(address factoryAddress, address deployerSafeAddress)
        internal
        returns (address organizationFactoryAddress)
    {
        Logger.logSection("Factory Contracts");

        // Deploy OrganizationFactory with deployerSafeAddress as the deployer
        bytes memory orgFactoryInitCode =
            abi.encodePacked(type(OrganizationFactory).creationCode, abi.encode(deployerSafeAddress));

        (organizationFactoryAddress,) = Create2Utils.deployIfNotExists(
            factoryAddress, DeploymentConfig.ORG_FACTORY_SALT, orgFactoryInitCode, "OrganizationFactory"
        );
    }

    /// @dev Deploys the ImplementationWhitelistProxy via CREATE2 with atomic initialization
    /// @param factoryAddress Address of the CREATE2 factory to use for deployments
    /// @param implementationContracts Implementation contract addresses
    /// @param deployerSafeAddress Address of the Deployer Safe (owner of the whitelist)
    /// @return whitelistProxyAddress Address of the deployed whitelist proxy
    function _deployWhitelistProxy(
        address factoryAddress,
        PlatformImplementations memory implementationContracts,
        address deployerSafeAddress
    ) internal returns (address whitelistProxyAddress) {
        Logger.logSection("ImplementationWhitelistProxy");

        // Construct arrays of implementation addresses to whitelist
        address[] memory organizationImplementationAddresses = new address[](1);
        organizationImplementationAddresses[0] = implementationContracts.organizationAddress;
        address[] memory accountImplementationAddresses = new address[](1);
        accountImplementationAddresses[0] = implementationContracts.accountAddress;

        // Encode the initialization data for the whitelist proxy
        bytes memory initData = abi.encodeCall(
            ImplementationWhitelistImplementation.initialize,
            (deployerSafeAddress, organizationImplementationAddresses, accountImplementationAddresses)
        );

        // Construct the proxy bytecode for the whitelist proxy
        bytes memory proxyBytecode = abi.encodePacked(
            type(ImplementationWhitelistProxy).creationCode,
            abi.encode(implementationContracts.whitelistAddress, initData)
        );

        // Deploy the whitelist proxy using CREATE2
        (whitelistProxyAddress,) = Create2Utils.deployIfNotExists(
            factoryAddress, DeploymentConfig.WHITELIST_PROXY_SALT, proxyBytecode, "ImplementationWhitelistProxy"
        );
    }

    /// @dev Verifies that platform libraries are deployed at their expected CREATE2 addresses
    /// @param factoryAddress Address of the CREATE2 factory used for address computation
    function _validateLibrariesDeployedOrRevert(address factoryAddress) internal view {
        Logger.logSection("Verify Library Addresses");

        // Compute expected library addresses using the shared helper
        // These addresses are dependent on which CREATE2 factory is used for deployment
        PlatformLibraries memory expectedLibAddresses =
            LinkedLibrariesUtils.computePlatformLibraryAddresses(factoryAddress);

        bool allDeployed = true;

        // Check if libraries are deployed at expected addresses
        if (!Create2Utils.isContractDeployedAtAddress(expectedLibAddresses.policyAddress)) {
            Logger.logFail("LibOrganizationPolicy NOT DEPLOYED at expected address");
            allDeployed = false;
        } else {
            Logger.logPass("LibOrganizationPolicy deployed at expected address");
        }

        if (!Create2Utils.isContractDeployedAtAddress(expectedLibAddresses.adminAddress)) {
            Logger.logFail("LibOrganizationAdmin NOT DEPLOYED at expected address");
            allDeployed = false;
        } else {
            Logger.logPass("LibOrganizationAdmin deployed at expected address");
        }

        if (!Create2Utils.isContractDeployedAtAddress(expectedLibAddresses.initializationAddress)) {
            Logger.logFail("LibOrganizationInitialization NOT DEPLOYED at expected address");
            allDeployed = false;
        } else {
            Logger.logPass("LibOrganizationInitialization deployed at expected address");
        }

        if (!Create2Utils.isContractDeployedAtAddress(expectedLibAddresses.accountSignatureAddress)) {
            Logger.logFail("LibOrganizationAccountSignature NOT DEPLOYED at expected address");
            allDeployed = false;
        } else {
            Logger.logPass("LibOrganizationAccountSignature deployed at expected address");
        }

        if (!allDeployed) {
            Logger.logEmptyLine();
            Logger.logWarn("WARNING: Some libraries are not deployed!");
            Logger.logIndented("Run DeployLibraries.s.sol first, then re-run this script with --libraries flags.");
            Logger.logEmptyLine();
            revert("Some libraries are not deployed!");
        }
    }

    /// @dev Validates that external libraries are properly linked via --libraries flag
    /// @param factoryAddress Address of the CREATE2 factory used for computing expected library addresses
    function _validateLibrariesLinkedOrRevert(address factoryAddress) internal pure {
        // Get the creation code of OrganizationImplementation
        // If libraries aren't linked via --libraries flag, the creation code will have
        // placeholder bytes instead of the actual library addresses
        bytes memory initCode = type(OrganizationImplementation).creationCode;

        // Compute expected library addresses using the shared helper
        // These addresses are dependent on which CREATE2 factory is used for deployment
        PlatformLibraries memory expectedLibAddresses =
            LinkedLibrariesUtils.computePlatformLibraryAddresses(factoryAddress);

        // Verify each library address appears in the creation code
        // If --libraries flag wasn't used, these addresses won't be embedded in the bytecode
        // forgefmt: disable-next-item
        require(
            LinkedLibrariesUtils.isAddressInInitCode(initCode, expectedLibAddresses.policyAddress),
            "LibOrgPolicy not linked. Use --libraries"
        );
        // forgefmt: disable-next-item
        require(
            LinkedLibrariesUtils.isAddressInInitCode(initCode, expectedLibAddresses.adminAddress),
            "LibOrgAdmin not linked. Use --libraries"
        );
        require(
            LinkedLibrariesUtils.isAddressInInitCode(initCode, expectedLibAddresses.initializationAddress),
            "LibOrgInit not linked. Use --libraries"
        );
        require(
            LinkedLibrariesUtils.isAddressInInitCode(initCode, expectedLibAddresses.accountSignatureAddress),
            "LibOrgAccSig not linked. Use --libraries"
        );
    }

    /// @dev Logs all deployed contract addresses in a formatted summary
    /// @param contracts Complete set of deployed contract addresses
    function _logDeployedAddresses(DeployedContracts memory contracts) internal pure {
        Logger.logBoxHeader("Deployed Contract Addresses");
        Logger.logIndented("Safe Infrastructure:");
        Logger.logKeyAddress("  Safe Singleton", contracts.safeInfra.singletonAddress);
        Logger.logKeyAddress("  SafeProxyFactory", contracts.safeInfra.proxyFactoryAddress);
        Logger.logKeyAddress("  FallbackHandler", contracts.safeInfra.fallbackHandlerAddress);
        Logger.logKeyAddress("  MultiSend", contracts.safeInfra.multiSendAddress);
        Logger.logKeyAddress("  MultiSendCallOnly", contracts.safeInfra.multiSendCallOnlyAddress);
        Logger.logKeyAddress("  CreateCall", contracts.safeInfra.createCallAddress);
        Logger.logKeyAddress("  SimulateTxAccessor", contracts.safeInfra.simulateTxAccessorAddress);
        Logger.logEmptyLine();
        Logger.logIndented("Safe Multisigs:");
        Logger.logKeyAddress("  Guardian Safe", contracts.safes.guardianSafeAddress);
        Logger.logKeyAddress("  Deployer Safe", contracts.safes.deployerSafeAddress);
        Logger.logEmptyLine();
        Logger.logIndented("Platform Implementations:");
        Logger.logKeyAddress("  OrganizationImplementation", contracts.implementations.organizationAddress);
        Logger.logKeyAddress("  AccountImplementation", contracts.implementations.accountAddress);
        Logger.logKeyAddress("  WhitelistImplementation", contracts.implementations.whitelistAddress);
        Logger.logEmptyLine();
        Logger.logIndented("Platform Factories:");
        Logger.logKeyAddress("  OrganizationFactory", contracts.organizationFactoryAddress);
        Logger.logEmptyLine();
        Logger.logIndented("Platform Proxies:");
        Logger.logKeyAddress("  WhitelistProxy", contracts.whitelistProxyAddress);
        Logger.logEmptyLine();
        Logger.logBoxFooter();
    }
}
