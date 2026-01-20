// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Safe} from "@safe/Safe.sol";
import {SimulateTxAccessor} from "@safe/accessors/SimulateTxAccessor.sol";
import {CompatibilityFallbackHandler} from "@safe/handler/CompatibilityFallbackHandler.sol";
import {ISafe} from "@safe/interfaces/ISafe.sol";
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
import {Create2Deployer} from "script/libraries/Create2Deployer.sol";
import {LinkedLibrariesUtils} from "script/libraries/LinkedLibrariesUtils.sol";
import {Logger} from "script/libraries/Logger.sol";
import {PlatformLibraries} from "script/libraries/Types.sol";

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
    /// @dev Struct containing addresses for the deployed Safe infrastructure contracts
    struct SafeInfrastructure {
        address singletonAddress;
        address proxyFactoryAddress;
        address fallbackHandlerAddress;
        address multiSendAddress;
        address multiSendCallOnlyAddress;
        address createCallAddress;
        address simulateTxAccessorAddress;
    }

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
        // Get the CREATE2 factory that will be used for deployments
        // The address of the factory is explicitly provided in the environment
        address factoryAddress = Create2Deployer.getCreate2Factory(vm);

        // Validate that the script was run with --libraries flag (critical for determinism)
        _validateLibrariesLinkedOrRevert(factoryAddress);

        // Validate libraries are deployed at expected addresses (critical for determinism)
        _validateLibrariesDeployedOrRevert(factoryAddress);

        // Get the Guardian Safe configuration from environment
        // The Guardian Safe is a multisig wallet that will be used to deploy the contracts
        // The configuration must be explicitly provided via environment variables
        (address[] memory guardianOwnerAddresses, uint256 guardianThreshold) = _getGuardianSafeConfig();

        // Get the Deployer Safe configuration from environment
        // The Deployer Safe is a multisig wallet that will be the owner of the ImplementationWhitelist contract
        // and OrganizationFactory contract.
        // The configuration must be explicitly provided via environment variables
        (address[] memory deployerOwnerAddresses, uint256 deployerThreshold) = _getDeployerSafeConfig();

        // Validate Safe configurations and require explicit confirmation
        _validateSafeConfigsAndConfirm(
            guardianOwnerAddresses, guardianThreshold, deployerOwnerAddresses, deployerThreshold
        );

        // Get Deployer private key/address from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        // Log the deployment header
        // This includes the factory type, chain ID, and deployer EOA address
        Create2Deployer.logDeploymentHeader(factoryAddress, block.chainid);
        Logger.logKeyAddress("Deployer EOA", deployerAddress);
        Logger.logEmptyLine();

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

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
        Create2Deployer.logDeploymentComplete();
        _logDeployedAddresses(contracts);
    }

    /// @dev Deploys all Safe infrastructure contracts via CREATE2 if not already deployed
    ///      Note that we deploy our own Safe infrastructure contracts, rather than the ones deployed by the Safe team,
    ///      because we need to ensure that the addresses of the deployed contracts are deterministic and consistent.
    /// @param factoryAddress Address of the CREATE2 factory to use for deployments
    /// @return safeInfra Struct containing all deployed Safe infrastructure addresses
    function _deploySafeInfrastructure(address factoryAddress) internal returns (SafeInfrastructure memory safeInfra) {
        Create2Deployer.logSection("Safe Infrastructure");

        // Deploy Safe Singleton (master copy) if not already deployed
        (safeInfra.singletonAddress,) = Create2Deployer.deployIfNotExists(
            factoryAddress, DeploymentConfig.SAFE_SINGLETON_SALT, type(Safe).creationCode, "Safe Singleton"
        );

        // Deploy Safe Proxy Factory if not already deployed
        (safeInfra.proxyFactoryAddress,) = Create2Deployer.deployIfNotExists(
            factoryAddress,
            DeploymentConfig.SAFE_PROXY_FACTORY_SALT,
            type(SafeProxyFactory).creationCode,
            "SafeProxyFactory"
        );

        // Deploy Compatibility Fallback Handler if not already deployed
        (safeInfra.fallbackHandlerAddress,) = Create2Deployer.deployIfNotExists(
            factoryAddress,
            DeploymentConfig.SAFE_FALLBACK_HANDLER_SALT,
            type(CompatibilityFallbackHandler).creationCode,
            "CompatibilityFallbackHandler"
        );

        // Deploy MultiSend if not already deployed
        (safeInfra.multiSendAddress,) = Create2Deployer.deployIfNotExists(
            factoryAddress, DeploymentConfig.SAFE_MULTISEND_SALT, type(MultiSend).creationCode, "MultiSend"
        );

        // Deploy MultiSendCallOnly if not already deployed
        (safeInfra.multiSendCallOnlyAddress,) = Create2Deployer.deployIfNotExists(
            factoryAddress,
            DeploymentConfig.SAFE_MULTISEND_CALL_ONLY_SALT,
            type(MultiSendCallOnly).creationCode,
            "MultiSendCallOnly"
        );

        // Deploy CreateCall if not already deployed
        (safeInfra.createCallAddress,) = Create2Deployer.deployIfNotExists(
            factoryAddress, DeploymentConfig.SAFE_CREATE_CALL_SALT, type(CreateCall).creationCode, "CreateCall"
        );

        // Deploy SimulateTxAccessor if not already deployed
        (safeInfra.simulateTxAccessorAddress,) = Create2Deployer.deployIfNotExists(
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
        Create2Deployer.logSection("Safe Multisigs");

        // Deploy Guardian Safe
        safes.guardianSafeAddress = _deploySafeMultisig({
            safeInfra: safeInfra,
            ownerAddresses: guardianOwnerAddresses,
            threshold: guardianThreshold,
            salt: DeploymentConfig.GUARDIAN_SAFE_SALT,
            name: "Guardian Safe"
        });

        // Deploy Deployer Safe
        safes.deployerSafeAddress = _deploySafeMultisig({
            safeInfra: safeInfra,
            ownerAddresses: deployerOwnerAddresses,
            threshold: deployerThreshold,
            salt: DeploymentConfig.DEPLOYER_SAFE_SALT,
            name: "Deployer Safe"
        });
    }

    /// @dev Deploys a Safe multisig wallet using SafeProxyFactory
    /// @param safeInfra Safe infrastructure addresses needed for Safe deployment
    /// @param ownerAddresses Array of owner addresses for the Safe
    /// @param threshold Required number of signatures for transactions
    /// @param salt Salt used for deterministic address computation
    /// @param name Human-readable name for logging purposes
    /// @return safeAddress Address of the deployed Safe proxy
    function _deploySafeMultisig(
        SafeInfrastructure memory safeInfra,
        address[] memory ownerAddresses,
        uint256 threshold,
        bytes32 salt,
        string memory name
    ) internal returns (address safeAddress) {
        // Encode the initializer for Safe.setup()
        bytes memory initializer = abi.encodeCall(
            ISafe.setup,
            (
                // owners
                ownerAddresses,
                // threshold
                threshold,
                // to - no delegate call
                address(0),
                // data - no delegate call data
                "",
                // fallbackHandler
                safeInfra.fallbackHandlerAddress,
                // paymentToken - ETH
                address(0),
                // payment - no payment
                0,
                // paymentReceiver
                payable(address(0))
            )
        );

        // Compute the salt nonce
        uint256 saltNonce = uint256(salt);

        // Compute expected address using SafeProxyFactory's CREATE2 formula
        safeAddress = _computeSafeProxyAddress(safeInfra, initializer, saltNonce);

        // Check if already deployed
        if (Create2Deployer.isContractDeployedAtAddress(safeAddress)) {
            Logger.logDeploymentSkipped(name, safeAddress);
            return safeAddress;
        }

        // Deploy the Safe
        address deployedAtAddress = address(
            SafeProxyFactory(safeInfra.proxyFactoryAddress)
                .createProxyWithNonce(safeInfra.singletonAddress, initializer, saltNonce)
        );
        Logger.logDeployed(name, deployedAtAddress);

        // Verify deployment matches expected address
        require(deployedAtAddress == safeAddress, "Safe deployed at unexpected address");
    }

    /// @dev Deploys all implementation contracts via CREATE2
    /// @param factoryAddress Address of the CREATE2 factory to use for deployments
    /// @return implementationContracts Struct containing all deployed implementation addresses
    function _deployImplementationContracts(address factoryAddress)
        internal
        returns (PlatformImplementations memory implementationContracts)
    {
        Create2Deployer.logSection("Implementation Contracts");

        // Deploy ImplementationWhitelistImplementation
        (implementationContracts.whitelistAddress,) = Create2Deployer.deployIfNotExists(
            factoryAddress,
            DeploymentConfig.WHITELIST_IMPL_SALT,
            type(ImplementationWhitelistImplementation).creationCode,
            "ImplementationWhitelistImplementation"
        );

        // Deploy OrganizationImplementation
        // IMPORTANT: This script must be run with --libraries flag for deterministic deployment
        (implementationContracts.organizationAddress,) = Create2Deployer.deployIfNotExists(
            factoryAddress,
            DeploymentConfig.ORG_IMPL_SALT,
            type(OrganizationImplementation).creationCode,
            "OrganizationImplementation"
        );

        // Deploy AccountImplementation
        (implementationContracts.accountAddress,) = Create2Deployer.deployIfNotExists(
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
        Create2Deployer.logSection("Factory Contracts");

        // Deploy OrganizationFactory with deployerSafeAddress as the deployer
        bytes memory orgFactoryInitCode =
            abi.encodePacked(type(OrganizationFactory).creationCode, abi.encode(deployerSafeAddress));

        (organizationFactoryAddress,) = Create2Deployer.deployIfNotExists(
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
        Create2Deployer.logSection("ImplementationWhitelistProxy");

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
        (whitelistProxyAddress,) = Create2Deployer.deployIfNotExists(
            factoryAddress, DeploymentConfig.WHITELIST_PROXY_SALT, proxyBytecode, "ImplementationWhitelistProxy"
        );
    }

    /// @dev Validates Safe configurations and prompts for user confirmation
    /// @param guardianOwners Guardian Safe owners from env
    /// @param guardianThreshold Guardian Safe threshold from env
    /// @param deployerOwners Deployer Safe owners from env
    /// @param deployerThreshold Deployer Safe threshold from env
    function _validateSafeConfigsAndConfirm(
        address[] memory guardianOwners,
        uint256 guardianThreshold,
        address[] memory deployerOwners,
        uint256 deployerThreshold
    ) internal {
        bool guardianIsProd = _isProductionGuardianConfig(guardianOwners, guardianThreshold);
        bool deployerIsProd = _isProductionDeployerConfig(deployerOwners, deployerThreshold);

        Logger.logWarn("Safe configuration confirmation required");
        if (guardianIsProd) {
            Logger.logIndented("Guardian Safe: PRODUCTION configuration");
        } else {
            Logger.logIndented("Guardian Safe: NON-PRODUCTION configuration");
        }

        if (deployerIsProd) {
            Logger.logIndented("Deployer Safe: PRODUCTION configuration");
        } else {
            Logger.logIndented("Deployer Safe: NON-PRODUCTION configuration");
        }
        Logger.logEmptyLine();

        string memory mode = guardianIsProd && deployerIsProd ? "PRODUCTION" : "NON-PRODUCTION";
        string memory prompt =
            string(abi.encodePacked("Type 'yes' to confirm you want to deploy with ", mode, " configuration: "));
        string memory response = vm.prompt(prompt);
        string memory trimmedResponse = vm.trim(response);
        if (!_isYesResponse(trimmedResponse)) {
            revert("Deployment aborted: confirmation not received");
        }
    }

    /// @dev Computes the deterministic address of a Safe proxy before deployment
    /// @param safeInfra Safe infrastructure addresses needed for address computation
    /// @param initializer Encoded Safe.setup() call data
    /// @param saltNonce Nonce used for salt computation
    /// @return The predicted Safe proxy address
    function _computeSafeProxyAddress(SafeInfrastructure memory safeInfra, bytes memory initializer, uint256 saltNonce)
        internal
        view
        returns (address)
    {
        // SafeProxyFactory computes salt as: keccak256(abi.encodePacked(keccak256(initializer), saltNonce))
        bytes32 salt = keccak256(abi.encodePacked(keccak256(initializer), saltNonce));

        // Get the init code hash from the factory (includes singleton address)
        bytes32 initCodeHash =
            SafeProxyFactory(safeInfra.proxyFactoryAddress).proxyCreationCodehash(safeInfra.singletonAddress);

        // Use OpenZeppelin's Create2 utility for address computation
        return Create2.computeAddress(salt, initCodeHash, safeInfra.proxyFactoryAddress);
    }

    /// @dev Verifies that platform libraries are deployed at their expected CREATE2 addresses
    /// @param factoryAddress Address of the CREATE2 factory used for address computation
    function _validateLibrariesDeployedOrRevert(address factoryAddress) internal view {
        Create2Deployer.logSection("Verify Library Addresses");

        // Compute expected library addresses using the shared helper
        // These addresses are dependent on which CREATE2 factory is used for deployment
        PlatformLibraries memory expectedLibAddresses =
            LinkedLibrariesUtils.computePlatformLibraryAddresses(factoryAddress);

        bool allDeployed = true;

        // Check if libraries are deployed at expected addresses
        if (!Create2Deployer.isContractDeployedAtAddress(expectedLibAddresses.policyAddress)) {
            Logger.logFail("LibOrganizationPolicy NOT DEPLOYED at expected address");
            allDeployed = false;
        } else {
            Logger.logPass("LibOrganizationPolicy deployed at expected address");
        }

        if (!Create2Deployer.isContractDeployedAtAddress(expectedLibAddresses.adminAddress)) {
            Logger.logFail("LibOrganizationAdmin NOT DEPLOYED at expected address");
            allDeployed = false;
        } else {
            Logger.logPass("LibOrganizationAdmin deployed at expected address");
        }

        if (!Create2Deployer.isContractDeployedAtAddress(expectedLibAddresses.initializationAddress)) {
            Logger.logFail("LibOrganizationInitialization NOT DEPLOYED at expected address");
            allDeployed = false;
        } else {
            Logger.logPass("LibOrganizationInitialization deployed at expected address");
        }

        if (!Create2Deployer.isContractDeployedAtAddress(expectedLibAddresses.accountSignatureAddress)) {
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

    /// @dev Retrieves Guardian Safe configuration from environment variables
    /// @return ownerAddresses Array of owner addresses for the Guardian Safe
    /// @return threshold Required number of signatures
    function _getGuardianSafeConfig() internal view returns (address[] memory ownerAddresses, uint256 threshold) {
        string memory ownersStr = vm.envString("GUARDIAN_SAFE_OWNERS");
        ownerAddresses = _parseAddressArray(ownersStr);
        threshold = vm.envUint("GUARDIAN_SAFE_THRESHOLD");
    }

    /// @dev Retrieves Deployer Safe configuration from environment variables
    /// @return ownerAddresses Array of owner addresses for the Deployer Safe
    /// @return threshold Required number of signatures
    function _getDeployerSafeConfig() internal view returns (address[] memory ownerAddresses, uint256 threshold) {
        string memory ownersStr = vm.envString("DEPLOYER_SAFE_OWNERS");
        ownerAddresses = _parseAddressArray(ownersStr);
        threshold = vm.envUint("DEPLOYER_SAFE_THRESHOLD");
    }

    /// @dev Parses a comma-separated string of addresses into an array
    /// @param input Comma-separated addresses (e.g., "0x123...,0x456...")
    /// @return parsedAddresses Array of parsed addresses
    function _parseAddressArray(string memory input) internal view returns (address[] memory parsedAddresses) {
        // Case: the input string is empty
        // Return empty array
        if (bytes(input).length == 0) {
            return new address[](0);
        }

        // Split the input string into parts using the comma as the delimiter
        string[] memory parts = vm.split(input, ",");

        // Create a new array to store the parsed addresses
        parsedAddresses = new address[](parts.length);

        // Iterate over each part and parse the address
        for (uint256 i = 0; i < parts.length; ++i) {
            // Parse the address from the part, trim any whitespace, and add it to the array
            // slither-disable-next-line calls-loop
            parsedAddresses[i] = vm.parseAddress(vm.trim(parts[i]));
        }

        return parsedAddresses;
    }

    /// @dev Checks if the provided Guardian Safe config matches production
    /// @param owners Guardian Safe owner addresses from environment
    /// @param threshold Guardian Safe threshold from environment
    /// @return True if owners and threshold match production configuration
    function _isProductionGuardianConfig(address[] memory owners, uint256 threshold) internal pure returns (bool) {
        if (threshold != DeploymentConfig.PROD_GUARDIAN_SAFE_THRESHOLD) {
            return false;
        }

        address[] memory prodOwners = DeploymentConfig.getProdGuardianSafeOwners();
        return _areSameOwners(owners, prodOwners);
    }

    /// @dev Checks if the provided Deployer Safe config matches production
    /// @param owners Deployer Safe owner addresses from environment
    /// @param threshold Deployer Safe threshold from environment
    /// @return True if owners and threshold match production configuration
    function _isProductionDeployerConfig(address[] memory owners, uint256 threshold) internal pure returns (bool) {
        if (threshold != DeploymentConfig.PROD_DEPLOYER_SAFE_THRESHOLD) {
            return false;
        }

        address[] memory prodOwners = DeploymentConfig.getProdDeployerSafeOwners();
        return _areSameOwners(owners, prodOwners);
    }

    /// @dev Compares two owner arrays for exact match (length and order)
    /// @param owners First array of owners
    /// @param expectedOwners Expected array of owners
    /// @return True if arrays match exactly
    function _areSameOwners(address[] memory owners, address[] memory expectedOwners) internal pure returns (bool) {
        if (owners.length != expectedOwners.length) {
            return false;
        }

        for (uint256 i = 0; i < owners.length; ++i) {
            if (owners[i] != expectedOwners[i]) {
                return false;
            }
        }

        return true;
    }

    /// @dev Checks if user confirmation input equals "yes"
    /// @param response User input response
    /// @return True if response equals "yes"
    function _isYesResponse(string memory response) internal pure returns (bool) {
        return keccak256(bytes(response)) == keccak256(bytes("yes"));
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
        Logger.logEmptyLine();
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
