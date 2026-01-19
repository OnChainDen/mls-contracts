// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Script, console} from "forge-std/Script.sol";

// Safe contracts
import {CompatibilityFallbackHandler} from "@safe/handler/CompatibilityFallbackHandler.sol";
import {CreateCall} from "@safe/libraries/CreateCall.sol";
import {MultiSend} from "@safe/libraries/MultiSend.sol";
import {MultiSendCallOnly} from "@safe/libraries/MultiSendCallOnly.sol";
import {Safe} from "@safe/Safe.sol";
import {SafeProxyFactory} from "@safe/proxies/SafeProxyFactory.sol";
import {SimulateTxAccessor} from "@safe/accessors/SimulateTxAccessor.sol";

// Platform contracts
import {AccountImplementation} from "account/AccountImplementation.sol";
import {ImplementationWhitelistFactory} from "implementation-whitelist/ImplementationWhitelistFactory.sol";
import {ImplementationWhitelistImplementation} from "implementation-whitelist/ImplementationWhitelistImplementation.sol";
import {OrganizationFactory} from "organization/OrganizationFactory.sol";
import {OrganizationImplementation} from "organization/OrganizationImplementation.sol";
import {ContractType} from "types/CommonTypes.sol";

// Platform libraries (for bytecode access - used for verification)
import {LibOrganizationAccountSignature} from "organization/libraries/LibOrganizationAccountSignature.sol";
import {LibOrganizationAdmin} from "organization/libraries/LibOrganizationAdmin.sol";
import {LibOrganizationInitialization} from "organization/libraries/LibOrganizationInitialization.sol";
import {LibOrganizationPolicy} from "organization/libraries/LibOrganizationPolicy.sol";

// OpenZeppelin utilities
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

// Script utilities
import {DeploymentConfig} from "script/config/DeploymentConfig.sol";
import {ISafe} from "@safe/interfaces/ISafe.sol";
import {Create2Deployer} from "script/libraries/Create2Deployer.sol";

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
    /// @notice Address of the deployed Safe Singleton (master copy)
    address public safeSingleton;

    /// @notice Address of the deployed SafeProxyFactory
    address public safeProxyFactory;

    /// @notice Address of the deployed CompatibilityFallbackHandler
    address public compatibilityFallbackHandler;

    /// @notice Address of the deployed MultiSend library
    address public multiSend;

    /// @notice Address of the deployed MultiSendCallOnly library
    address public multiSendCallOnly;

    /// @notice Address of the deployed CreateCall library
    address public createCall;

    /// @notice Address of the deployed SimulateTxAccessor
    address public simulateTxAccessor;

    /// @notice Address of the deployed Guardian Safe multisig
    address public guardianSafe;

    /// @notice Address of the deployed Deployer Safe multisig
    address public deployerSafe;

    /// @notice Address of the deployed OrganizationImplementation contract
    address public organizationImplementation;

    /// @notice Address of the deployed AccountImplementation contract
    address public accountImplementation;

    /// @notice Address of the deployed ImplementationWhitelistImplementation contract
    address public whitelistImplementation;

    /// @notice Address of the deployed OrganizationFactory contract
    address public organizationFactory;

    /// @notice Address of the deployed ImplementationWhitelistFactory contract
    address public whitelistFactory;

    /// @notice Address of the deployed ImplementationWhitelistProxy contract
    address public whitelistProxy;

    /// @notice Address of the CREATE2 factory being used for deployments
    address public create2Factory;

    /**
     * @notice Main entry point for the deployment script
     * @dev IMPORTANT: Run with --libraries flags pointing to CREATE2-deployed library addresses
     */
    function run() external {
        // Get configuration from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        // Get CREATE2 factory (from env or auto-detect)
        create2Factory = _getCreate2Factory();

        // Get Safe multisig configuration
        (address[] memory guardianSafeOwners, uint256 guardianSafeThreshold) = _getGuardianSafeConfig();
        (address[] memory deployerSafeOwners, uint256 deployerSafeThreshold) = _getDeployerSafeConfig();

        // Log deployment header
        Create2Deployer.logDeploymentHeader(create2Factory, block.chainid);
        console.log("  Deployer EOA: %s", deployerAddress);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy Safe Infrastructure
        _deploySafeInfrastructure();

        // Step 2: Deploy Safe Multisigs
        _deploySafeMultisigs(guardianSafeOwners, guardianSafeThreshold, deployerSafeOwners, deployerSafeThreshold);

        // Step 3: Verify libraries are at expected addresses (critical for determinism)
        _verifyLibraryAddresses();

        // Step 4: Deploy Implementation Contracts
        _deployImplementationContracts();

        // Step 5: Deploy Factory Contracts
        _deployFactoryContracts();

        // Step 6: Deploy ImplementationWhitelistProxy via factory
        _deployWhitelistProxy();

        // Step 7: Whitelist implementations
        _whitelistImplementations();

        vm.stopBroadcast();

        // Log completion
        Create2Deployer.logDeploymentComplete();
        _logDeployedAddresses();
    }

    /// @dev Deploys all Safe infrastructure contracts via CREATE2
    ///      Includes: Safe singleton, proxy factory, fallback handler, MultiSend libraries,
    ///      CreateCall, and SimulateTxAccessor
    function _deploySafeInfrastructure() internal {
        Create2Deployer.logSection("Safe Infrastructure");

        // Deploy Safe Singleton (master copy)
        (safeSingleton,) = Create2Deployer.deployIfNotExists(
            create2Factory, DeploymentConfig.SAFE_SINGLETON_SALT, type(Safe).creationCode, "Safe Singleton"
        );

        // Deploy Safe Proxy Factory
        (safeProxyFactory,) = Create2Deployer.deployIfNotExists(
            create2Factory,
            DeploymentConfig.SAFE_PROXY_FACTORY_SALT,
            type(SafeProxyFactory).creationCode,
            "SafeProxyFactory"
        );

        // Deploy Compatibility Fallback Handler
        (compatibilityFallbackHandler,) = Create2Deployer.deployIfNotExists(
            create2Factory,
            DeploymentConfig.SAFE_FALLBACK_HANDLER_SALT,
            type(CompatibilityFallbackHandler).creationCode,
            "CompatibilityFallbackHandler"
        );

        // Deploy MultiSend
        (multiSend,) = Create2Deployer.deployIfNotExists(
            create2Factory, DeploymentConfig.SAFE_MULTISEND_SALT, type(MultiSend).creationCode, "MultiSend"
        );

        // Deploy MultiSendCallOnly
        (multiSendCallOnly,) = Create2Deployer.deployIfNotExists(
            create2Factory,
            DeploymentConfig.SAFE_MULTISEND_CALL_ONLY_SALT,
            type(MultiSendCallOnly).creationCode,
            "MultiSendCallOnly"
        );

        // Deploy CreateCall
        (createCall,) = Create2Deployer.deployIfNotExists(
            create2Factory, DeploymentConfig.SAFE_CREATE_CALL_SALT, type(CreateCall).creationCode, "CreateCall"
        );

        // Deploy SimulateTxAccessor
        (simulateTxAccessor,) = Create2Deployer.deployIfNotExists(
            create2Factory,
            DeploymentConfig.SAFE_SIMULATE_TX_ACCESSOR_SALT,
            type(SimulateTxAccessor).creationCode,
            "SimulateTxAccessor"
        );
    }

    /// @dev Deploys Guardian and Deployer Safe multisig wallets
    /// @param guardianSafeOwners Array of owner addresses for the Guardian Safe
    /// @param guardianSafeThreshold Required signatures threshold for Guardian Safe
    /// @param deployerSafeOwners Array of owner addresses for the Deployer Safe
    /// @param deployerSafeThreshold Required signatures threshold for Deployer Safe
    function _deploySafeMultisigs(
        address[] memory guardianSafeOwners,
        uint256 guardianSafeThreshold,
        address[] memory deployerSafeOwners,
        uint256 deployerSafeThreshold
    ) internal {
        Create2Deployer.logSection("Safe Multisigs");

        // Deploy Guardian Safe
        guardianSafe = _deploySafeMultisig(
            guardianSafeOwners, guardianSafeThreshold, DeploymentConfig.GUARDIAN_SAFE_SALT, "Guardian Safe"
        );

        // Deploy Deployer Safe
        deployerSafe = _deploySafeMultisig(
            deployerSafeOwners, deployerSafeThreshold, DeploymentConfig.DEPLOYER_SAFE_SALT, "Deployer Safe"
        );
    }

    /// @dev Deploys a Safe multisig wallet using SafeProxyFactory
    /// @param owners Array of owner addresses for the Safe
    /// @param threshold Required number of signatures for transactions
    /// @param salt Salt used for deterministic address computation
    /// @param name Human-readable name for logging purposes
    /// @return safe Address of the deployed Safe proxy
    function _deploySafeMultisig(address[] memory owners, uint256 threshold, bytes32 salt, string memory name)
        internal
        returns (address safe)
    {
        // Encode the initializer for Safe.setup()
        bytes memory initializer = abi.encodeCall(
            ISafe.setup,
            (
                owners,
                threshold,
                address(0), // to - no delegate call
                "", // data - no delegate call data
                compatibilityFallbackHandler,
                address(0), // paymentToken - ETH
                0, // payment - no payment
                payable(address(0)) // paymentReceiver
            )
        );

        uint256 saltNonce = uint256(salt);

        // Compute expected address using SafeProxyFactory's CREATE2 formula
        safe = _computeSafeProxyAddress(initializer, saltNonce);

        // Check if already deployed
        if (safe.code.length > 0) {
            console.log(unicode"  ⏭️  SKIPPED: %s (already deployed at %s)", name, safe);
            return safe;
        }

        // Deploy the Safe
        address deployedAtAddress =
            address(SafeProxyFactory(safeProxyFactory).createProxyWithNonce(safeSingleton, initializer, saltNonce));
        console.log(unicode"  ✅ DEPLOYED: %s at %s", name, deployedAtAddress);

        // Verify deployment matches expected address
        require(deployedAtAddress == safe, "Safe deployed at unexpected address");
    }

    /// @dev Computes the deterministic address of a Safe proxy before deployment
    /// @param initializer Encoded Safe.setup() call data
    /// @param saltNonce Nonce used for salt computation
    /// @return The predicted Safe proxy address
    function _computeSafeProxyAddress(bytes memory initializer, uint256 saltNonce) internal view returns (address) {
        // SafeProxyFactory computes salt as: keccak256(abi.encodePacked(keccak256(initializer), saltNonce))
        bytes32 salt = keccak256(abi.encodePacked(keccak256(initializer), saltNonce));

        // Get the init code hash from the factory (includes singleton address)
        bytes32 initCodeHash = SafeProxyFactory(safeProxyFactory).proxyCreationCodehash(safeSingleton);

        // Use OpenZeppelin's Create2 utility for address computation
        return Create2.computeAddress(salt, initCodeHash, safeProxyFactory);
    }

    /// @dev Verifies that platform libraries are deployed at their expected CREATE2 addresses
    ///      Logs warnings if any libraries are missing and need to be deployed first
    function _verifyLibraryAddresses() internal view {
        Create2Deployer.logSection("Verify Library Addresses");

        address expectedPolicy = Create2Deployer.computeAddress(
            create2Factory, DeploymentConfig.LIB_ORG_POLICY_SALT, type(LibOrganizationPolicy).creationCode
        );
        address expectedAdmin = Create2Deployer.computeAddress(
            create2Factory, DeploymentConfig.LIB_ORG_ADMIN_SALT, type(LibOrganizationAdmin).creationCode
        );
        address expectedInit = Create2Deployer.computeAddress(
            create2Factory, DeploymentConfig.LIB_ORG_INIT_SALT, type(LibOrganizationInitialization).creationCode
        );
        address expectedAccSig = Create2Deployer.computeAddress(
            create2Factory, DeploymentConfig.LIB_ORG_ACCOUNT_SIG_SALT, type(LibOrganizationAccountSignature).creationCode
        );

        bool allDeployed = true;

        // Check if libraries are deployed at expected addresses
        if (expectedPolicy.code.length == 0) {
            console.log(unicode"  ❌ LibOrganizationPolicy NOT DEPLOYED at expected address: %s", expectedPolicy);
            allDeployed = false;
        } else {
            console.log(unicode"  ✅ LibOrganizationPolicy at %s", expectedPolicy);
        }

        if (expectedAdmin.code.length == 0) {
            console.log(unicode"  ❌ LibOrganizationAdmin NOT DEPLOYED at expected address: %s", expectedAdmin);
            allDeployed = false;
        } else {
            console.log(unicode"  ✅ LibOrganizationAdmin at %s", expectedAdmin);
        }

        if (expectedInit.code.length == 0) {
            console.log(unicode"  ❌ LibOrganizationInitialization NOT DEPLOYED at expected address: %s", expectedInit);
            allDeployed = false;
        } else {
            console.log(unicode"  ✅ LibOrganizationInitialization at %s", expectedInit);
        }

        if (expectedAccSig.code.length == 0) {
            console.log(
                unicode"  ❌ LibOrganizationAccountSignature NOT DEPLOYED at expected address: %s", expectedAccSig
            );
            allDeployed = false;
        } else {
            console.log(unicode"  ✅ LibOrganizationAccountSignature at %s", expectedAccSig);
        }

        if (!allDeployed) {
            console.log("");
            console.log(unicode"  ⚠️  WARNING: Some libraries are not deployed!");
            console.log("     Run DeployLibraries.s.sol first, then re-run this script with --libraries flags.");
            console.log("");
        }
    }

    /// @dev Deploys all implementation contracts via CREATE2
    ///      Includes: OrganizationImplementation, AccountImplementation, ImplementationWhitelistImplementation
    function _deployImplementationContracts() internal {
        Create2Deployer.logSection("Implementation Contracts");

        // Deploy ImplementationWhitelistImplementation
        (whitelistImplementation,) = Create2Deployer.deployIfNotExists(
            create2Factory,
            DeploymentConfig.WHITELIST_IMPL_SALT,
            type(ImplementationWhitelistImplementation).creationCode,
            "ImplementationWhitelistImplementation"
        );

        // Deploy OrganizationImplementation
        // IMPORTANT: This script must be run with --libraries flag for deterministic deployment
        (organizationImplementation,) = Create2Deployer.deployIfNotExists(
            create2Factory,
            DeploymentConfig.ORG_IMPL_SALT,
            type(OrganizationImplementation).creationCode,
            "OrganizationImplementation"
        );

        // Deploy AccountImplementation
        (accountImplementation,) = Create2Deployer.deployIfNotExists(
            create2Factory,
            DeploymentConfig.ACCOUNT_IMPL_SALT,
            type(AccountImplementation).creationCode,
            "AccountImplementation"
        );
    }

    /// @dev Deploys factory contracts via CREATE2
    ///      Includes: OrganizationFactory, ImplementationWhitelistFactory
    ///      Both factories are initialized with deployerSafe as the authorized deployer
    function _deployFactoryContracts() internal {
        Create2Deployer.logSection("Factory Contracts");

        // Deploy ImplementationWhitelistFactory with deployerSafe as the deployer
        bytes memory whitelistFactoryInitCode =
            abi.encodePacked(type(ImplementationWhitelistFactory).creationCode, abi.encode(deployerSafe));

        (whitelistFactory,) = Create2Deployer.deployIfNotExists(
            create2Factory, DeploymentConfig.WHITELIST_FACTORY_SALT, whitelistFactoryInitCode, "WhitelistFactory"
        );

        // Deploy OrganizationFactory with deployerSafe as the deployer
        bytes memory orgFactoryInitCode =
            abi.encodePacked(type(OrganizationFactory).creationCode, abi.encode(deployerSafe));

        (organizationFactory,) = Create2Deployer.deployIfNotExists(
            create2Factory, DeploymentConfig.ORG_FACTORY_SALT, orgFactoryInitCode, "OrganizationFactory"
        );
    }

    /// @dev Deploys the ImplementationWhitelistProxy via ImplementationWhitelistFactory
    ///      This proxy serves as the canonical whitelist for approved implementations
    function _deployWhitelistProxy() internal {
        Create2Deployer.logSection("ImplementationWhitelistProxy");

        // Compute expected address
        address expectedProxy = ImplementationWhitelistFactory(whitelistFactory).computeImplementationWhitelistAddress(
            DeploymentConfig.WHITELIST_PROXY_SALT, whitelistImplementation
        );

        // Check if already deployed
        if (expectedProxy.code.length > 0) {
            whitelistProxy = expectedProxy;
            console.log(unicode"  ⏭️  SKIPPED: ImplementationWhitelistProxy (already at %s)", whitelistProxy);
            return;
        }

        // Note: This call must come from the deployerSafe
        console.log("  Note: WhitelistProxy deployment requires deployerSafe to call the factory");
        console.log("  For initial deployment, configure ImplementationWhitelistFactory with EOA deployer");
        console.log("  Or execute this step via the Deployer Safe multisig");

        // If deployer matches factory's DEPLOYER_ADDRESS, deploy directly
        try ImplementationWhitelistFactory(whitelistFactory).deployImplementationWhitelist(
            DeploymentConfig.WHITELIST_PROXY_SALT,
            whitelistImplementation,
            deployerSafe // Owner of the whitelist
        ) returns (address deployedAtAddress) {
            whitelistProxy = deployedAtAddress;
            console.log(unicode"  ✅ DEPLOYED: ImplementationWhitelistProxy at %s", whitelistProxy);
        } catch {
            console.log(unicode"  ⚠️  SKIPPED: Deployment requires authorization from deployerSafe");
            whitelistProxy = expectedProxy;
        }
    }

    /// @dev Whitelists the deployed implementation contracts in the ImplementationWhitelistProxy
    ///      Registers OrganizationImplementation and AccountImplementation as approved implementations
    function _whitelistImplementations() internal {
        Create2Deployer.logSection("Whitelist Implementations");

        if (whitelistProxy == address(0) || whitelistProxy.code.length == 0) {
            console.log("  Skipping: WhitelistProxy not deployed yet");
            return;
        }

        ImplementationWhitelistImplementation whitelist = ImplementationWhitelistImplementation(whitelistProxy);

        // Check if already whitelisted
        bool orgWhitelisted =
            whitelist.isImplementationWhitelisted(ContractType.Organization, organizationImplementation);
        bool accWhitelisted = whitelist.isImplementationWhitelisted(ContractType.Account, accountImplementation);

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
            toWhitelist[0] = organizationImplementation;
            try whitelist.whitelistImplementations(ContractType.Organization, toWhitelist, empty) {
                console.log(unicode"  ✅ Whitelisted OrganizationImplementation");
            } catch {
                console.log(unicode"  ⚠️  Failed to whitelist OrganizationImplementation (requires owner)");
            }
        }

        // Whitelist Account implementation
        if (!accWhitelisted) {
            toWhitelist = new address[](1);
            toWhitelist[0] = accountImplementation;
            try whitelist.whitelistImplementations(ContractType.Account, toWhitelist, empty) {
                console.log(unicode"  ✅ Whitelisted AccountImplementation");
            } catch {
                console.log(unicode"  ⚠️  Failed to whitelist AccountImplementation (requires owner)");
            }
        }
    }

    /// @dev Retrieves the CREATE2 factory address from environment or auto-detects one
    /// @return factory Address of the available CREATE2 factory
    function _getCreate2Factory() internal view returns (address factory) {
        // First, check if explicitly provided
        try vm.envAddress("CREATE2_FACTORY_ADDRESS") returns (address provided) {
            if (provided != address(0) && provided.code.length > 0) {
                return provided;
            }
        } catch {}

        // Auto-detect available factory
        (factory,) = Create2Deployer.getAvailableFactory();

        if (factory == address(0)) {
            revert("No CREATE2 factory available. Deploy Safe Singleton Factory first.");
        }
    }

    /// @dev Retrieves Guardian Safe configuration from environment variables
    ///      Falls back to deployer as single owner if not configured
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
    ///      Falls back to deployer as single owner if not configured
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

    /// @dev Parses a comma-separated string of addresses into an array
    ///      Note: Simplified implementation - returns empty array
    ///      In production, use a proper string parsing library
    /// @return Empty address array (placeholder implementation)
    function _parseAddressArray(string memory) internal pure returns (address[] memory) {
        // Simplified: return empty array, actual parsing would split by comma
        // In production, use a proper string parsing library
        return new address[](0);
    }

    /// @dev Logs all deployed contract addresses in a formatted summary
    function _logDeployedAddresses() internal view {
        console.log("");
        console.log("================================================================================");
        console.log("  Deployed Contract Addresses");
        console.log("================================================================================");
        console.log("");
        console.log("  Safe Infrastructure:");
        console.log("    Safe Singleton:              %s", safeSingleton);
        console.log("    SafeProxyFactory:            %s", safeProxyFactory);
        console.log("    FallbackHandler:             %s", compatibilityFallbackHandler);
        console.log("    MultiSend:                   %s", multiSend);
        console.log("    MultiSendCallOnly:           %s", multiSendCallOnly);
        console.log("    CreateCall:                  %s", createCall);
        console.log("    SimulateTxAccessor:          %s", simulateTxAccessor);
        console.log("");
        console.log("  Safe Multisigs:");
        console.log("    Guardian Safe:               %s", guardianSafe);
        console.log("    Deployer Safe:               %s", deployerSafe);
        console.log("");
        console.log("  Platform Implementations:");
        console.log("    OrganizationImplementation:  %s", organizationImplementation);
        console.log("    AccountImplementation:       %s", accountImplementation);
        console.log("    WhitelistImplementation:     %s", whitelistImplementation);
        console.log("");
        console.log("  Platform Factories:");
        console.log("    OrganizationFactory:         %s", organizationFactory);
        console.log("    WhitelistFactory:            %s", whitelistFactory);
        console.log("");
        console.log("  Platform Proxies:");
        console.log("    WhitelistProxy:              %s", whitelistProxy);
        console.log("");
        console.log("================================================================================");
    }
}
