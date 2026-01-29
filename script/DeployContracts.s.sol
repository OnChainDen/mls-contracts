// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {AccountImplementation} from "account/AccountImplementation.sol";
import {
    ImplementationWhitelistImplementation
} from "implementation-whitelist/ImplementationWhitelistImplementation.sol";
import {ImplementationWhitelistProxy} from "implementation-whitelist/ImplementationWhitelistProxy.sol";
import {OrganizationFactory} from "organization/OrganizationFactory.sol";
import {OrganizationImplementation} from "organization/OrganizationImplementation.sol";
import {BaseDeployScript} from "script/base/BaseDeployScript.sol";
import {Create2Utils} from "script/libraries/Create2Utils.sol";
import {LinkedLibrariesUtils} from "script/libraries/LinkedLibrariesUtils.sol";
import {Logger} from "script/libraries/Logger.sol";
import {LinkedLibraryInfo, PlatformLibraries, SafeInfrastructure} from "script/libraries/Types.sol";

/**
 * @title DeployContracts
 * @notice Deploys all platform contracts (implementations, factories, proxies)
 * @dev This script must be run AFTER:
 *      1. DeploySafeInfrastructure.s.sol and DeploySafeMultisigs.s.sol (Safe 1.4.1) - requires FOUNDRY_PROFILE=safe
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
 *      - Guardian and Admin Safes are not deployed
 *
 *      Expected addresses are read from deployment.toml based on which CREATE2 factory is used.
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
 *      1. Verifies the provided CREATE2 factory is a known factory from deployment.toml
 *      2. Verifies the provided CREATE2 factory is deployed
 *      3. Verifies that the deployer is not the production Den Factory deployer
 *      4. Validates that --libraries flag was used with correct addresses
 *      5. Validates that libraries are deployed at expected addresses
 *      6. Validates that Safe infrastructure is deployed at expected addresses
 *      7. Validates that Guardian and Admin Safes are deployed
 *      8. Requires interactive confirmation when broadcasting
 *
 * @author Den Technologies Inc
 */
contract DeployContracts is BaseDeployScript {
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
     *      IMPORTANT: Safe infrastructure must be deployed first using DeploySafeInfrastructure.s.sol
     *      and DeploySafeMultisigs.s.sol
     * @param factoryAddress Address of the CREATE2 factory to use for deployments
     */
    function run(address factoryAddress) external {
        // Common deployment initialization (factory validation, confirmations, header logging)
        validateAndInitializeDeploymentOrRevert(factoryAddress, "DeployContracts");

        // Script-specific validations
        _validateLinkedLibrariesOrRevert();
        validateSafeInfrastructureDeployedOrRevert();
        _validateSafeMultisigsDeployedOrRevert();
        address guardianSafeAddress = getExpectedGuardianSafeAddress();
        address adminSafeAddress = getExpectedAdminSafeAddress();

        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy Implementation Contracts (OrganizationImpl, AccountImpl, WhitelistImpl)
        PlatformImplementations memory implementationContracts = _deployImplementationContracts();

        // Deploy Factory Contracts (OrganizationFactory)
        address organizationFactoryAddress = _deployOrganizationFactory(guardianSafeAddress);

        // Deploy ImplementationWhitelistProxy (depends on implementationContracts, admin safe)
        address whitelistProxyAddress = _deployWhitelistProxy(implementationContracts, adminSafeAddress);

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Build the complete deployed contracts struct for logging
        DeployedContracts memory contracts = DeployedContracts({
            implementations: implementationContracts,
            organizationFactoryAddress: organizationFactoryAddress,
            whitelistProxyAddress: whitelistProxyAddress
        });

        // Log deployed addresses
        _logDeployedAddresses(contracts);
    }

    /**
     * @notice Compute and print platform contract addresses without deploying
     * @dev Use this to preview addresses before deployment or for updating deployment.toml.
     *      Does not require RPC connection.
     *      IMPORTANT: This function must be called with the correct --libraries flags to ensure
     *      the library addresses are linked at compile time. The bash script compute_all_addresses.sh
     *      handles this by first computing library addresses and passing them via --libraries.
     * @param factoryAddress Address of the CREATE2 factory to use for address computation
     * @param guardianSafeAddress Address of the Guardian Safe (owner of OrganizationFactory)
     * @param adminSafeAddress Address of the Admin Safe (owner of ImplementationWhitelistProxy)
     */
    function computeAddresses(address factoryAddress, address guardianSafeAddress, address adminSafeAddress)
        external
        pure
    {
        // Validate inputs
        require(factoryAddress != address(0), "Factory address cannot be zero");
        require(guardianSafeAddress != address(0), "Guardian Safe address cannot be zero");
        require(adminSafeAddress != address(0), "Admin Safe address cannot be zero");

        // Log header
        Logger.logBoxHeader("Computed Platform Contract Addresses");
        Logger.logKeyValue("CREATE2 Factory", factoryAddress);
        Logger.logKeyValue("Guardian Safe", guardianSafeAddress);
        Logger.logKeyValue("Admin Safe", adminSafeAddress);
        Logger.logEmptyLine();

        // Compute implementation addresses
        Logger.logSection("Implementation Contracts");

        address whitelistImplAddress = Create2Utils.computeAddress(
            factoryAddress, WHITELIST_IMPL_SALT, type(ImplementationWhitelistImplementation).creationCode
        );
        Logger.logKeyValue("ImplementationWhitelistImplementation", whitelistImplAddress);

        address orgImplAddress =
            Create2Utils.computeAddress(factoryAddress, ORG_IMPL_SALT, type(OrganizationImplementation).creationCode);
        Logger.logKeyValue("OrganizationImplementation", orgImplAddress);

        address accountImplAddress =
            Create2Utils.computeAddress(factoryAddress, ACCOUNT_IMPL_SALT, type(AccountImplementation).creationCode);
        Logger.logKeyValue("AccountImplementation", accountImplAddress);

        // Compute OrganizationFactory address (depends on guardianSafeAddress constructor arg)
        Logger.logSection("Factory Contracts");

        bytes memory orgFactoryInitCode =
            abi.encodePacked(type(OrganizationFactory).creationCode, abi.encode(guardianSafeAddress));
        address orgFactoryAddress = Create2Utils.computeAddress(factoryAddress, ORG_FACTORY_SALT, orgFactoryInitCode);
        Logger.logKeyValue("OrganizationFactory", orgFactoryAddress);

        // Compute ImplementationWhitelistProxy address
        // (depends on whitelistImplAddress, orgImplAddress, accountImplAddress, adminSafeAddress)
        Logger.logSection("Proxy Contracts");

        // Build the same init data that _deployWhitelistProxy uses
        address[] memory organizationImplementationAddresses = new address[](1);
        organizationImplementationAddresses[0] = orgImplAddress;
        address[] memory accountImplementationAddresses = new address[](1);
        accountImplementationAddresses[0] = accountImplAddress;

        bytes memory initData = abi.encodeCall(
            ImplementationWhitelistImplementation.initialize,
            (adminSafeAddress, organizationImplementationAddresses, accountImplementationAddresses)
        );

        bytes memory proxyBytecode = abi.encodePacked(
            type(ImplementationWhitelistProxy).creationCode, abi.encode(whitelistImplAddress, initData)
        );

        address whitelistProxyAddress = Create2Utils.computeAddress(factoryAddress, WHITELIST_PROXY_SALT, proxyBytecode);
        Logger.logKeyValue("ImplementationWhitelistProxy", whitelistProxyAddress);
        Logger.logBoxFooter();
    }

    /// @dev Deploys all implementation contracts via CREATE2
    /// @return implementationContracts Struct containing all deployed implementation addresses
    function _deployImplementationContracts()
        internal
        returns (PlatformImplementations memory implementationContracts)
    {
        Logger.logSection("Implementation Contracts");

        // Deploy ImplementationWhitelistImplementation
        (implementationContracts.whitelistAddress,) = Create2Utils.deployIfNotExists(
            _factoryAddress,
            WHITELIST_IMPL_SALT,
            type(ImplementationWhitelistImplementation).creationCode,
            "ImplementationWhitelistImplementation"
        );

        // Deploy OrganizationImplementation
        // IMPORTANT: This script must be run with --libraries flag for deterministic deployment
        (implementationContracts.organizationAddress,) = Create2Utils.deployIfNotExists(
            _factoryAddress, ORG_IMPL_SALT, type(OrganizationImplementation).creationCode, "OrganizationImplementation"
        );

        // Deploy AccountImplementation
        (implementationContracts.accountAddress,) = Create2Utils.deployIfNotExists(
            _factoryAddress, ACCOUNT_IMPL_SALT, type(AccountImplementation).creationCode, "AccountImplementation"
        );
    }

    /// @dev Deploys the OrganizationFactory via CREATE2
    /// @param guardianSafeAddress Address of the Guardian Safe to authorize as factory deployer
    /// @return organizationFactoryAddress Address of the deployed OrganizationFactory
    function _deployOrganizationFactory(address guardianSafeAddress)
        internal
        returns (address organizationFactoryAddress)
    {
        Logger.logSection("Factory Contracts");

        // Deploy OrganizationFactory with guardianSafeAddress as the deployer
        bytes memory orgFactoryInitCode =
            abi.encodePacked(type(OrganizationFactory).creationCode, abi.encode(guardianSafeAddress));

        (organizationFactoryAddress,) = Create2Utils.deployIfNotExists(
            _factoryAddress, ORG_FACTORY_SALT, orgFactoryInitCode, "OrganizationFactory"
        );
    }

    /// @dev Deploys the ImplementationWhitelistProxy via CREATE2 with atomic initialization
    /// @param implementationContracts Implementation contract addresses
    /// @param adminSafeAddress Address of the Admin Safe (owner of the whitelist)
    /// @return whitelistProxyAddress Address of the deployed whitelist proxy
    function _deployWhitelistProxy(PlatformImplementations memory implementationContracts, address adminSafeAddress)
        internal
        returns (address whitelistProxyAddress)
    {
        Logger.logSection("ImplementationWhitelistProxy");

        // Construct arrays of implementation addresses to whitelist
        address[] memory organizationImplementationAddresses = new address[](1);
        organizationImplementationAddresses[0] = implementationContracts.organizationAddress;
        address[] memory accountImplementationAddresses = new address[](1);
        accountImplementationAddresses[0] = implementationContracts.accountAddress;

        // Encode the initialization data for the whitelist proxy
        bytes memory initData = abi.encodeCall(
            ImplementationWhitelistImplementation.initialize,
            (adminSafeAddress, organizationImplementationAddresses, accountImplementationAddresses)
        );

        // Construct the proxy bytecode for the whitelist proxy
        bytes memory proxyBytecode = abi.encodePacked(
            type(ImplementationWhitelistProxy).creationCode,
            abi.encode(implementationContracts.whitelistAddress, initData)
        );

        // Deploy the whitelist proxy using CREATE2
        (whitelistProxyAddress,) = Create2Utils.deployIfNotExists(
            _factoryAddress, WHITELIST_PROXY_SALT, proxyBytecode, "ImplementationWhitelistProxy"
        );
    }

    /// @dev Verifies that Guardian and Admin Safes are deployed at the expected addresses from deployment.toml
    function _validateSafeMultisigsDeployedOrRevert() internal {
        Logger.logSection("Verify Safe Multisigs");

        // Get expected Safe addresses from deployment.toml
        address expectedGuardianSafe = getExpectedGuardianSafeAddress();
        address expectedAdminSafe = getExpectedAdminSafeAddress();

        bool allDeployed = true;

        // Check if Guardian Safe is deployed
        if (!Create2Utils.isContractDeployedAtAddress(expectedGuardianSafe)) {
            Logger.logFail("Guardian Safe NOT DEPLOYED at expected address");
            Logger.logKeyValue("  Expected", expectedGuardianSafe);
            allDeployed = false;
        } else {
            Logger.logPass("Guardian Safe deployed at expected address");
        }

        // Check if Admin Safe is deployed
        if (!Create2Utils.isContractDeployedAtAddress(expectedAdminSafe)) {
            Logger.logFail("Admin Safe NOT DEPLOYED at expected address");
            Logger.logKeyValue("  Expected", expectedAdminSafe);
            allDeployed = false;
        } else {
            Logger.logPass("Admin Safe deployed at expected address");
        }

        if (!allDeployed) {
            Logger.logEmptyLine();
            Logger.logWarn("WARNING: Safe multisigs are not deployed!");
            Logger.logIndented("Run DeploySafeMultisigs.s.sol first (FOUNDRY_PROFILE=safe), then re-run this script.");
            Logger.logEmptyLine();
            revert("Safe multisigs are not deployed at expected addresses");
        }
    }

    /// @dev Validates that external libraries are properly linked via --libraries flag AND deployed
    ///      Uses expected addresses from deployment.toml to verify the correct addresses are embedded
    function _validateLinkedLibrariesOrRevert() internal {
        Logger.logSection("Verify Libraries Linked and Deployed");

        // Get expected library addresses from deployment.toml (based on which factory was used)
        PlatformLibraries memory expected = getExpectedLibraryAddresses();

        // Get the creation code of OrganizationImplementation
        // If libraries aren't linked via --libraries flag, the creation code will have
        // placeholder bytes instead of the actual library addresses
        bytes memory initCode = type(OrganizationImplementation).creationCode;

        // Build array of libraries to validate
        LinkedLibraryInfo[] memory libs = new LinkedLibraryInfo[](4);
        libs[0] = LinkedLibraryInfo(expected.policyAddress, "LibOrganizationPolicy");
        libs[1] = LinkedLibraryInfo(expected.adminAddress, "LibOrganizationAdmin");
        libs[2] = LinkedLibraryInfo(expected.initializationAddress, "LibOrganizationInitialization");
        libs[3] = LinkedLibraryInfo(expected.accountSignatureAddress, "LibOrganizationAccountSignature");

        // Validate all libraries are linked in bytecode and deployed
        LinkedLibrariesUtils.validateLinkedLibrariesOrRevert(initCode, libs);
    }

    /// @dev Logs all deployed contract addresses in a formatted summary
    /// @param contracts Complete set of deployed contract addresses
    function _logDeployedAddresses(DeployedContracts memory contracts) internal {
        // Get Safe addresses from deployment.toml for logging
        SafeInfrastructure memory safeInfra = getExpectedSafeInfrastructureAddresses();
        address guardianSafe = getExpectedGuardianSafeAddress();
        address adminSafe = getExpectedAdminSafeAddress();

        Logger.logBoxHeader(unicode"✅ Deployed Contract Addresses");
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
        Logger.logKeyValue("  Admin Safe", adminSafe);
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
        Logger.logBoxFooter();
    }
}
