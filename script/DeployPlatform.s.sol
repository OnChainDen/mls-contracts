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

// Platform libraries (for bytecode access)
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
 * @title DeployPlatform
 * @notice Main deployment script for the Den Onchain Custody platform
 * @dev Deploys all contracts deterministically using CREATE2, supporting both
 *      Arachnid and Safe Singleton Factory. Contracts are deployed in dependency order.
 *
 *      IMPORTANT: For fully deterministic deployment, this script requires TWO runs:
 *
 *      Run 1 - Deploy Libraries:
 *        forge script script/DeployPlatform.s.sol:DeployPlatform --sig "deployLibraries()" ...
 *
 *      Run 2 - Deploy Everything (with library linking):
 *        forge script script/DeployPlatform.s.sol:DeployPlatform --libraries <lib-flags> ...
 *
 *      The script will output the required --libraries flag after deploying libraries.
 *
 *      Deployment Order:
 *      1. Safe Infrastructure (Safe singleton, proxy factory, handlers, libraries)
 *      2. Safe Multisigs (Guardian Safe, Deployer Safe)
 *      3. Platform Libraries (LibOrganizationPolicy, Admin, Init, AccountSignature)
 *      4. Implementation Contracts (OrganizationImpl, AccountImpl, WhitelistImpl)
 *      5. Factory Contracts (OrganizationFactory, WhitelistFactory)
 *      6. ImplementationWhitelistProxy (via factory)
 *      7. Whitelist initial implementations
 *
 * @author Den Technologies Inc
 */
contract DeployPlatform is Script {
    // ============================================================
    // Deployed Contract Addresses (populated during deployment)
    // ============================================================

    // Safe Infrastructure
    address public safeSingleton;
    address public safeProxyFactory;
    address public compatibilityFallbackHandler;
    address public multiSend;
    address public multiSendCallOnly;
    address public createCall;
    address public simulateTxAccessor;

    // Safe Multisigs
    address public guardianSafe;
    address public deployerSafe;

    // Platform Libraries
    address public libOrganizationPolicy;
    address public libOrganizationAdmin;
    address public libOrganizationInitialization;
    address public libOrganizationAccountSignature;

    // Platform Contracts
    address public organizationImplementation;
    address public accountImplementation;
    address public whitelistImplementation;
    address public organizationFactory;
    address public whitelistFactory;
    address public whitelistProxy;

    // CREATE2 Factory being used
    address public create2Factory;

    /**
     * @notice Deploy only the platform libraries via CREATE2
     * @dev Run this first, then use the output to run the full deployment with --libraries flag
     */
    function deployLibraries() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        create2Factory = _getCreate2Factory();

        Create2Deployer.logDeploymentHeader(create2Factory, block.chainid);
        console.log("  Deployer EOA: %s", deployerAddress);
        console.log("  Mode: Library Deployment Only");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        _deployPlatformLibraries();

        vm.stopBroadcast();

        // Output the --libraries command
        _printLibrariesCommand();
    }

    /**
     * @notice Compute and print library addresses without deploying
     * @dev Use this to get the --libraries flag before any deployment
     */
    function computeLibraryAddresses() external view {
        address factory = _getCreate2Factory();

        console.log("");
        console.log("================================================================================");
        console.log("  Computed Deterministic Library Addresses");
        console.log("================================================================================");
        console.log("  CREATE2 Factory: %s", factory);
        console.log("  Chain ID: %s", block.chainid);
        console.log("");

        address libPolicy = Create2Deployer.computeAddress(
            factory, DeploymentConfig.LIB_ORG_POLICY_SALT, type(LibOrganizationPolicy).creationCode
        );
        address libAdmin = Create2Deployer.computeAddress(
            factory, DeploymentConfig.LIB_ORG_ADMIN_SALT, type(LibOrganizationAdmin).creationCode
        );
        address libInit = Create2Deployer.computeAddress(
            factory, DeploymentConfig.LIB_ORG_INIT_SALT, type(LibOrganizationInitialization).creationCode
        );
        address libAccSig = Create2Deployer.computeAddress(
            factory, DeploymentConfig.LIB_ORG_ACCOUNT_SIG_SALT, type(LibOrganizationAccountSignature).creationCode
        );

        console.log("  LibOrganizationPolicy:          %s", libPolicy);
        console.log("  LibOrganizationAdmin:           %s", libAdmin);
        console.log("  LibOrganizationInitialization:  %s", libInit);
        console.log("  LibOrganizationAccountSignature: %s", libAccSig);
        console.log("");

        _printLibrariesCommandWithAddresses(libPolicy, libAdmin, libInit, libAccSig);
    }

    /**
     * @notice Main entry point for the deployment script
     * @dev IMPORTANT: For deterministic deployment, run deployLibraries() first,
     *      then run this with the --libraries flag output from that command.
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

        // Step 3: Deploy Platform Libraries via CREATE2
        _deployPlatformLibraries();

        // Verify libraries are at expected addresses (critical for determinism)
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

        // Print the --libraries command for reference
        _printLibrariesCommand();
    }

    // ============================================================
    // Step 1: Safe Infrastructure
    // ============================================================

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

    // ============================================================
    // Step 2: Safe Multisigs
    // ============================================================

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

    /**
     * @dev Computes the CREATE2 address for a Safe proxy deployed via SafeProxyFactory
     *      SafeProxyFactory uses: salt = keccak256(abi.encodePacked(keccak256(initializer), saltNonce))
     */
    function _computeSafeProxyAddress(bytes memory initializer, uint256 saltNonce) internal view returns (address) {
        // SafeProxyFactory computes salt as: keccak256(abi.encodePacked(keccak256(initializer), saltNonce))
        bytes32 salt = keccak256(abi.encodePacked(keccak256(initializer), saltNonce));

        // Get the init code hash from the factory (includes singleton address)
        bytes32 initCodeHash = SafeProxyFactory(safeProxyFactory).proxyCreationCodehash(safeSingleton);

        // Use OpenZeppelin's Create2 utility for address computation
        return Create2.computeAddress(salt, initCodeHash, safeProxyFactory);
    }

    // ============================================================
    // Step 3: Platform Libraries (via CREATE2)
    // ============================================================

    function _deployPlatformLibraries() internal {
        Create2Deployer.logSection("Platform Libraries (CREATE2)");

        // Deploy LibOrganizationPolicy
        (libOrganizationPolicy,) = Create2Deployer.deployIfNotExists(
            create2Factory,
            DeploymentConfig.LIB_ORG_POLICY_SALT,
            type(LibOrganizationPolicy).creationCode,
            "LibOrganizationPolicy"
        );

        // Deploy LibOrganizationAdmin
        (libOrganizationAdmin,) = Create2Deployer.deployIfNotExists(
            create2Factory,
            DeploymentConfig.LIB_ORG_ADMIN_SALT,
            type(LibOrganizationAdmin).creationCode,
            "LibOrganizationAdmin"
        );

        // Deploy LibOrganizationInitialization
        (libOrganizationInitialization,) = Create2Deployer.deployIfNotExists(
            create2Factory,
            DeploymentConfig.LIB_ORG_INIT_SALT,
            type(LibOrganizationInitialization).creationCode,
            "LibOrganizationInitialization"
        );

        // Deploy LibOrganizationAccountSignature
        (libOrganizationAccountSignature,) = Create2Deployer.deployIfNotExists(
            create2Factory,
            DeploymentConfig.LIB_ORG_ACCOUNT_SIG_SALT,
            type(LibOrganizationAccountSignature).creationCode,
            "LibOrganizationAccountSignature"
        );
    }

    /**
     * @dev Verifies that libraries are deployed at the expected CREATE2 addresses
     *      This is critical - if they don't match, OrganizationImplementation won't work
     */
    function _verifyLibraryAddresses() internal view {
        console.log("");
        console.log("  Verifying library addresses match CREATE2 expectations...");

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

        bool allMatch = true;

        if (libOrganizationPolicy != expectedPolicy) {
            console.log(unicode"  ❌ LibOrganizationPolicy mismatch!");
            console.log("     Expected: %s", expectedPolicy);
            console.log("     Got: %s", libOrganizationPolicy);
            allMatch = false;
        }

        if (libOrganizationAdmin != expectedAdmin) {
            console.log(unicode"  ❌ LibOrganizationAdmin mismatch!");
            allMatch = false;
        }

        if (libOrganizationInitialization != expectedInit) {
            console.log(unicode"  ❌ LibOrganizationInitialization mismatch!");
            allMatch = false;
        }

        if (libOrganizationAccountSignature != expectedAccSig) {
            console.log(unicode"  ❌ LibOrganizationAccountSignature mismatch!");
            allMatch = false;
        }

        if (allMatch) {
            console.log(unicode"  ✅ All library addresses match expected CREATE2 addresses");
        } else {
            console.log("");
            console.log(unicode"  ⚠️  WARNING: Library addresses don't match expected CREATE2 addresses!");
            console.log("     This may indicate the script was run without --libraries flag.");
            console.log("     OrganizationImplementation may not be deterministic across chains.");
            console.log("");
        }
    }

    // ============================================================
    // Step 4: Implementation Contracts
    // ============================================================

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
        // IMPORTANT: For deterministic deployment, this script must be run with --libraries flag
        // pointing to the CREATE2-deployed library addresses
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

    // ============================================================
    // Step 5: Factory Contracts
    // ============================================================

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

    // ============================================================
    // Step 6: Deploy ImplementationWhitelistProxy
    // ============================================================

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
        // For the initial deployment, we need the deployer EOA to be the DEPLOYER_ADDRESS
        // OR we need to execute this via the Safe
        // For simplicity in scripts, we check if msg.sender is the deployer
        console.log("  Note: WhitelistProxy deployment requires deployerSafe to call the factory");
        console.log("  For initial deployment, configure ImplementationWhitelistFactory with EOA deployer");
        console.log("  Or execute this step via the Deployer Safe multisig");

        // If deployer matches factory's DEPLOYER_ADDRESS, deploy directly
        // Otherwise, this step needs to be done via Safe transaction
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

    // ============================================================
    // Step 7: Whitelist Implementations
    // ============================================================

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

    // ============================================================
    // Helper Functions
    // ============================================================

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

    function _parseAddressArray(string memory) internal pure returns (address[] memory) {
        // Simplified: return empty array, actual parsing would split by comma
        // In production, use a proper string parsing library
        return new address[](0);
    }

    function _printLibrariesCommand() internal view {
        _printLibrariesCommandWithAddresses(
            libOrganizationPolicy, libOrganizationAdmin, libOrganizationInitialization, libOrganizationAccountSignature
        );
    }

    function _printLibrariesCommandWithAddresses(
        address libPolicy,
        address libAdmin,
        address libInit,
        address libAccSig
    ) internal pure {
        console.log("");
        console.log("================================================================================");
        console.log("  IMPORTANT: For deterministic OrganizationImplementation deployment,");
        console.log("  run the full deployment with the following --libraries flags:");
        console.log("================================================================================");
        console.log("");
        console.log("  forge script script/DeployPlatform.s.sol:DeployPlatform \\");
        console.log("    --rpc-url $RPC_URL \\");
        console.log("    --broadcast \\");
        console.log("    --libraries %s:%s \\", DeploymentConfig.LIB_ORG_POLICY_PATH, libPolicy);
        console.log("    --libraries %s:%s \\", DeploymentConfig.LIB_ORG_ADMIN_PATH, libAdmin);
        console.log("    --libraries %s:%s \\", DeploymentConfig.LIB_ORG_INIT_PATH, libInit);
        console.log("    --libraries %s:%s \\", DeploymentConfig.LIB_ORG_ACCOUNT_SIG_PATH, libAccSig);
        console.log("    -vvvv");
        console.log("");
        console.log("================================================================================");
    }

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
        console.log("  Platform Libraries:");
        console.log("    LibOrganizationPolicy:       %s", libOrganizationPolicy);
        console.log("    LibOrganizationAdmin:        %s", libOrganizationAdmin);
        console.log("    LibOrganizationInit:         %s", libOrganizationInitialization);
        console.log("    LibOrganizationAccSig:       %s", libOrganizationAccountSignature);
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
