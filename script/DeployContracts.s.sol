// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

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
import {ScriptUtils} from "script/libraries/ScriptUtils.sol";
import {PlatformLibraries, SafeInfrastructure} from "script/libraries/Types.sol";

/**
 * @title DeployContracts
 * @notice Deploys all platform contracts (implementations, factories, proxies)
 * @dev This script must be run AFTER:
 *      1. DeploySafe.s.sol (Safe 1.3.0 infrastructure) - requires FOUNDRY_PROFILE=safe
 *      2. DeployLibraries.s.sol (platform libraries)
 *
 *      This script expects Safe infrastructure and Safe multisigs to already be deployed.
 *      Use the --libraries flags pointing to the library addresses outputted by DeployLibraries.s.sol.
 *
 *      The CREATE2 factory address must be passed as an argument to the run function.
 *
 *      This script will revert if:
 *      - Libraries are not deployed at expected addresses
 *      - Safe infrastructure is not deployed at expected addresses
 *      - Guardian and Deployer Safes are not deployed
 *
 *      Expected addresses are hardcoded in DeploymentConfig based on which CREATE2 factory is used.
 *
 *      This script deploys the following contracts in the following order:
 *      1. Implementation Contracts (OrganizationImpl, AccountImpl, WhitelistImpl)
 *      2. Factory Contracts (OrganizationFactory)
 *      3. ImplementationWhitelistProxy
 *
 *      Usage:
 *        forge script script/DeployContracts.s.sol:DeployContracts \
 *          --sig "run(address)" <CREATE2_FACTORY_ADDRESS> \
 *          --rpc-url $RPC_URL \
 *          --broadcast \
 *          --libraries ... \
 *          -vvvv
 *
 *      SAFETY CHECKS:
 *      1. Verifies the provided CREATE2 factory address is not zero
 *      2. Verifies the provided CREATE2 factory address is deployed at the provided address
 *      3. Verifies that the deployer is not the production Den Factory deployer
 *      4. Validates that --libraries flag was used with correct addresses
 *      5. Validates that libraries are deployed at expected addresses
 *      6. Validates that Safe infrastructure is deployed at expected addresses
 *      7. Validates that Guardian and Deployer Safes are deployed
 *      8. Requires interactive confirmation when broadcasting
 *
 * @author Den Technologies Inc
 */
contract DeployContracts is Script {
    /// @dev Struct containing addresses for the deployed platform implementation contracts
    struct PlatformImplementations {
        address organizationAddress;
        address accountAddress;
        address whitelistAddress;
    }

    /// @dev Struct containing addresses for all deployed contracts
    struct DeployedContracts {
        PlatformImplementations implementations;
        address organizationFactoryAddress;
        address whitelistProxyAddress;
    }

    /**
     * @notice Main entry point for the deployment script
     * @dev IMPORTANT: Run with --libraries flags pointing to CREATE2-deployed library addresses
     *      IMPORTANT: Safe infrastructure must be deployed first using DeploySafe.s.sol
     * @param factoryAddress Address of the CREATE2 factory to use for deployments
     */
    function run(address factoryAddress) external {
        // Validate the provided CREATE2 factory address
        require(factoryAddress != address(0), "Factory address cannot be zero");
        require(
            Create2Utils.isContractDeployedAtAddress(factoryAddress), "CREATE2 factory not deployed at provided address"
        );

        // Warn and confirm when targeting production chains
        ScriptUtils.warnAndConfirmIfProductionChain(vm, "DeployContracts");

        // Prompt for confirmation when running with --broadcast
        ScriptUtils.confirmBroadcastOrDryRun(vm, "DeployContracts");

        // Validate that --libraries flag was used with correct addresses
        _validateLibrariesLinkedOrRevert(factoryAddress);

        // Validate libraries are deployed at expected addresses
        _validateLibrariesDeployedOrRevert(factoryAddress);

        // Validate Safe infrastructure is deployed at expected addresses
        _validateSafeInfrastructureDeployedOrRevert(factoryAddress);

        // Validate Guardian and Deployer Safes are deployed
        _validateSafeMultisigsDeployedOrRevert(factoryAddress);

        // Get the expected Deployer Safe address (needed for factory and whitelist deployment)
        address deployerSafeAddress = DeploymentConfig.getExpectedDeployerSafeAddress(factoryAddress);

        // Prevent using the production Den Factory deployer for this script
        Create2Utils.validateNotProductionDenFactoryDeployerOrRevert();

        // Log the deployment header
        // This includes the factory type, chain ID, and deployer EOA address
        Create2Utils.logDeploymentHeader(factoryAddress, ScriptUtils.getChainId());
        Logger.logKeyValue("Deployer EOA", msg.sender);
        Logger.logEmptyLine();

        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy Implementation Contracts (OrganizationImpl, AccountImpl, WhitelistImpl)
        PlatformImplementations memory implementationContracts = _deployImplementationContracts(factoryAddress);

        // Deploy Factory Contracts (OrganizationFactory)
        address organizationFactoryAddress = _deployOrganizationFactory(factoryAddress, deployerSafeAddress);

        // Deploy ImplementationWhitelistProxy (depends on implementationContracts, deployer safe)
        address whitelistProxyAddress =
            _deployWhitelistProxy(factoryAddress, implementationContracts, deployerSafeAddress);

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Build the complete deployed contracts struct for logging
        DeployedContracts memory contracts = DeployedContracts({
            implementations: implementationContracts,
            organizationFactoryAddress: organizationFactoryAddress,
            whitelistProxyAddress: whitelistProxyAddress
        });

        // Log deployment completion and print deployed addresses
        Logger.logDeploymentComplete();
        _logDeployedAddresses(contracts, factoryAddress);
    }

    /**
     * @notice Compute and print platform contract addresses without deploying
     * @dev Use this to preview addresses before deployment or for updating DeploymentConfig.sol.
     *      Does not require RPC connection.
     *      IMPORTANT: This function must be called with the correct --libraries flags to ensure
     *      the library addresses are linked at compile time. The bash script compute_all_addresses.sh
     *      handles this by first computing library addresses and passing them via --libraries.
     * @param factoryAddress Address of the CREATE2 factory to use for address computation
     * @param deployerSafeAddress Address of the Deployer Safe (computed by DeploySafe.s.sol)
     */
    function computeAddresses(address factoryAddress, address deployerSafeAddress) external pure {
        // Validate inputs
        require(factoryAddress != address(0), "Factory address cannot be zero");
        require(deployerSafeAddress != address(0), "Deployer Safe address cannot be zero");

        // Log header
        Logger.logBoxHeader("Computed Platform Contract Addresses");
        Logger.logKeyValue("CREATE2 Factory", factoryAddress);
        Logger.logKeyValue("Deployer Safe", deployerSafeAddress);
        Logger.logEmptyLine();

        // Compute implementation addresses
        Logger.logSection("Implementation Contracts");

        address whitelistImplAddress = Create2Utils.computeAddress(
            factoryAddress,
            DeploymentConfig.WHITELIST_IMPL_SALT,
            type(ImplementationWhitelistImplementation).creationCode
        );
        Logger.logKeyValue("ImplementationWhitelistImplementation", whitelistImplAddress);

        address orgImplAddress = Create2Utils.computeAddress(
            factoryAddress, DeploymentConfig.ORG_IMPL_SALT, type(OrganizationImplementation).creationCode
        );
        Logger.logKeyValue("OrganizationImplementation", orgImplAddress);

        address accountImplAddress = Create2Utils.computeAddress(
            factoryAddress, DeploymentConfig.ACCOUNT_IMPL_SALT, type(AccountImplementation).creationCode
        );
        Logger.logKeyValue("AccountImplementation", accountImplAddress);

        // Compute OrganizationFactory address (depends on deployerSafeAddress constructor arg)
        Logger.logSection("Factory Contracts");

        bytes memory orgFactoryInitCode =
            abi.encodePacked(type(OrganizationFactory).creationCode, abi.encode(deployerSafeAddress));
        address orgFactoryAddress =
            Create2Utils.computeAddress(factoryAddress, DeploymentConfig.ORG_FACTORY_SALT, orgFactoryInitCode);
        Logger.logKeyValue("OrganizationFactory", orgFactoryAddress);

        // Compute ImplementationWhitelistProxy address
        // (depends on whitelistImplAddress, orgImplAddress, accountImplAddress, deployerSafeAddress)
        Logger.logSection("Proxy Contracts");

        // Build the same init data that _deployWhitelistProxy uses
        address[] memory organizationImplementationAddresses = new address[](1);
        organizationImplementationAddresses[0] = orgImplAddress;
        address[] memory accountImplementationAddresses = new address[](1);
        accountImplementationAddresses[0] = accountImplAddress;

        bytes memory initData = abi.encodeCall(
            ImplementationWhitelistImplementation.initialize,
            (deployerSafeAddress, organizationImplementationAddresses, accountImplementationAddresses)
        );

        bytes memory proxyBytecode = abi.encodePacked(
            type(ImplementationWhitelistProxy).creationCode, abi.encode(whitelistImplAddress, initData)
        );

        address whitelistProxyAddress =
            Create2Utils.computeAddress(factoryAddress, DeploymentConfig.WHITELIST_PROXY_SALT, proxyBytecode);
        Logger.logKeyValue("ImplementationWhitelistProxy", whitelistProxyAddress);

        Logger.logEmptyLine();
        Logger.logBoxFooter();
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

    /// @dev Verifies that platform libraries are deployed at the expected hardcoded addresses
    /// @param factoryAddress Address of the CREATE2 factory used for deployment (determines expected addresses)
    function _validateLibrariesDeployedOrRevert(address factoryAddress) internal view {
        Logger.logSection("Verify Library Addresses");

        // Get expected library addresses from hardcoded config (based on which factory was used)
        PlatformLibraries memory expectedLibAddresses = DeploymentConfig.getExpectedLibraryAddresses(factoryAddress);

        bool allDeployed = true;

        // Check if libraries are deployed at expected addresses
        if (!Create2Utils.isContractDeployedAtAddress(expectedLibAddresses.policyAddress)) {
            Logger.logFail("LibOrganizationPolicy NOT DEPLOYED at expected address");
            Logger.logKeyValue("  Expected", expectedLibAddresses.policyAddress);
            allDeployed = false;
        } else {
            Logger.logPass("LibOrganizationPolicy deployed at expected address");
        }

        if (!Create2Utils.isContractDeployedAtAddress(expectedLibAddresses.adminAddress)) {
            Logger.logFail("LibOrganizationAdmin NOT DEPLOYED at expected address");
            Logger.logKeyValue("  Expected", expectedLibAddresses.adminAddress);
            allDeployed = false;
        } else {
            Logger.logPass("LibOrganizationAdmin deployed at expected address");
        }

        if (!Create2Utils.isContractDeployedAtAddress(expectedLibAddresses.initializationAddress)) {
            Logger.logFail("LibOrganizationInitialization NOT DEPLOYED at expected address");
            Logger.logKeyValue("  Expected", expectedLibAddresses.initializationAddress);
            allDeployed = false;
        } else {
            Logger.logPass("LibOrganizationInitialization deployed at expected address");
        }

        if (!Create2Utils.isContractDeployedAtAddress(expectedLibAddresses.accountSignatureAddress)) {
            Logger.logFail("LibOrganizationAccountSignature NOT DEPLOYED at expected address");
            Logger.logKeyValue("  Expected", expectedLibAddresses.accountSignatureAddress);
            allDeployed = false;
        } else {
            Logger.logPass("LibOrganizationAccountSignature deployed at expected address");
        }

        if (!allDeployed) {
            Logger.logEmptyLine();
            Logger.logWarn("WARNING: Some libraries are not deployed!");
            Logger.logIndented("Run DeployLibraries.s.sol first, then re-run this script with --libraries flags.");
            Logger.logEmptyLine();
            revert("Some libraries are not deployed at expected addresses");
        }
    }

    /// @dev Verifies that Safe infrastructure is deployed at the expected hardcoded addresses
    /// @param factoryAddress Address of the CREATE2 factory used for deployment (determines expected addresses)
    function _validateSafeInfrastructureDeployedOrRevert(address factoryAddress) internal view {
        Logger.logSection("Verify Safe 1.3.0 Infrastructure");

        // Get expected Safe infrastructure addresses from hardcoded config
        SafeInfrastructure memory expectedSafeInfra =
            DeploymentConfig.getExpectedSafeInfrastructureAddresses(factoryAddress);

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
            Logger.logIndented("Run DeploySafe.s.sol first (FOUNDRY_PROFILE=safe), then re-run this script.");
            Logger.logEmptyLine();
            revert("Safe infrastructure is not deployed at expected addresses");
        }
    }

    /// @dev Verifies that Guardian and Deployer Safes are deployed at the expected hardcoded addresses
    /// @param factoryAddress Address of the CREATE2 factory used for deployment (determines expected addresses)
    function _validateSafeMultisigsDeployedOrRevert(address factoryAddress) internal view {
        Logger.logSection("Verify Safe Multisigs");

        // Get expected Safe addresses from hardcoded config
        address expectedGuardianSafe = DeploymentConfig.getExpectedGuardianSafeAddress(factoryAddress);
        address expectedDeployerSafe = DeploymentConfig.getExpectedDeployerSafeAddress(factoryAddress);

        bool allDeployed = true;

        // Check if Guardian Safe is deployed
        if (!Create2Utils.isContractDeployedAtAddress(expectedGuardianSafe)) {
            Logger.logFail("Guardian Safe NOT DEPLOYED at expected address");
            Logger.logKeyValue("  Expected", expectedGuardianSafe);
            allDeployed = false;
        } else {
            Logger.logPass("Guardian Safe deployed at expected address");
        }

        // Check if Deployer Safe is deployed
        if (!Create2Utils.isContractDeployedAtAddress(expectedDeployerSafe)) {
            Logger.logFail("Deployer Safe NOT DEPLOYED at expected address");
            Logger.logKeyValue("  Expected", expectedDeployerSafe);
            allDeployed = false;
        } else {
            Logger.logPass("Deployer Safe deployed at expected address");
        }

        if (!allDeployed) {
            Logger.logEmptyLine();
            Logger.logWarn("WARNING: Safe multisigs are not deployed!");
            Logger.logIndented("Run DeploySafe.s.sol first (FOUNDRY_PROFILE=safe), then re-run this script.");
            Logger.logEmptyLine();
            revert("Safe multisigs are not deployed at expected addresses");
        }
    }

    /// @dev Validates that external libraries are properly linked via --libraries flag
    ///      Uses hardcoded expected addresses from DeploymentConfig to verify the correct addresses are embedded
    /// @param factoryAddress Address of the CREATE2 factory (determines which hardcoded addresses to check for)
    function _validateLibrariesLinkedOrRevert(address factoryAddress) internal pure {
        // Get the creation code of OrganizationImplementation
        // If libraries aren't linked via --libraries flag, the creation code will have
        // placeholder bytes instead of the actual library addresses
        bytes memory initCode = type(OrganizationImplementation).creationCode;

        // Get expected library addresses from hardcoded config (based on which factory was used)
        PlatformLibraries memory expectedLibAddresses = DeploymentConfig.getExpectedLibraryAddresses(factoryAddress);

        // Verify each expected library address appears in the creation code
        // If --libraries flag wasn't used (or used with wrong addresses), these won't be in the bytecode
        require(
            LinkedLibrariesUtils.isAddressInInitCode(initCode, expectedLibAddresses.policyAddress),
            "LibOrgPolicy not linked. Use --libraries"
        );
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
    /// @param factoryAddress The CREATE2 factory used for deployment (to look up Safe addresses)
    function _logDeployedAddresses(DeployedContracts memory contracts, address factoryAddress) internal pure {
        // Get Safe addresses from config for logging
        SafeInfrastructure memory safeInfra = DeploymentConfig.getExpectedSafeInfrastructureAddresses(factoryAddress);
        address guardianSafe = DeploymentConfig.getExpectedGuardianSafeAddress(factoryAddress);
        address deployerSafe = DeploymentConfig.getExpectedDeployerSafeAddress(factoryAddress);

        Logger.logBoxHeader("Deployed Contract Addresses");
        Logger.logIndented("Safe Infrastructure (pre-deployed):");
        Logger.logKeyValue("  GnosisSafe Singleton", safeInfra.singletonAddress);
        Logger.logKeyValue("  GnosisSafeProxyFactory", safeInfra.proxyFactoryAddress);
        Logger.logKeyValue("  FallbackHandler", safeInfra.fallbackHandlerAddress);
        Logger.logKeyValue("  MultiSend", safeInfra.multiSendAddress);
        Logger.logKeyValue("  MultiSendCallOnly", safeInfra.multiSendCallOnlyAddress);
        Logger.logKeyValue("  CreateCall", safeInfra.createCallAddress);
        Logger.logKeyValue("  SimulateTxAccessor", safeInfra.simulateTxAccessorAddress);
        Logger.logEmptyLine();
        Logger.logIndented("Safe Multisigs (pre-deployed):");
        Logger.logKeyValue("  Guardian Safe", guardianSafe);
        Logger.logKeyValue("  Deployer Safe", deployerSafe);
        Logger.logEmptyLine();
        Logger.logIndented("Platform Implementations:");
        Logger.logKeyValue("  OrganizationImplementation", contracts.implementations.organizationAddress);
        Logger.logKeyValue("  AccountImplementation", contracts.implementations.accountAddress);
        Logger.logKeyValue("  WhitelistImplementation", contracts.implementations.whitelistAddress);
        Logger.logEmptyLine();
        Logger.logIndented("Platform Factories:");
        Logger.logKeyValue("  OrganizationFactory", contracts.organizationFactoryAddress);
        Logger.logEmptyLine();
        Logger.logIndented("Platform Proxies:");
        Logger.logKeyValue("  WhitelistProxy", contracts.whitelistProxyAddress);
        Logger.logEmptyLine();
        Logger.logBoxFooter();
    }
}
