// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.7.6;

// Safe 1.3.0 imports
import {GnosisSafe} from "@safe/GnosisSafe.sol";
import {GnosisSafeProxy} from "@safe/proxies/GnosisSafeProxy.sol";
import {GnosisSafeProxyFactory} from "@safe/proxies/GnosisSafeProxyFactory.sol";

// Shared script utilities
import {BaseDeployScript} from "script/base/BaseDeployScript.sol";
import {Create2Utils} from "script/libraries/Create2Utils.sol";
import {Logger} from "script/libraries/Logger.sol";
import {SafeInfrastructure} from "script/libraries/Types.sol";

/**
 * @title DeploySafeMultisigs
 * @notice Deploys Safe multisig wallets (Guardian and Deployer Safes)
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
 *      - Deployer Safe (deployment operations multisig)
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
        address deployerSafeAddress;
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
        (address[] memory deployerOwnerAddresses, uint256 deployerThreshold) = getDeployerSafeConfig(variant);

        // Get Safe infrastructure addresses from deployment.toml
        SafeInfrastructure memory safeInfra = getExpectedSafeInfrastructureAddresses();

        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy our two Safe Multisigs (Deployer and Guardian Safes)
        SafeMultisigs memory safes = _deploySafeMultisigs({
            safeInfra: safeInfra,
            guardianOwnerAddresses: guardianOwnerAddresses,
            guardianThreshold: guardianThreshold,
            deployerOwnerAddresses: deployerOwnerAddresses,
            deployerThreshold: deployerThreshold
        });

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Log deployed addresses
        _logDeployedAddresses(safes);
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
        safes.guardianSafeAddress = _deploySafeMultisig({
            safeInfra: safeInfra,
            ownerAddresses: guardianOwnerAddresses,
            threshold: guardianThreshold,
            salt: GUARDIAN_SAFE_SALT,
            name: "Guardian Safe"
        });

        // Deploy Deployer Safe
        safes.deployerSafeAddress = _deploySafeMultisig({
            safeInfra: safeInfra,
            ownerAddresses: deployerOwnerAddresses,
            threshold: deployerThreshold,
            salt: DEPLOYER_SAFE_SALT,
            name: "Deployer Safe"
        });
    }

    /// @dev Deploys a Safe multisig wallet using GnosisSafeProxyFactory
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
        // Encode the initializer for GnosisSafe.setup()
        // GnosisSafe.setup signature:
        //   setup(address[] calldata _owners, uint256 _threshold, address to, bytes calldata data,
        //         address fallbackHandler, address paymentToken, uint256 payment, address payable paymentReceiver)
        bytes memory initializer = abi.encodeWithSelector(
            GnosisSafe.setup.selector,
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

        // Compute expected address using GnosisSafeProxyFactory's CREATE2 formula
        safeAddress = _computeSafeProxyAddress({
            singletonAddress: safeInfra.singletonAddress,
            proxyFactoryAddress: safeInfra.proxyFactoryAddress,
            initializer: initializer,
            saltNonce: saltNonce
        });

        // Check if already deployed
        if (Create2Utils.isContractDeployedAtAddress(safeAddress)) {
            Logger.logDeploymentSkipped(name, safeAddress);
            return safeAddress;
        }

        // Deploy the Safe using GnosisSafeProxyFactory.createProxyWithNonce
        address deployedAtAddress = address(
            GnosisSafeProxyFactory(safeInfra.proxyFactoryAddress)
                .createProxyWithNonce(safeInfra.singletonAddress, initializer, saltNonce)
        );
        Logger.logDeployed(name, deployedAtAddress);

        // Verify deployment matches expected address
        require(deployedAtAddress == safeAddress, "Safe deployed at unexpected address");
    }

    /// @dev Computes the deterministic address of a Safe proxy before deployment
    /// @param singletonAddress Address of the GnosisSafe singleton (master copy)
    /// @param proxyFactoryAddress Address of the GnosisSafeProxyFactory
    /// @param initializer Encoded GnosisSafe.setup() call data
    /// @param saltNonce Nonce used for salt computation
    /// @return The predicted Safe proxy address
    function _computeSafeProxyAddress(
        address singletonAddress,
        address proxyFactoryAddress,
        bytes memory initializer,
        uint256 saltNonce
    ) private pure returns (address) {
        // GnosisSafeProxyFactory computes salt as: keccak256(abi.encodePacked(keccak256(initializer), saltNonce))
        bytes32 computedSalt = keccak256(abi.encodePacked(keccak256(initializer), saltNonce));

        // Compute init code hash: proxyCreationCode + singleton address (as uint256)
        // This matches GnosisSafeProxyFactory.deployProxyWithNonce() which does:
        // bytes memory deploymentData = abi.encodePacked(type(GnosisSafeProxy).creationCode,
        // uint256(uint160(_singleton)));
        // Using compile-time proxy creation code to avoid requiring the factory to be deployed
        bytes memory proxyCreationCode = type(GnosisSafeProxy).creationCode;
        bytes32 initCodeHash = keccak256(abi.encodePacked(proxyCreationCode, uint256(uint160(singletonAddress))));

        // Use our custom CREATE2 address computation (0.7.x compatible)
        return Create2Utils.computeCreate2Address(computedSalt, initCodeHash, proxyFactoryAddress);
    }

    /**
     * @notice Computes and displays expected Safe multisig addresses for a specific variant without deploying
     * @dev Use this to preview addresses before deployment. Does not require RPC connection.
     *      Infrastructure addresses should be obtained from DeploySafeInfrastructure.computeAddresses().
     * @param singletonAddress Address of the GnosisSafe singleton (master copy)
     * @param proxyFactoryAddress Address of the GnosisSafeProxyFactory
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

        // Get the Deployer Safe configuration for the specified variant
        (address[] memory deployerOwnerAddresses, uint256 deployerThreshold) = getDeployerSafeConfig(safeVariant);

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

        // Compute Deployer Safe address
        address deployerSafeAddress = _computeSafeMultisigAddress({
            singletonAddress: singletonAddress,
            proxyFactoryAddress: proxyFactoryAddress,
            fallbackHandlerAddress: fallbackHandlerAddress,
            ownerAddresses: deployerOwnerAddresses,
            threshold: deployerThreshold,
            salt: DEPLOYER_SAFE_SALT
        });
        Logger.logKeyValue("Deployer Safe", deployerSafeAddress);

        // Log footer
        Logger.logBoxFooter();
    }

    /// @dev Computes a Safe multisig address without deploying
    /// @param singletonAddress Address of the GnosisSafe singleton (master copy)
    /// @param proxyFactoryAddress Address of the GnosisSafeProxyFactory
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
        // Encode the initializer for GnosisSafe.setup()
        bytes memory initializer = abi.encodeWithSelector(
            GnosisSafe.setup.selector,
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

        // Compute expected address using GnosisSafeProxyFactory's CREATE2 formula
        safeAddress = _computeSafeProxyAddress({
            singletonAddress: singletonAddress,
            proxyFactoryAddress: proxyFactoryAddress,
            initializer: initializer,
            saltNonce: saltNonce
        });
    }

    /// @dev Logs all deployed contract addresses in a formatted summary
    /// @param safes Deployed Safe multisig addresses
    function _logDeployedAddresses(SafeMultisigs memory safes) internal pure {
        Logger.logBoxHeader(unicode"✅ Deployed Safe Multisig Addresses");
        Logger.logKeyValue("Guardian Safe", safes.guardianSafeAddress);
        Logger.logKeyValue("Deployer Safe", safes.deployerSafeAddress);
        Logger.logBoxFooter();
    }
}
