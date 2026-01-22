// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {PlatformLibraries} from "script/libraries/Types.sol";

/**
 * @title DeploymentConfig
 * @notice Configuration constants for deterministic contract deployment
 * @dev Contains pre-defined salts following ERC-7201 naming convention and known factory addresses
 * @author Den Technologies Inc
 */
library DeploymentConfig {
    // ==================== Hardcoded Salts ====================
    // These are the hardcoded salts for deploying contracts and linked-libraries via CREATE2 to achieve deterministic
    // addresses. These salts are not expected to change, so they are hardcoded in the library.
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

    // ==================== Hardcoded CREATE2 Factory and Deployer Addresses =====================
    // These are the hardcoded addresses for the CREATE2 factories that are used to deploy the platform contracts.
    // These addresses are not expected to change, so they are hardcoded in the library.
    //
    // IMPORTANT: These addresses must be updated if the CREATE2 factory or deployer addresses change.
    // ==============================================================================
    /// @dev Arachnid Deterministic Deployment Proxy address (deployed on most EVM chains)
    address internal constant ARACHNID_CREATE2_FACTORY_ADDRESS = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// @dev Production Den Singleton Factory deployer address (must maintain nonce 0)
    ///      TODO: Fill in after deploying Den Singleton Factory from PROD_DEN_FACTORY_DEPLOYER_ADDRESS
    address internal constant PROD_DEN_FACTORY_DEPLOYER_ADDRESS = address(0);

    /// @dev Expected Den Singleton Factory address when deployed from PROD_DEN_FACTORY_DEPLOYER_ADDRESS at nonce 0
    ///      TODO: Fill in after deploying Den Singleton Factory from PROD_DEN_FACTORY_DEPLOYER_ADDRESS at nonce 0
    address internal constant PROD_DEN_SINGLETON_FACTORY_ADDRESS = address(0);

    /// @dev Non-production Den Singleton Factory deployer address
    address internal constant NON_PROD_DEN_FACTORY_DEPLOYER_ADDRESS = 0x22002e8661A780d61EF4c86F4a9fFa843A6fea20;

    /// @dev Expected Den Singleton Factory address for non-production deployments
    address internal constant NON_PROD_DEN_SINGLETON_FACTORY_ADDRESS = 0xC6123B1C95825f98939C76c8cBCEFDBB1C0D94db;

    // ==================== Hardcoded Library Paths ====================
    // These are the hardcoded paths for the platform libraries that are used when deploying contracts that
    // link to the platform libraries. These paths are used to print the foundry --libraries flag that should
    // be used when running DeployContracts.s.sol.
    //
    // These paths are not expected to change, so they are hardcoded.
    //
    // IMPORTANT: These paths must be updated if library paths change.
    // ==============================================================================

    /// @dev Library path for LibOrganizationPolicy (used when deploying libraries to print the
    ///      foundry --libraries flag that should be used when running DeployContracts.s.sol)
    string internal constant LIB_ORG_POLICY_PATH =
        "src/organization/libraries/LibOrganizationPolicy.sol:LibOrganizationPolicy";

    /// @dev Library path for LibOrganizationAdmin (used when deploying libraries to print the
    ///      foundry --libraries flag that should be used when running DeployContracts.s.sol)
    string internal constant LIB_ORG_ADMIN_PATH =
        "src/organization/libraries/LibOrganizationAdmin.sol:LibOrganizationAdmin";

    /// @dev Library path for LibOrganizationInitialization (used when deploying libraries to print the
    ///      foundry --libraries flag that should be used when running DeployContracts.s.sol)
    string internal constant LIB_ORG_INIT_PATH =
        "src/organization/libraries/LibOrganizationInitialization.sol:LibOrganizationInitialization";

    /// @dev Library path for LibOrganizationAccountSignature (used when deploying libraries to print the
    ///      foundry --libraries flag that should be used when running DeployContracts.s.sol)
    string internal constant LIB_ORG_ACCOUNT_SIG_PATH =
        "src/organization/libraries/LibOrganizationAccountSignature.sol:LibOrganizationAccountSignature";

    // ==================== Hardcoded Library Addresses ====================
    // These are the expected deployment addresses for platform libraries when deployed via CREATE2
    // using the specified factory. Addresses differ based on which factory is used because the
    // factory address is part of the CREATE2 address computation.
    //
    // IMPORTANT: These addresses must be updated if library source code or salts change.
    // ==============================================================================

    /// @dev Expected library addresses when deployed via Arachnid Deterministic Deployment Proxy
    ///      TODO: Update these addresses after making changes to library source code and deploying
    ///      libraries via arachnid Deterministic Deployment Proxy
    address internal constant ARACHNID_LIB_ORG_POLICY_ADDRESS = 0x0c39cb4F67AA70D53ceE37d4c88f11ffDb07E314;
    address internal constant ARACHNID_LIB_ORG_ADMIN_ADDRESS = 0x744CaFa607273AF5664073d05BE066C6bDbf8201;
    address internal constant ARACHNID_LIB_ORG_INIT_ADDRESS = 0x95A9CDA2a67E48b154d8EFa3B147f31eC6e8147E;
    address internal constant ARACHNID_LIB_ORG_ACCOUNT_SIG_ADDRESS = 0x6A6709A2c898E719A6Ee7635a3963122059655eB;

    /// @dev Expected library addresses when deployed via Production Den Singleton Factory
    ///      TODO: Fill in these addresses after deploying libraries via prod Den Singleton Factory
    ///      TODO: Update these addresses after making changes to library source code and deploying
    ///      libraries via prod Den Singleton Factory
    address internal constant PROD_DEN_FACTORY_LIB_ORG_POLICY_ADDRESS = address(0);
    address internal constant PROD_DEN_FACTORY_LIB_ORG_ADMIN_ADDRESS = address(0);
    address internal constant PROD_DEN_FACTORY_LIB_ORG_INIT_ADDRESS = address(0);
    address internal constant PROD_DEN_FACTORY_LIB_ORG_ACCOUNT_SIG_ADDRESS = address(0);

    /// @dev Expected library addresses when deployed via Non-Production Den Singleton Factory
    ///      TODO: Update these addresses after making changes to library source code and deploying
    ///      libraries via non-prod Den Singleton Factory
    address internal constant NON_PROD_DEN_FACTORY_LIB_ORG_POLICY_ADDRESS = 0x85c8b8410F0feeFd157496245c37d89F33985cC0;
    address internal constant NON_PROD_DEN_FACTORY_LIB_ORG_ADMIN_ADDRESS = 0xCAE149fD735Cc65290e737BF06855Bba119b6082;
    address internal constant NON_PROD_DEN_FACTORY_LIB_ORG_INIT_ADDRESS = 0x384803ADc053682c7f42270De5DF50d37c243913;
    address internal constant NON_PROD_DEN_FACTORY_LIB_ORG_ACCOUNT_SIG_ADDRESS =
        0xFcBDb3e95De055ac3BAedADA90894E5624Af1162;

    // ==================== Hardcoded Guardian Safe Multisig Configurations =====================
    // These are the hardcoded multisig configurations for the Guardian Safe and Deployer Safe.
    // that are used to deploy the platform contracts. These configurations are not expected to change,
    // so they are hardcoded in the library.
    //
    // IMPORTANT: These configurations must be updated if the Guardian Safe or Deployer Safe configurations change.
    // ==============================================================================

    /// @dev Production Guardian Safe owner addresses
    address internal constant PROD_GUARDIAN_SAFE_OWNER_1 = address(0x1111111111111111111111111111111111111111);
    address internal constant PROD_GUARDIAN_SAFE_OWNER_2 = address(0x2222222222222222222222222222222222222222);

    /// @dev Production Guardian Safe signature threshold
    uint256 internal constant PROD_GUARDIAN_SAFE_THRESHOLD = 2;

    /// @dev Production Deployer Safe owner addresses
    address internal constant PROD_DEPLOYER_SAFE_OWNER_1 = address(0x3333333333333333333333333333333333333333);
    address internal constant PROD_DEPLOYER_SAFE_OWNER_2 = address(0x4444444444444444444444444444444444444444);
    address internal constant PROD_DEPLOYER_SAFE_OWNER_3 = address(0x5555555555555555555555555555555555555555);

    /// @dev Production Deployer Safe signature threshold
    uint256 internal constant PROD_DEPLOYER_SAFE_THRESHOLD = 2;

    /// @dev Non-production Guardian Safe owner addresses (placeholder - replace before deploying)
    address internal constant NON_PROD_GUARDIAN_SAFE_OWNER_1 = address(0xFdA43C00bA0589bb10Bc3b75c3D8E1046e73E328);

    /// @dev Non-production Guardian Safe signature threshold
    uint256 internal constant NON_PROD_GUARDIAN_SAFE_THRESHOLD = 1;

    /// @dev Non-production Deployer Safe owner addresses (placeholder - replace before deploying)
    address internal constant NON_PROD_DEPLOYER_SAFE_OWNER_1 = address(0x901CAb5Fdb93571F0f6Cd6D643F8b2532f00d2A3);

    /// @dev Non-production Deployer Safe signature threshold
    uint256 internal constant NON_PROD_DEPLOYER_SAFE_THRESHOLD = 1;

    // ==================== Helper Functions ====================
    // These are the helper functions that are used to determine which configurations to use based on the chain ID.
    // ==============================================================================

    /// @dev Returns true if the given chain ID is a production network
    /// @param chainId The chain ID to check
    /// @return True if the chain is a production network
    function isProductionChain(uint256 chainId) internal pure returns (bool) {
        return chainId == 1 // Ethereum Mainnet
            || chainId == 10 // Optimism
            || chainId == 56 // BNB Smart Chain
            || chainId == 137 // Polygon
            || chainId == 8453 // Base
            || chainId == 42_161 // Arbitrum One
            || chainId == 43_114; // Avalanche C-Chain
    }

    /// @dev Returns Guardian Safe configuration based on chain ID
    /// @param chainId The target chain ID
    /// @return ownerAddresses Array of owner addresses for the Guardian Safe
    /// @return threshold Required number of signatures
    function getGuardianSafeConfig(uint256 chainId)
        internal
        pure
        returns (address[] memory ownerAddresses, uint256 threshold)
    {
        // Case: Production chain
        if (isProductionChain(chainId)) {
            ownerAddresses = new address[](2);
            ownerAddresses[0] = PROD_GUARDIAN_SAFE_OWNER_1;
            ownerAddresses[1] = PROD_GUARDIAN_SAFE_OWNER_2;
            threshold = PROD_GUARDIAN_SAFE_THRESHOLD;
            return (ownerAddresses, threshold);
        }

        // Case: Non-production chain
        ownerAddresses = new address[](1);
        ownerAddresses[0] = NON_PROD_GUARDIAN_SAFE_OWNER_1;
        threshold = NON_PROD_GUARDIAN_SAFE_THRESHOLD;
        return (ownerAddresses, threshold);
    }

    /// @dev Returns Deployer Safe configuration based on chain ID
    /// @param chainId The target chain ID
    /// @return ownerAddresses Array of owner addresses for the Deployer Safe
    /// @return threshold Required number of signatures
    function getDeployerSafeConfig(uint256 chainId)
        internal
        pure
        returns (address[] memory ownerAddresses, uint256 threshold)
    {
        // Case: Production chain
        if (isProductionChain(chainId)) {
            ownerAddresses = new address[](3);
            ownerAddresses[0] = PROD_DEPLOYER_SAFE_OWNER_1;
            ownerAddresses[1] = PROD_DEPLOYER_SAFE_OWNER_2;
            ownerAddresses[2] = PROD_DEPLOYER_SAFE_OWNER_3;
            threshold = PROD_DEPLOYER_SAFE_THRESHOLD;
            return (ownerAddresses, threshold);
        }

        // Case: Non-production chain
        ownerAddresses = new address[](1);
        ownerAddresses[0] = NON_PROD_DEPLOYER_SAFE_OWNER_1;
        threshold = NON_PROD_DEPLOYER_SAFE_THRESHOLD;
        return (ownerAddresses, threshold);
    }

    /// @dev Returns expected library addresses based on which CREATE2 factory was used for deployment
    /// @param factoryAddress The CREATE2 factory address used to deploy the libraries
    /// @return libs Struct containing expected library addresses
    function getExpectedLibraryAddresses(address factoryAddress) internal pure returns (PlatformLibraries memory libs) {
        // Case: Arachnid Deterministic Deployment Proxy
        if (factoryAddress == ARACHNID_CREATE2_FACTORY_ADDRESS) {
            libs = PlatformLibraries({
                policyAddress: ARACHNID_LIB_ORG_POLICY_ADDRESS,
                adminAddress: ARACHNID_LIB_ORG_ADMIN_ADDRESS,
                initializationAddress: ARACHNID_LIB_ORG_INIT_ADDRESS,
                accountSignatureAddress: ARACHNID_LIB_ORG_ACCOUNT_SIG_ADDRESS
            });
            return libs;
        }

        // Case: Production Den Singleton Factory
        if (factoryAddress == PROD_DEN_SINGLETON_FACTORY_ADDRESS) {
            libs = PlatformLibraries({
                policyAddress: PROD_DEN_FACTORY_LIB_ORG_POLICY_ADDRESS,
                adminAddress: PROD_DEN_FACTORY_LIB_ORG_ADMIN_ADDRESS,
                initializationAddress: PROD_DEN_FACTORY_LIB_ORG_INIT_ADDRESS,
                accountSignatureAddress: PROD_DEN_FACTORY_LIB_ORG_ACCOUNT_SIG_ADDRESS
            });
            return libs;
        }

        // Case: Non-Production Den Singleton Factory
        if (factoryAddress == NON_PROD_DEN_SINGLETON_FACTORY_ADDRESS) {
            libs = PlatformLibraries({
                policyAddress: NON_PROD_DEN_FACTORY_LIB_ORG_POLICY_ADDRESS,
                adminAddress: NON_PROD_DEN_FACTORY_LIB_ORG_ADMIN_ADDRESS,
                initializationAddress: NON_PROD_DEN_FACTORY_LIB_ORG_INIT_ADDRESS,
                accountSignatureAddress: NON_PROD_DEN_FACTORY_LIB_ORG_ACCOUNT_SIG_ADDRESS
            });
            return libs;
        }

        revert("Unknown factory - no expected library addresses");
    }
}
