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

    /// @dev Returns the production Guardian Safe owner addresses
    /// @return owners Array of owner addresses
    function getProdGuardianSafeOwners() internal pure returns (address[] memory owners) {
        owners = new address[](2);
        owners[0] = PROD_GUARDIAN_SAFE_OWNER_1;
        owners[1] = PROD_GUARDIAN_SAFE_OWNER_2;
    }

    /// @dev Returns the production Deployer Safe owner addresses
    /// @return owners Array of owner addresses
    function getProdDeployerSafeOwners() internal pure returns (address[] memory owners) {
        owners = new address[](3);
        owners[0] = PROD_DEPLOYER_SAFE_OWNER_1;
        owners[1] = PROD_DEPLOYER_SAFE_OWNER_2;
        owners[2] = PROD_DEPLOYER_SAFE_OWNER_3;
    }
}
