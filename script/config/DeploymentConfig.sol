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
    address internal constant ARACHNID_CREATE2_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// @dev Safe Singleton Factory address (deterministic across all chains where deployed)
    address internal constant SAFE_SINGLETON_FACTORY = 0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7;

    /// @dev Safe Singleton Factory deployer address (for nonce-0 deployment)
    address internal constant SAFE_FACTORY_DEPLOYER = 0xE1CB04A0fA36DdD16a06ea828007E35e1a3cBC37;

    // ============================================================
    // External Dependencies (Safe contracts) - "den.external.*" namespace
    // ============================================================

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

    // ============================================================
    // Safe Multisigs for Privileged Roles - "den.mls-wallet.safe.*" namespace
    // ============================================================

    /// @dev Salt for Guardian Safe (used as Organization guardian)
    bytes32 internal constant GUARDIAN_SAFE_SALT = keccak256("den.mls-wallet.safe.guardian.v1");

    /// @dev Salt for Deployer Safe (used as factory deployer)
    bytes32 internal constant DEPLOYER_SAFE_SALT = keccak256("den.mls-wallet.safe.deployer.v1");

    // ============================================================
    // Organization Libraries - "den.mls-wallet.organization.lib.*" namespace
    // These are libraries with public functions that get compiled as separate
    // contracts and must be deployed via CREATE2 for deterministic addresses.
    // ============================================================

    /// @dev Salt for LibOrganizationPolicy library deployment
    bytes32 internal constant LIB_ORG_POLICY_SALT = keccak256("den.mls-wallet.organization.lib.policy.v1");

    /// @dev Salt for LibOrganizationAdmin library deployment
    bytes32 internal constant LIB_ORG_ADMIN_SALT = keccak256("den.mls-wallet.organization.lib.admin.v1");

    /// @dev Salt for LibOrganizationInitialization library deployment
    bytes32 internal constant LIB_ORG_INIT_SALT = keccak256("den.mls-wallet.organization.lib.initialization.v1");

    /// @dev Salt for LibOrganizationAccountSignature library deployment
    bytes32 internal constant LIB_ORG_ACCOUNT_SIG_SALT =
        keccak256("den.mls-wallet.organization.lib.account-signature.v1");

    // ============================================================
    // Library File Paths (for --libraries flag generation)
    // ============================================================

    /// @dev Library paths for foundry --libraries flag
    string internal constant LIB_ORG_POLICY_PATH =
        "src/organization/libraries/LibOrganizationPolicy.sol:LibOrganizationPolicy";
    string internal constant LIB_ORG_ADMIN_PATH =
        "src/organization/libraries/LibOrganizationAdmin.sol:LibOrganizationAdmin";
    string internal constant LIB_ORG_INIT_PATH =
        "src/organization/libraries/LibOrganizationInitialization.sol:LibOrganizationInitialization";
    string internal constant LIB_ORG_ACCOUNT_SIG_PATH =
        "src/organization/libraries/LibOrganizationAccountSignature.sol:LibOrganizationAccountSignature";

    // ============================================================
    // Implementation Contracts - "den.mls-wallet.<domain>.implementation" namespace
    // ============================================================

    /// @dev Salt for OrganizationImplementation deployment
    bytes32 internal constant ORG_IMPL_SALT = keccak256("den.mls-wallet.organization.implementation.v1");

    /// @dev Salt for AccountImplementation deployment
    bytes32 internal constant ACCOUNT_IMPL_SALT = keccak256("den.mls-wallet.account.implementation.v1");

    /// @dev Salt for ImplementationWhitelistImplementation deployment
    bytes32 internal constant WHITELIST_IMPL_SALT = keccak256("den.mls-wallet.whitelist.implementation.v1");

    // ============================================================
    // Factory Contracts - "den.mls-wallet.<domain>.factory" namespace
    // ============================================================

    /// @dev Salt for OrganizationFactory deployment
    bytes32 internal constant ORG_FACTORY_SALT = keccak256("den.mls-wallet.organization.factory.v1");

    /// @dev Salt for ImplementationWhitelistFactory deployment
    bytes32 internal constant WHITELIST_FACTORY_SALT = keccak256("den.mls-wallet.whitelist.factory.v1");

    // ============================================================
    // Proxy Contracts - "den.mls-wallet.<domain>.proxy" namespace
    // ============================================================

    /// @dev Salt for ImplementationWhitelistProxy deployment (via factory)
    bytes32 internal constant WHITELIST_PROXY_SALT = keccak256("den.mls-wallet.whitelist.proxy.v1");

    /// @dev Returns the appropriate CREATE2 factory address based on preference
    /// @param preferSafe If true, returns Safe Singleton Factory; otherwise returns Arachnid
    /// @return factory The factory address to use
    function getCreate2Factory(bool preferSafe) internal pure returns (address factory) {
        return preferSafe ? SAFE_SINGLETON_FACTORY : ARACHNID_CREATE2_FACTORY;
    }
}
