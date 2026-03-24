// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.7.6;

// Safe 1.4.1 imports (renamed from Gnosis* to Safe*)
import {Safe} from "@safe/Safe.sol";
import {SafeProxy} from "@safe/proxies/SafeProxy.sol";
import {SafeProxyFactory} from "@safe/proxies/SafeProxyFactory.sol";

// Shared script utilities
import {BaseDeployScript} from "script/base/BaseDeployScript.sol";
import {Create2Utils} from "script/libraries/Create2Utils.sol";
import {Logger} from "script/libraries/Logger.sol";
import {SafeInfrastructure} from "script/libraries/Types.sol";

/**
 * @title DeploySafeMultisigs
 * @notice Deploys Safe multisig wallets (Guardian and Admin Safes)
 * @dev This script deploys Safe multisig proxies using Solidity 0.7.6 for deterministic addresses.
 *
 *      IMPORTANT: This script must be compiled with the [profile.safe] foundry profile:
 *        FOUNDRY_PROFILE=safe forge script script/safe/DeploySafeMultisigs.s.sol:DeploySafeMultisigs \
 *          --sig "run(address)" <CREATE2_FACTORY_ADDRESS> \
 *          --rpc-url $RPC_URL \
 *          --broadcast \
 *          -vvvv
 *
 *      PREREQUISITE: Safe infrastructure must be deployed first using DeploySafeInfrastructure.s.sol.
 *      This script will verify that the Safe Singleton is deployed before attempting to deploy
 *      multisig proxies.
 *
 *      This script deploys the following multisig wallets:
 *      - Guardian Safe (security operations multisig)
 *      - Admin Safe (whitelist admin operations multisig)
 *
 *      SAFETY CHECKS:
 *      1. Verifies the provided CREATE2 factory is a known factory from deployment.toml
 *      2. Verifies the provided CREATE2 factory is deployed
 *      3. Verifies that the deployer is not the production Den Factory deployer
 *      4. Verifies that Safe infrastructure is deployed at expected addresses
 *      5. Warns and requires confirmation when targeting production chains
 *      6. Requires interactive confirmation when broadcasting
 *
 * @author Den Technologies Inc
 */
contract DeploySafeMultisigs is BaseDeployScript {
    /// @dev Struct containing addresses for the deployed Safe multisig wallets
    struct SafeMultisigs {
        address guardianSafeAddress;
        address adminSafeAddress;
    }

    /**
     * @notice Main entry point for the deployment script
     * @param factoryAddress Address of the CREATE2 factory to use for deployments
     */
    function run(address factoryAddress) external {
        // Common deployment initialization (factory validation, confirmations, header logging)
        validateAndInitializeDeploymentOrRevert(factoryAddress, "DeploySafeMultisigs");

        // Verify Safe infrastructure is deployed (CRITICAL for security)
        validateSafeInfrastructureDeployedOrRevert();

        // Determine variant based on chain (prod for production chains, nonprod otherwise)
        string memory variant = _isProductionChain() ? "prod" : "nonprod";

        // Get Safe configurations (after init since they read from TOML)
        (address[] memory guardianOwnerAddresses, uint256 guardianThreshold) = getGuardianSafeConfig(variant);
        (address[] memory adminOwnerAddresses, uint256 adminThreshold) = getAdminSafeConfig(variant);

        // Get Safe infrastructure addresses from deployment.toml
        SafeInfrastructure memory safeInfra = getExpectedSafeInfrastructureAddresses();

        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy our two Safe Multisigs (Admin and Guardian Safes)
        SafeMultisigs memory safes = _deploySafeMultisigs({
            safeInfra: safeInfra,
            guardianOwnerAddresses: guardianOwnerAddresses,
            guardianThreshold: guardianThreshold,
            adminOwnerAddresses: adminOwnerAddresses,
            adminThreshold: adminThreshold
        });

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Log deployed addresses
        _logDeployedAddresses(safes);
    }

    /// @dev Deploys Guardian and Admin Safe multisig wallets
    /// @param safeInfra Safe infrastructure addresses needed for Safe deployment
    /// @param guardianOwnerAddresses Array of owner addresses for the Guardian Safe
    /// @param guardianThreshold Required signatures threshold for Guardian Safe
    /// @param adminOwnerAddresses Array of owner addresses for the Admin Safe
    /// @param adminThreshold Required signatures threshold for Admin Safe
    /// @return safes Struct containing deployed Guardian and Admin Safe addresses
    function _deploySafeMultisigs(
        SafeInfrastructure memory safeInfra,
        address[] memory guardianOwnerAddresses,
        uint256 guardianThreshold,
        address[] memory adminOwnerAddresses,
        uint256 adminThreshold
    ) internal returns (SafeMultisigs memory safes) {
        Logger.logSection("Safe Multisigs");

        // Get expected addresses from deployment.toml
        address expectedGuardianSafe = getExpectedGuardianSafeAddress();
        address expectedAdminSafe = getExpectedAdminSafeAddress();

        // Deploy Guardian Safe
        safes.guardianSafeAddress = _deploySafeMultisig({
            safeInfra: safeInfra,
            ownerAddresses: guardianOwnerAddresses,
            threshold: guardianThreshold,
            salt: GUARDIAN_SAFE_SALT,
            expectedAddress: expectedGuardianSafe,
            name: "Guardian Safe"
        });

        // Deploy Admin Safe
        safes.adminSafeAddress = _deploySafeMultisig({
            safeInfra: safeInfra,
            ownerAddresses: adminOwnerAddresses,
            threshold: adminThreshold,
            salt: ADMIN_SAFE_SALT,
            expectedAddress: expectedAdminSafe,
            name: "Admin Safe"
        });
    }

    /// @dev Deploys a Safe multisig wallet using SafeProxyFactory
    /// @param safeInfra Safe infrastructure addresses needed for Safe deployment
    /// @param ownerAddresses Array of owner addresses for the Safe
    /// @param threshold Required number of signatures for transactions
    /// @param salt Salt used for deterministic address computation
    /// @param expectedAddress Expected address from deployment.toml
    /// @param name Human-readable name for logging purposes
    /// @return safeAddress Address of the deployed Safe proxy
    function _deploySafeMultisig(
        SafeInfrastructure memory safeInfra,
        address[] memory ownerAddresses,
        uint256 threshold,
        bytes32 salt,
        address expectedAddress,
        string memory name
    ) internal returns (address safeAddress) {
        // Check if already deployed at expected address
        if (Create2Utils.isContractDeployedAtAddress(expectedAddress)) {
            Logger.logDeploymentSkipped(name, expectedAddress);
            return expectedAddress;
        }

        // Encode the initializer for Safe.setup() (inherited by SafeL2)
        // Safe.setup signature:
        //   setup(address[] calldata _owners, uint256 _threshold, address to, bytes calldata data,
        //         address fallbackHandler, address paymentToken, uint256 payment, address payable paymentReceiver)
        bytes memory initializer = abi.encodeWithSelector(
            Safe.setup.selector,
            ownerAddresses, // _owners
            threshold, // _threshold
            address(0), // to - no delegate call
            "", // data - no delegate call data
            safeInfra.fallbackHandlerAddress, // fallbackHandler
            address(0), // paymentToken - ETH
            0, // payment - no payment
            address(0) // paymentReceiver
        );

        // Compute the salt nonce
        uint256 saltNonce = uint256(salt);

        // Deploy the Safe using SafeProxyFactory.createProxyWithNonce
        safeAddress = address(
            SafeProxyFactory(safeInfra.proxyFactoryAddress)
                .createProxyWithNonce(safeInfra.singletonAddress, initializer, saltNonce)
        );
        Logger.logDeployed(name, safeAddress);

        // Verify deployment matches expected address from deployment.toml
        require(safeAddress == expectedAddress, "Safe deployed at unexpected address - check deployment.toml");
    }

    /**
     * @notice Computes and displays expected Safe multisig addresses for a specific variant without deploying
     * @dev Use this to preview addresses before deployment. Does not require RPC connection.
     *      Infrastructure addresses should be obtained from DeploySafeInfrastructure.computeAddresses().
     * @param singletonAddress Address of the SafeL2 singleton (master copy)
     * @param proxyFactoryAddress Address of the SafeProxyFactory
     * @param fallbackHandlerAddress Address of the CompatibilityFallbackHandler
     * @param safeVariant The Safe configuration variant to use ("prod" or "nonprod")
     */
    function computeAddresses(
        address singletonAddress,
        address proxyFactoryAddress,
        address fallbackHandlerAddress,
        string calldata safeVariant
    ) external {
        // Validate the safeVariant
        bytes32 variantHash = keccak256(bytes(safeVariant));
        require(
            variantHash == keccak256(bytes("prod")) || variantHash == keccak256(bytes("nonprod")),
            "Invalid safeVariant - must be 'prod' or 'nonprod'"
        );

        // Get the Guardian Safe configuration for the specified variant
        (address[] memory guardianOwnerAddresses, uint256 guardianThreshold) = getGuardianSafeConfig(safeVariant);

        // Get the Admin Safe configuration for the specified variant
        (address[] memory adminOwnerAddresses, uint256 adminThreshold) = getAdminSafeConfig(safeVariant);

        // Log header
        Logger.logBoxHeader("Computed Safe Multisig Addresses");
        Logger.logKeyValue("Safe Variant", safeVariant);
        Logger.logKeyValue("Singleton", singletonAddress);
        Logger.logKeyValue("Proxy Factory", proxyFactoryAddress);
        Logger.logKeyValue("Fallback Handler", fallbackHandlerAddress);
        Logger.logEmptyLine();
        Logger.logSection("Safe Multisigs");

        // Compute Guardian Safe address
        address guardianSafeAddress = _computeSafeMultisigAddress({
            singletonAddress: singletonAddress,
            proxyFactoryAddress: proxyFactoryAddress,
            fallbackHandlerAddress: fallbackHandlerAddress,
            ownerAddresses: guardianOwnerAddresses,
            threshold: guardianThreshold,
            salt: GUARDIAN_SAFE_SALT
        });
        Logger.logKeyValue("Guardian Safe", guardianSafeAddress);

        // Compute Admin Safe address
        address adminSafeAddress = _computeSafeMultisigAddress({
            singletonAddress: singletonAddress,
            proxyFactoryAddress: proxyFactoryAddress,
            fallbackHandlerAddress: fallbackHandlerAddress,
            ownerAddresses: adminOwnerAddresses,
            threshold: adminThreshold,
            salt: ADMIN_SAFE_SALT
        });
        Logger.logKeyValue("Admin Safe", adminSafeAddress);

        // Log footer
        Logger.logBoxFooter();
    }

    /// @dev Computes a Safe multisig address without deploying
    /// @param singletonAddress Address of the SafeL2 singleton (master copy)
    /// @param proxyFactoryAddress Address of the SafeProxyFactory
    /// @param fallbackHandlerAddress Address of the CompatibilityFallbackHandler
    /// @param ownerAddresses Array of owner addresses for the Safe
    /// @param threshold Required number of signatures for transactions
    /// @param salt Salt used for deterministic address computation
    /// @return safeAddress Computed address of the Safe proxy
    function _computeSafeMultisigAddress(
        address singletonAddress,
        address proxyFactoryAddress,
        address fallbackHandlerAddress,
        address[] memory ownerAddresses,
        uint256 threshold,
        bytes32 salt
    ) internal pure returns (address safeAddress) {
        // Encode the initializer for Safe.setup() (inherited by SafeL2)
        bytes memory initializer = abi.encodeWithSelector(
            Safe.setup.selector,
            ownerAddresses, // _owners
            threshold, // _threshold
            address(0), // to - no delegate call
            "", // data - no delegate call data
            fallbackHandlerAddress, // fallbackHandler
            address(0), // paymentToken - ETH
            0, // payment - no payment
            address(0) // paymentReceiver
        );

        // Compute the salt nonce
        uint256 saltNonce = uint256(salt);

        // Compute expected address using SafeProxyFactory's CREATE2 formula
        // SafeProxyFactory computes salt as: keccak256(abi.encodePacked(keccak256(initializer), saltNonce))
        bytes32 computedSalt = keccak256(abi.encodePacked(keccak256(initializer), saltNonce));

        // Compute init code hash: proxyCreationCode + singleton address (as uint256)
        // This matches SafeProxyFactory.deployProxy() which does:
        // bytes memory deploymentData = abi.encodePacked(type(SafeProxy).creationCode,
        // uint256(uint160(_singleton)));
        bytes memory proxyCreationCode = type(SafeProxy).creationCode;
        bytes32 initCodeHash = keccak256(abi.encodePacked(proxyCreationCode, uint256(uint160(singletonAddress))));

        // Use our custom CREATE2 address computation (0.7.x compatible)
        safeAddress = Create2Utils.computeCreate2Address(computedSalt, initCodeHash, proxyFactoryAddress);
    }

    /// @dev Logs all deployed contract addresses in a formatted summary
    /// @param safes Deployed Safe multisig addresses
    function _logDeployedAddresses(SafeMultisigs memory safes) internal pure {
        Logger.logBoxHeader(unicode"✅ Deployed Safe Multisig Addresses");
        Logger.logKeyValue("Guardian Safe", safes.guardianSafeAddress);
        Logger.logKeyValue("Admin Safe", safes.adminSafeAddress);
        Logger.logBoxFooter();
    }
}
