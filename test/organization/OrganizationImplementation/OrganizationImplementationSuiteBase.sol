// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";
import {OrganizationAdminTestBase} from "test/organization/shared/OrganizationAdminTestBase.sol";
import {
    OrganizationImplementationHarness,
    OrganizationImplementationNonUUPS,
    OrganizationImplementationV2Harness,
    OrganizationImplementationV3Harness,
    OrganizationImplementationWrongUUID,
    UpgradeWhitelistMock
} from "test/organization/shared/OrganizationUpgradeHarnesses.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {ContractType, OperationType} from "types/CommonTypes.sol";

/**
 * @dev Shared setup/helpers for `OrganizationImplementation` upgradeability suites.
 */
abstract contract OrganizationImplementationSuiteBase is OrganizationAdminTestBase {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    OrganizationImplementationHarness internal implementationV1;
    OrganizationImplementationHarness internal organizationProxy;
    OrganizationImplementationV2Harness internal implementationV2;
    OrganizationImplementationV3Harness internal implementationV3;
    OrganizationImplementationWrongUUID internal wrongUuidImplementation;
    OrganizationImplementationNonUUPS internal nonUupsImplementation;
    UpgradeWhitelistMock internal whitelist;

    /**
     * @dev Deploys the baseline V1 organization implementation harness for this suite.
     * @return harness Deployed V1 harness cast to the shared admin-state interface.
     */
    function _deployHarness() internal override returns (OrganizationAdminStateHarness) {
        implementationV1 = new OrganizationImplementationHarness();
        return OrganizationAdminStateHarness(address(implementationV1));
    }

    /**
     * @dev Initializes all upgrade test fixtures, then binds `stateHarness` to a proxy-backed organization instance.
     */
    function setUp() public virtual override {
        super.setUp();

        implementationV2 = new OrganizationImplementationV2Harness();
        implementationV3 = new OrganizationImplementationV3Harness();
        wrongUuidImplementation = new OrganizationImplementationWrongUUID();
        nonUupsImplementation = new OrganizationImplementationNonUUPS();
        whitelist = new UpgradeWhitelistMock();

        // All Organization upgrade tests execute against a proxy so UUPS guards are exercised end-to-end.
        organizationProxy = _deployOrganizationProxy(implementationV1);
        stateHarness = OrganizationAdminStateHarness(address(organizationProxy));
        organizationProxy.setGuardianStorage(GUARDIAN);
        organizationProxy.setUpgradeState(address(whitelist), address(0));
    }

    /**
     * @dev Deploys an ERC1967 proxy that points at `implementationAddress` with no initializer payload.
     * @param implementationAddress Initial implementation used by the newly deployed proxy.
     * @return proxyInstance Proxy cast to the organization implementation harness type.
     */
    function _deployOrganizationProxy(OrganizationImplementationHarness implementationAddress)
        internal
        returns (OrganizationImplementationHarness)
    {
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementationAddress), bytes(""));
        return OrganizationImplementationHarness(payable(address(proxy)));
    }

    /**
     * @dev Sets whitelist status for an organization implementation in the upgrade whitelist mock.
     * @param implementation Implementation address whose organization whitelist status is being updated.
     * @param isWhitelisted True to allow upgrades to `implementation`, false to disallow them.
     */
    function _setOrganizationImplementationWhitelisted(address implementation, bool isWhitelisted) internal {
        whitelist.setImplementationWhitelisted(ContractType.Organization, implementation, isWhitelisted);
    }

    /**
     * @dev Sets whitelist status for an account implementation in the upgrade whitelist mock.
     * @param implementation Implementation address whose account whitelist status is being updated.
     * @param isWhitelisted True to allow upgrades to `implementation`, false to disallow them.
     */
    function _setAccountImplementationWhitelisted(address implementation, bool isWhitelisted) internal {
        whitelist.setImplementationWhitelisted(ContractType.Account, implementation, isWhitelisted);
    }

    /**
     * @dev Configures a single-member/single-admin state with threshold one for upgrade auth tests.
     */
    function _setSingleAdminThresholdOne() internal {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
    }

    /**
     * @dev Builds operation data and matching admin-auth payload for an upgrade with empty migration calldata.
     * @param newImplementation Target implementation address to be authorized for upgrade.
     * @param salt Salt value mixed into nonce derivation for replay protection.
     * @param expiration Expiration timestamp embedded in the authorization payload.
     * @param isApproval True when signatures represent approval, false when they represent rejection.
     * @param privateKeys Private keys used to sign the authorization payload.
     * @return auth Admin authorization parameters ready to pass into upgrade calls.
     * @return operationData ABI-encoded upgrade operation data used for auth and nonce computation.
     */
    function _buildUpgradeAuth(
        address newImplementation,
        uint256 salt,
        uint256 expiration,
        bool isApproval,
        uint256[] memory privateKeys
    ) internal view returns (AdminAuthParams memory auth, bytes memory operationData) {
        return _buildUpgradeAuth({
            newImplementation: newImplementation,
            migrationData: bytes(""),
            salt: salt,
            expiration: expiration,
            isApproval: isApproval,
            privateKeys: privateKeys
        });
    }

    /**
     * @dev Builds operation data and matching admin-auth payload for an upgrade operation.
     * @param newImplementation Target implementation address to be authorized for upgrade.
     * @param migrationData Migration calldata whose hash is bound into the signed operation payload.
     * @param salt Salt value mixed into nonce derivation for replay protection.
     * @param expiration Expiration timestamp embedded in the authorization payload.
     * @param isApproval True when signatures represent approval, false when they represent rejection.
     * @param privateKeys Private keys used to sign the authorization payload.
     * @return auth Admin authorization parameters ready to pass into upgrade calls.
     * @return operationData ABI-encoded upgrade operation data used for auth and nonce computation.
     */
    function _buildUpgradeAuth(
        address newImplementation,
        bytes memory migrationData,
        uint256 salt,
        uint256 expiration,
        bool isApproval,
        uint256[] memory privateKeys
    ) internal view returns (AdminAuthParams memory auth, bytes memory operationData) {
        operationData = _encodeOperationDataForUpgrade(newImplementation, migrationData);
        auth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.Upgrade,
            operationData: operationData,
            isApproval: isApproval,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: privateKeys
        });
    }

    /**
     * @dev Encodes the upgrade operation payload for upgrades with empty migration calldata.
     * @param newImplementation Target implementation address for the upgrade.
     * @return operationData ABI-encoded bytes containing `newImplementation` and `keccak256(bytes(""))`.
     */
    function _encodeOperationDataForUpgrade(address newImplementation) internal pure returns (bytes memory) {
        return _encodeOperationDataForUpgrade(newImplementation, bytes(""));
    }

    /**
     * @dev Encodes the upgrade operation payload expected by nonce and auth builders.
     * @param newImplementation Target implementation address for the upgrade.
     * @param migrationData Migration calldata whose hash is bound into the operation payload.
     * @return operationData ABI-encoded bytes containing `newImplementation` and `keccak256(migrationData)`.
     */
    function _encodeOperationDataForUpgrade(address newImplementation, bytes memory migrationData)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(newImplementation, keccak256(migrationData));
    }

    /**
     * @dev Computes the upgrade nonce for `operationData` and `salt` using the state harness logic.
     * @param operationData ABI-encoded upgrade operation payload.
     * @param salt Salt value included in nonce derivation.
     * @return nonce Nonce used when building upgrade authorization signatures.
     */
    function _computeUpgradeNonce(bytes memory operationData, uint256 salt) internal view returns (uint256) {
        return stateHarness.computeNonce(OperationType.Upgrade, operationData, salt);
    }

    /**
     * @dev Reads the current implementation from an ERC1967 proxy's implementation storage slot.
     * @param proxy Proxy address to inspect.
     * @return implementation Address currently set as the proxy implementation.
     */
    function _readProxyImplementation(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT))));
    }
}
