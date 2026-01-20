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
import {Script, console} from "forge-std/Script.sol";

import {AccountImplementation} from "account/AccountImplementation.sol";
import {ImplementationWhitelistFactory} from "implementation-whitelist/ImplementationWhitelistFactory.sol";
import {
    ImplementationWhitelistImplementation
} from "implementation-whitelist/ImplementationWhitelistImplementation.sol";
import {OrganizationFactory} from "organization/OrganizationFactory.sol";
import {OrganizationImplementation} from "organization/OrganizationImplementation.sol";
import {LibOrganizationAccountSignature} from "organization/libraries/LibOrganizationAccountSignature.sol";
import {LibOrganizationAdmin} from "organization/libraries/LibOrganizationAdmin.sol";
import {LibOrganizationInitialization} from "organization/libraries/LibOrganizationInitialization.sol";
import {LibOrganizationPolicy} from "organization/libraries/LibOrganizationPolicy.sol";
import {DeploymentConfig} from "script/config/DeploymentConfig.sol";
import {Create2Deployer} from "script/libraries/Create2Deployer.sol";
import {ContractType} from "types/CommonTypes.sol";

/**
 * @title DeployContracts
 * @notice Deploys all platform contracts (Safe infrastructure, implementations, factories, proxies)
 * @dev This script must be run AFTER DeployLibraries.s.sol with the --libraries flags.
 *
 *      IMPORTANT: For deterministic deployment, run with --libraries flags pointing to
 *      the library addresses output by DeployLibraries.s.sol.
 *
 *      Deployment Order:
 *      1. Safe Infrastructure (Safe singleton, proxy factory, handlers, libraries)
 *      2. Safe Multisigs (Guardian Safe, Deployer Safe)
 *      3. Verify Platform Libraries (ensure they're at expected addresses)
 *      4. Implementation Contracts (OrganizationImpl, AccountImpl, WhitelistImpl)
 *      5. Factory Contracts (OrganizationFactory, WhitelistFactory)
 *      6. ImplementationWhitelistProxy (via factory)
 *      7. Whitelist initial implementations
 *
 * @author Den Technologies Inc
 */
contract DeployContracts is Script {
    /// @dev Grouped addresses for Safe infrastructure contracts
    struct SafeInfrastructure {
        address singleton;
        address proxyFactory;
        address fallbackHandler;
        address multiSend;
        address multiSendCallOnly;
        address createCall;
        address simulateTxAccessor;
    }

    /// @dev Grouped addresses for Safe multisig wallets
    struct SafeMultisigs {
        address guardianSafe;
        address deployerSafe;
    }

    /// @dev Grouped addresses for platform implementation contracts
    struct PlatformImplementations {
        address organization;
        address account;
        address whitelist;
    }

    /// @dev Grouped addresses for platform factory contracts
    struct PlatformFactories {
        address organization;
        address whitelist;
    }

    /// @dev Complete set of all deployed contract addresses
    struct DeployedContracts {
        SafeInfrastructure safeInfra;
        SafeMultisigs safes;
        PlatformImplementations implementations;
        PlatformFactories factories;
        address whitelistProxy;
    }

    /// @dev Custom error for when a Safe is deployed at an unexpected address
    error SafeDeployedAtUnexpectedAddress(address expected, address actual);

    /**
     * @notice Main entry point for the deployment script
     * @dev IMPORTANT: Run with --libraries flags pointing to CREATE2-deployed library addresses
     */
    function run() external {
        // Get the CREATE2 factory that will be used for deployments
        // The address of the factory is either explicitly provided in the environment, or auto-detected
        // If auto-detected, the factory is either Arachnid or Safe Singleton Factory
        address factoryAddress = Create2Deployer.getCreate2Factory(vm);

        // Validate libraries are deployed at expected addresses (critical for determinism)
        _validateLibraryAddressesDeployedOrRevert(factoryAddress);

        // Get the Guardian Safe configuration from environment
        // The Guardian Safe is a multisig wallet that will be used to deploy the contracts
        // The configuration is either explicitly provided in the environment, or defaults to the deployer as single
        // owner
        (address[] memory guardianOwners, uint256 guardianThreshold) = _getGuardianSafeConfig();

        // Get the Deployer Safe configuration from environment
        // The Deployer Safe is a multisig wallet that will be the owner of the ImplementationWhitelistFactory.sol
        // and OrganizationFactory.sol contracts.
        // The configuration is either explicitly provided in the environment, or defaults to the deployer as single
        // owner
        (address[] memory deployerOwners, uint256 deployerThreshold) = _getDeployerSafeConfig();

        // Get Deployer private key/address from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        // Log the deployment header
        // This includes the factory type, chain ID, and deployer EOA address
        Create2Deployer.logDeploymentHeader(factoryAddress, block.chainid);
        console.log("  Deployer EOA: %s", deployerAddress);
        console.log("");

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy Safe Infrastructure
        // This includes the Safe Singleton, Safe Proxy Factory, Compatibility Fallback Handler,
        // MultiSend, MultiSendCallOnly, CreateCall, and SimulateTxAccessor contracts
        SafeInfrastructure memory safeInfra = _deploySafeInfrastructure(factoryAddress);

        // Deploy our two Safe Multisigs (Deployer and Guardian Safes)
        SafeMultisigs memory safes = _deploySafeMultisigs({
            safeInfra: safeInfra,
            guardianOwners: guardianOwners,
            guardianThreshold: guardianThreshold,
            deployerOwners: deployerOwners,
            deployerThreshold: deployerThreshold
        });

        // Deploy Implementation Contracts (OrganizationImpl, AccountImpl, WhitelistImpl)
        PlatformImplementations memory impls = _deployImplementationContracts(factoryAddress);

        // Deploy Factory Contracts (OrganizationFactory, WhitelistFactory)
        PlatformFactories memory factories = _deployFactoryContracts(factoryAddress, safes.deployerSafe);

        // Deploy ImplementationWhitelistProxy via factory (depends on factories, impls, safes)
        address whitelistProxy = _deployWhitelistProxy(factories, impls, safes.deployerSafe);

        // Whitelist implementations (depends on whitelistProxy, impls)
        _whitelistImplementations(whitelistProxy, impls);

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Build the complete deployed contracts struct for logging
        DeployedContracts memory contracts = DeployedContracts({
            safeInfra: safeInfra,
            safes: safes,
            implementations: impls,
            factories: factories,
            whitelistProxy: whitelistProxy
        });

        // Log deployment completion and print deployed addresses
        Create2Deployer.logDeploymentComplete();
        _logDeployedAddresses(contracts);
    }

    /// @dev Deploys all Safe infrastructure contracts via CREATE2
    /// @param factory Address of the CREATE2 factory to use for deployments
    /// @return safeInfra Struct containing all deployed Safe infrastructure addresses
    function _deploySafeInfrastructure(address factory) internal returns (SafeInfrastructure memory safeInfra) {
        Create2Deployer.logSection("Safe Infrastructure");

        // Deploy Safe Singleton (master copy)
        (safeInfra.singleton,) = Create2Deployer.deployIfNotExists(
            factory, DeploymentConfig.SAFE_SINGLETON_SALT, type(Safe).creationCode, "Safe Singleton"
        );

        // Deploy Safe Proxy Factory
        (safeInfra.proxyFactory,) = Create2Deployer.deployIfNotExists(
            factory, DeploymentConfig.SAFE_PROXY_FACTORY_SALT, type(SafeProxyFactory).creationCode, "SafeProxyFactory"
        );

        // Deploy Compatibility Fallback Handler
        (safeInfra.fallbackHandler,) = Create2Deployer.deployIfNotExists(
            factory,
            DeploymentConfig.SAFE_FALLBACK_HANDLER_SALT,
            type(CompatibilityFallbackHandler).creationCode,
            "CompatibilityFallbackHandler"
        );

        // Deploy MultiSend
        (safeInfra.multiSend,) = Create2Deployer.deployIfNotExists(
            factory, DeploymentConfig.SAFE_MULTISEND_SALT, type(MultiSend).creationCode, "MultiSend"
        );

        // Deploy MultiSendCallOnly
        (safeInfra.multiSendCallOnly,) = Create2Deployer.deployIfNotExists(
            factory,
            DeploymentConfig.SAFE_MULTISEND_CALL_ONLY_SALT,
            type(MultiSendCallOnly).creationCode,
            "MultiSendCallOnly"
        );

        // Deploy CreateCall
        (safeInfra.createCall,) = Create2Deployer.deployIfNotExists(
            factory, DeploymentConfig.SAFE_CREATE_CALL_SALT, type(CreateCall).creationCode, "CreateCall"
        );

        // Deploy SimulateTxAccessor
        (safeInfra.simulateTxAccessor,) = Create2Deployer.deployIfNotExists(
            factory,
            DeploymentConfig.SAFE_SIMULATE_TX_ACCESSOR_SALT,
            type(SimulateTxAccessor).creationCode,
            "SimulateTxAccessor"
        );
    }

    /// @dev Deploys Guardian and Deployer Safe multisig wallets
    /// @param safeInfra Safe infrastructure addresses needed for Safe deployment
    /// @param guardianOwners Array of owner addresses for the Guardian Safe
    /// @param guardianThreshold Required signatures threshold for Guardian Safe
    /// @param deployerOwners Array of owner addresses for the Deployer Safe
    /// @param deployerThreshold Required signatures threshold for Deployer Safe
    /// @return safes Struct containing deployed Guardian and Deployer Safe addresses
    function _deploySafeMultisigs(
        SafeInfrastructure memory safeInfra,
        address[] memory guardianOwners,
        uint256 guardianThreshold,
        address[] memory deployerOwners,
        uint256 deployerThreshold
    ) internal returns (SafeMultisigs memory safes) {
        Create2Deployer.logSection("Safe Multisigs");

        // Deploy Guardian Safe
        safes.guardianSafe = _deploySafeMultisig({
            safeInfra: safeInfra,
            owners: guardianOwners,
            threshold: guardianThreshold,
            salt: DeploymentConfig.GUARDIAN_SAFE_SALT,
            name: "Guardian Safe"
        });

        // Deploy Deployer Safe
        safes.deployerSafe = _deploySafeMultisig({
            safeInfra: safeInfra,
            owners: deployerOwners,
            threshold: deployerThreshold,
            salt: DeploymentConfig.DEPLOYER_SAFE_SALT,
            name: "Deployer Safe"
        });
    }

    /// @dev Deploys a Safe multisig wallet using SafeProxyFactory
    /// @param safeInfra Safe infrastructure addresses needed for Safe deployment
    /// @param owners Array of owner addresses for the Safe
    /// @param threshold Required number of signatures for transactions
    /// @param salt Salt used for deterministic address computation
    /// @param name Human-readable name for logging purposes
    /// @return safe Address of the deployed Safe proxy
    function _deploySafeMultisig(
        SafeInfrastructure memory safeInfra,
        address[] memory owners,
        uint256 threshold,
        bytes32 salt,
        string memory name
    ) internal returns (address safe) {
        // Encode the initializer for Safe.setup()
        bytes memory initializer = abi.encodeCall(
            ISafe.setup,
            (
                owners,
                threshold,
                address(0), // to - no delegate call
                "", // data - no delegate call data
                safeInfra.fallbackHandler,
                address(0), // paymentToken - ETH
                0, // payment - no payment
                payable(address(0)) // paymentReceiver
            )
        );

        uint256 saltNonce = uint256(salt);

        // Compute expected address using SafeProxyFactory's CREATE2 formula
        safe = _computeSafeProxyAddress(safeInfra, initializer, saltNonce);

        // Check if already deployed
        if (Create2Deployer.isContractDeployedAtAddress(safe)) {
            console.log(unicode"  ⏭️  SKIPPED: %s (already deployed at %s)", name, safe);
            return safe;
        }

        // Deploy the Safe
        address deployedAtAddress = address(
            SafeProxyFactory(safeInfra.proxyFactory).createProxyWithNonce(safeInfra.singleton, initializer, saltNonce)
        );
        console.log(unicode"  ✅ DEPLOYED: %s at %s", name, deployedAtAddress);

        // Verify deployment matches expected address
        if (deployedAtAddress != safe) {
            revert SafeDeployedAtUnexpectedAddress(safe, deployedAtAddress);
        }
    }

    /// @dev Deploys all implementation contracts via CREATE2
    /// @param factory Address of the CREATE2 factory to use for deployments
    /// @return impls Struct containing all deployed implementation addresses
    function _deployImplementationContracts(address factory) internal returns (PlatformImplementations memory impls) {
        Create2Deployer.logSection("Implementation Contracts");

        // Deploy ImplementationWhitelistImplementation
        (impls.whitelist,) = Create2Deployer.deployIfNotExists(
            factory,
            DeploymentConfig.WHITELIST_IMPL_SALT,
            type(ImplementationWhitelistImplementation).creationCode,
            "ImplementationWhitelistImplementation"
        );

        // Deploy OrganizationImplementation
        // IMPORTANT: This script must be run with --libraries flag for deterministic deployment
        (impls.organization,) = Create2Deployer.deployIfNotExists(
            factory,
            DeploymentConfig.ORG_IMPL_SALT,
            type(OrganizationImplementation).creationCode,
            "OrganizationImplementation"
        );

        // Deploy AccountImplementation
        (impls.account,) = Create2Deployer.deployIfNotExists(
            factory,
            DeploymentConfig.ACCOUNT_IMPL_SALT,
            type(AccountImplementation).creationCode,
            "AccountImplementation"
        );
    }

    /// @dev Deploys factory contracts via CREATE2
    /// @param factory Address of the CREATE2 factory to use for deployments
    /// @param deployerSafe Address of the Deployer Safe to authorize as factory deployer
    /// @return factories Struct containing deployed factory addresses
    function _deployFactoryContracts(address factory, address deployerSafe)
        internal
        returns (PlatformFactories memory factories)
    {
        Create2Deployer.logSection("Factory Contracts");

        // Deploy ImplementationWhitelistFactory with deployerSafe as the deployer
        bytes memory whitelistFactoryInitCode =
            abi.encodePacked(type(ImplementationWhitelistFactory).creationCode, abi.encode(deployerSafe));

        (factories.whitelist,) = Create2Deployer.deployIfNotExists(
            factory, DeploymentConfig.WHITELIST_FACTORY_SALT, whitelistFactoryInitCode, "WhitelistFactory"
        );

        // Deploy OrganizationFactory with deployerSafe as the deployer
        bytes memory orgFactoryInitCode =
            abi.encodePacked(type(OrganizationFactory).creationCode, abi.encode(deployerSafe));

        (factories.organization,) = Create2Deployer.deployIfNotExists(
            factory, DeploymentConfig.ORG_FACTORY_SALT, orgFactoryInitCode, "OrganizationFactory"
        );
    }

    /// @dev Deploys the ImplementationWhitelistProxy via ImplementationWhitelistFactory
    /// @param factories Factory contract addresses
    /// @param impls Implementation contract addresses
    /// @param deployerSafe Address of the Deployer Safe (owner of the whitelist)
    /// @return whitelistProxy Address of the deployed whitelist proxy
    function _deployWhitelistProxy(
        PlatformFactories memory factories,
        PlatformImplementations memory impls,
        address deployerSafe
    ) internal returns (address whitelistProxy) {
        Create2Deployer.logSection("ImplementationWhitelistProxy");

        // Compute expected address
        address expectedProxy = ImplementationWhitelistFactory(factories.whitelist)
            .computeImplementationWhitelistAddress(DeploymentConfig.WHITELIST_PROXY_SALT, impls.whitelist);

        // Check if already deployed
        if (Create2Deployer.isContractDeployedAtAddress(expectedProxy)) {
            console.log(unicode"  ⏭️  SKIPPED: ImplementationWhitelistProxy (already at %s)", expectedProxy);
            return expectedProxy;
        }

        // Note: This call must come from the deployerSafe
        console.log("  Note: WhitelistProxy deployment requires deployerSafe to call the factory");
        console.log("  For initial deployment, configure ImplementationWhitelistFactory with EOA deployer");
        console.log("  Or execute this step via the Deployer Safe multisig");

        // If deployer matches factory's DEPLOYER_ADDRESS, deploy directly
        try ImplementationWhitelistFactory(factories.whitelist)
            .deployImplementationWhitelist(
                DeploymentConfig.WHITELIST_PROXY_SALT,
                impls.whitelist,
                deployerSafe // Owner of the whitelist
            ) returns (
            address deployedAtAddress
        ) {
            console.log(unicode"  ✅ DEPLOYED: ImplementationWhitelistProxy at %s", deployedAtAddress);
            return deployedAtAddress;
        } catch {
            console.log(unicode"  ⚠️  SKIPPED: Deployment requires authorization from deployerSafe");
            return expectedProxy;
        }
    }

    /// @dev Whitelists the deployed implementation contracts in the ImplementationWhitelistProxy
    /// @param whitelistProxy Address of the whitelist proxy contract
    /// @param impls Implementation contract addresses to whitelist
    function _whitelistImplementations(address whitelistProxy, PlatformImplementations memory impls) internal {
        Create2Deployer.logSection("Whitelist Implementations");

        if (whitelistProxy == address(0) || !Create2Deployer.isContractDeployedAtAddress(whitelistProxy)) {
            console.log("  Skipping: WhitelistProxy not deployed yet");
            return;
        }

        ImplementationWhitelistImplementation whitelist = ImplementationWhitelistImplementation(whitelistProxy);

        // Check if already whitelisted
        bool orgWhitelisted = whitelist.isImplementationWhitelisted(ContractType.Organization, impls.organization);
        bool accWhitelisted = whitelist.isImplementationWhitelisted(ContractType.Account, impls.account);

        if (orgWhitelisted && accWhitelisted) {
            console.log(unicode"  ⏭️  SKIPPED: Implementations already whitelisted");
            return;
        }

        // Prepare arrays for whitelisting
        address[] memory toWhitelist;
        address[] memory empty = new address[](0);

        // Whitelist Organization implementation
        if (!orgWhitelisted) {
            toWhitelist = new address[](1);
            toWhitelist[0] = impls.organization;
            try whitelist.whitelistImplementations(ContractType.Organization, toWhitelist, empty) {
                console.log(unicode"  ✅ Whitelisted OrganizationImplementation");
            } catch {
                console.log(unicode"  ⚠️  Failed to whitelist OrganizationImplementation (requires owner)");
            }
        }

        // Whitelist Account implementation
        if (!accWhitelisted) {
            toWhitelist = new address[](1);
            toWhitelist[0] = impls.account;
            try whitelist.whitelistImplementations(ContractType.Account, toWhitelist, empty) {
                console.log(unicode"  ✅ Whitelisted AccountImplementation");
            } catch {
                console.log(unicode"  ⚠️  Failed to whitelist AccountImplementation (requires owner)");
            }
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
        bytes32 initCodeHash = SafeProxyFactory(safeInfra.proxyFactory).proxyCreationCodehash(safeInfra.singleton);

        // Use OpenZeppelin's Create2 utility for address computation
        return Create2.computeAddress(salt, initCodeHash, safeInfra.proxyFactory);
    }

    /// @dev Verifies that platform libraries are deployed at their expected CREATE2 addresses
    /// @param factory Address of the CREATE2 factory used for address computation
    function _validateLibraryAddressesDeployedOrRevert(address factory) internal view {
        Create2Deployer.logSection("Verify Library Addresses");

        address expectedPoliciesLibAddress = Create2Deployer.computeAddress(
            factory, DeploymentConfig.LIB_ORG_POLICY_SALT, type(LibOrganizationPolicy).creationCode
        );

        address expectedAdminLibAddress = Create2Deployer.computeAddress(
            factory, DeploymentConfig.LIB_ORG_ADMIN_SALT, type(LibOrganizationAdmin).creationCode
        );
        address expectedInitLibAddress = Create2Deployer.computeAddress(
            factory, DeploymentConfig.LIB_ORG_INIT_SALT, type(LibOrganizationInitialization).creationCode
        );
        address expectedAccSigLibAddress = Create2Deployer.computeAddress(
            factory, DeploymentConfig.LIB_ORG_ACCOUNT_SIG_SALT, type(LibOrganizationAccountSignature).creationCode
        );

        bool allDeployed = true;

        // Check if libraries are deployed at expected addresses
        if (!Create2Deployer.isContractDeployedAtAddress(expectedPoliciesLibAddress)) {
            console.log(
                unicode"  ❌ LibOrganizationPolicy NOT DEPLOYED at expected address: %s", expectedPoliciesLibAddress
            );
            allDeployed = false;
        } else {
            console.log(unicode"  ✅ LibOrganizationPolicy at %s", expectedPoliciesLibAddress);
        }

        if (!Create2Deployer.isContractDeployedAtAddress(expectedAdminLibAddress)) {
            console.log(
                unicode"  ❌ LibOrganizationAdmin NOT DEPLOYED at expected address: %s", expectedAdminLibAddress
            );
            allDeployed = false;
        } else {
            console.log(unicode"  ✅ LibOrganizationAdmin at %s", expectedAdminLibAddress);
        }

        if (!Create2Deployer.isContractDeployedAtAddress(expectedInitLibAddress)) {
            console.log(
                unicode"  ❌ LibOrganizationInitialization NOT DEPLOYED at expected address: %s",
                expectedInitLibAddress
            );
            allDeployed = false;
        } else {
            console.log(unicode"  ✅ LibOrganizationInitialization at %s", expectedInitLibAddress);
        }

        if (!Create2Deployer.isContractDeployedAtAddress(expectedAccSigLibAddress)) {
            console.log(
                unicode"  ❌ LibOrganizationAccountSignature NOT DEPLOYED at expected address: %s",
                expectedAccSigLibAddress
            );
            allDeployed = false;
        } else {
            console.log(unicode"  ✅ LibOrganizationAccountSignature at %s", expectedAccSigLibAddress);
        }

        if (!allDeployed) {
            console.log("");
            console.log(unicode"  ⚠️  WARNING: Some libraries are not deployed!");
            console.log("     Run DeployLibraries.s.sol first, then re-run this script with --libraries flags.");
            console.log("");
            revert("Some libraries are not deployed!");
        }
    }

    /// @dev Retrieves Guardian Safe configuration from environment variables
    /// @return owners Array of owner addresses for the Guardian Safe
    /// @return threshold Required number of signatures
    function _getGuardianSafeConfig() internal view returns (address[] memory owners, uint256 threshold) {
        // Try to get from environment
        try vm.envString("GUARDIAN_SAFE_OWNERS") returns (string memory ownersStr) {
            owners = _parseAddressArray(ownersStr);
            threshold = vm.envOr("GUARDIAN_SAFE_THRESHOLD", uint256(1));
        } catch {
            // Default: use deployer as single owner
            owners = new address[](1);
            owners[0] = vm.addr(vm.envUint("PRIVATE_KEY"));
            threshold = 1;
            console.log("  Warning: Using default Guardian Safe config (deployer as single owner)");
        }
    }

    /// @dev Retrieves Deployer Safe configuration from environment variables
    /// @return owners Array of owner addresses for the Deployer Safe
    /// @return threshold Required number of signatures
    function _getDeployerSafeConfig() internal view returns (address[] memory owners, uint256 threshold) {
        // Try to get from environment
        try vm.envString("DEPLOYER_SAFE_OWNERS") returns (string memory ownersStr) {
            owners = _parseAddressArray(ownersStr);
            threshold = vm.envOr("DEPLOYER_SAFE_THRESHOLD", uint256(1));
        } catch {
            // Default: use deployer as single owner
            owners = new address[](1);
            owners[0] = vm.addr(vm.envUint("PRIVATE_KEY"));
            threshold = 1;
            console.log("  Warning: Using default Deployer Safe config (deployer as single owner)");
        }
    }

    /// @dev Logs all deployed contract addresses in a formatted summary
    /// @param contracts Complete set of deployed contract addresses
    function _logDeployedAddresses(DeployedContracts memory contracts) internal pure {
        console.log("");
        console.log("================================================================================");
        console.log("  Deployed Contract Addresses");
        console.log("================================================================================");
        console.log("");
        console.log("  Safe Infrastructure:");
        console.log("    Safe Singleton:              %s", contracts.safeInfra.singleton);
        console.log("    SafeProxyFactory:            %s", contracts.safeInfra.proxyFactory);
        console.log("    FallbackHandler:             %s", contracts.safeInfra.fallbackHandler);
        console.log("    MultiSend:                   %s", contracts.safeInfra.multiSend);
        console.log("    MultiSendCallOnly:           %s", contracts.safeInfra.multiSendCallOnly);
        console.log("    CreateCall:                  %s", contracts.safeInfra.createCall);
        console.log("    SimulateTxAccessor:          %s", contracts.safeInfra.simulateTxAccessor);
        console.log("");
        console.log("  Safe Multisigs:");
        console.log("    Guardian Safe:               %s", contracts.safes.guardianSafe);
        console.log("    Deployer Safe:               %s", contracts.safes.deployerSafe);
        console.log("");
        console.log("  Platform Implementations:");
        console.log("    OrganizationImplementation:  %s", contracts.implementations.organization);
        console.log("    AccountImplementation:       %s", contracts.implementations.account);
        console.log("    WhitelistImplementation:     %s", contracts.implementations.whitelist);
        console.log("");
        console.log("  Platform Factories:");
        console.log("    OrganizationFactory:         %s", contracts.factories.organization);
        console.log("    WhitelistFactory:            %s", contracts.factories.whitelist);
        console.log("");
        console.log("  Platform Proxies:");
        console.log("    WhitelistProxy:              %s", contracts.whitelistProxy);
        console.log("");
        console.log("================================================================================");
    }

    /// @dev Parses a comma-separated string of addresses into an array
    /// @return Empty address array (placeholder implementation)
    function _parseAddressArray(string memory) internal pure returns (address[] memory) {
        // Simplified: return empty array, actual parsing would split by comma
        // In production, use a proper string parsing library
        return new address[](0);
    }
}
