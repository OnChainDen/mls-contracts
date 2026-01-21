// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title DeploymentConfig
 * @notice Configuration constants for deterministic contract deployment
 * @dev Contains pre-defined salts following ERC-7201 naming convention and known factory addresses
 * @author Den Technologies Inc
 */
library DeploymentConfig {
    /// @dev Arachnid Deterministic Deployment Proxy address (deployed on most EVM chains)
    address internal constant ARACHNID_CREATE2_FACTORY_ADDRESS = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// @dev Safe Singleton Factory address (deterministic across all chains where deployed)
    address internal constant SAFE_SINGLETON_FACTORY_ADDRESS = 0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7;

    /// @dev Production Safe Singleton Factory deployer address (must maintain nonce 0)
    address internal constant PROD_SAFE_FACTORY_DEPLOYER_ADDRESS = 0xE1CB04A0fA36DdD16a06ea828007E35e1a3cBC37;

    /// @dev Expected Safe Singleton Factory address when deployed from PROD_SAFE_FACTORY_DEPLOYER_ADDRESS at nonce 0
    address internal constant PROD_EXPECTED_SAFE_FACTORY_ADDRESS = 0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7;

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
        if (isProductionChain(chainId)) {
            ownerAddresses = new address[](2);
            ownerAddresses[0] = PROD_GUARDIAN_SAFE_OWNER_1;
            ownerAddresses[1] = PROD_GUARDIAN_SAFE_OWNER_2;
            threshold = PROD_GUARDIAN_SAFE_THRESHOLD;
        } else {
            ownerAddresses = new address[](1);
            ownerAddresses[0] = NON_PROD_GUARDIAN_SAFE_OWNER_1;
            threshold = NON_PROD_GUARDIAN_SAFE_THRESHOLD;
        }
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
        if (isProductionChain(chainId)) {
            ownerAddresses = new address[](3);
            ownerAddresses[0] = PROD_DEPLOYER_SAFE_OWNER_1;
            ownerAddresses[1] = PROD_DEPLOYER_SAFE_OWNER_2;
            ownerAddresses[2] = PROD_DEPLOYER_SAFE_OWNER_3;
            threshold = PROD_DEPLOYER_SAFE_THRESHOLD;
        } else {
            ownerAddresses = new address[](1);
            ownerAddresses[0] = NON_PROD_DEPLOYER_SAFE_OWNER_1;
            threshold = NON_PROD_DEPLOYER_SAFE_THRESHOLD;
        }
    }
}
