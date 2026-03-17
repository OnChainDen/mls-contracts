// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IImplementationWhitelist} from "interfaces/IImplementationWhitelist.sol";
import {IOrganization} from "interfaces/IOrganization.sol";
import {
    AccountImplementationVersion1,
    IUUPSOrgEntrypoints,
    IVersionedAccount,
    OrganizationUpgradesCrossFileSuiteBase
} from "test/organization/integration/OrganizationUpgradesCrossFileSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Cross-file invariant-style checks for organization/account upgrade properties.
 */
contract OrganizationUpgradesCrossFileInvariants is OrganizationUpgradesCrossFileSuiteBase {
    /// @dev Verifies invariant that authorized upgrade target is unset outside authorized upgrade execution.
    function test_UPG_CTRL_1__UPG_INV_1__IWC_INV_1__IWC_INV_4_upgradeAuthorizedFlagFalseOutsideExecution() public {
        // Setup: perform successful upgrade with migration helper that requires temporary auth flag.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        bytes memory data = abi.encodeCall(implementationV2.migrationRequireAuthAndSetMarker, (1));
        (AdminAuthParams memory auth,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            migrationData: data,
            salt: 141_300,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        (, address beforeAuthorizedTarget) = organizationProxy.getUpgradeState();
        assertEq(beforeAuthorizedTarget, address(0), "authorized target should start unset");

        vm.prank(GUARDIAN);
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), data, auth);

        // Verify: authorized target resets to zero after execution.
        (, address afterAuthorizedTarget) = organizationProxy.getUpgradeState();
        assertEq(afterAuthorizedTarget, address(0), "authorized target should end unset");
    }

    /// @dev Verifies invariant that Organization upgrades only target whitelisted Organization implementations.
    function test_UPG_CTRL_3__UPG_INV_2__IWC_INV_2_organizationUpgrades_onlyTargetWhitelistedOrganizationImplementations()
        public
    {
        // Setup: valid admin auth for unwhitelisted Organization target.
        _setSingleAdminThresholdOne();
        (AdminAuthParams memory auth,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            salt: 141_301,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: upgrade is rejected while target remains unwhitelisted.
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector, address(implementationV2)
            )
        );
        vm.prank(GUARDIAN);
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), auth);
    }

    /// @dev Verifies invariant that Account upgrades only target whitelisted Account implementations.
    function test_UPG_CTRL_4__UPG_INV_3__IWC_INV_3_accountUpgrades_onlyTargetWhitelistedAccountImplementations()
        public
    {
        // Setup: whitelist target under Organization type only.
        _setSingleAdminThresholdOne();
        address target = address(new AccountImplementationVersion1());
        _setOrganizationImplementationWhitelisted(target, true);
        (AdminAuthParams memory auth,) = _buildAuthForOrganization({
            organization: address(organizationProxy),
            operationType: OperationType.UpgradeAccount,
            operationData: abi.encode(target),
            isApproval: true,
            salt: 141_302,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: Account upgrade path rejects Organization-only whitelist entries.
        vm.expectRevert(abi.encodeWithSelector(IImplementationWhitelist.ImplementationNotWhitelisted.selector, target));
        vm.prank(GUARDIAN);
        organizationProxy.setAccountImplementation(target, auth);
    }

    /// @dev Verifies invariant that all accounts under one organization resolve the same beacon implementation.
    function test_UPG_INV_4_allAccountsUnderOrganizationResolveSameImplementation() public {
        // Setup: configure account implementation and deploy two organization-managed accounts.
        _setSingleAdminThresholdOne();
        address accountImplV1 = address(new AccountImplementationVersion1());
        _setAccountImplementationWhitelisted(accountImplV1, true);
        (AdminAuthParams memory setAuth,) = _buildAuthForOrganization({
            organization: address(organizationProxy),
            operationType: OperationType.UpgradeAccount,
            operationData: abi.encode(accountImplV1),
            isApproval: true,
            salt: 141_303,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.prank(GUARDIAN);
        organizationProxy.setAccountImplementation(accountImplV1, setAuth);

        (AdminAuthParams memory deployAuthA,) = _buildAuthForOrganization({
            organization: address(organizationProxy),
            operationType: OperationType.DeployAccount,
            operationData: abi.encode(bytes32(uint256(3))),
            isApproval: true,
            salt: 141_304,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        (AdminAuthParams memory deployAuthB,) = _buildAuthForOrganization({
            organization: address(organizationProxy),
            operationType: OperationType.DeployAccount,
            operationData: abi.encode(bytes32(uint256(4))),
            isApproval: true,
            salt: 141_305,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        address accountA = organizationProxy.deployAccount(bytes32(uint256(3)), deployAuthA);
        vm.prank(GUARDIAN);
        address accountB = organizationProxy.deployAccount(bytes32(uint256(4)), deployAuthB);

        // Verify: all accounts resolve same organization-managed implementation pointer.
        assertEq(IVersionedAccount(accountA).version(), 1, "account A impl mismatch");
        assertEq(IVersionedAccount(accountB).version(), 1, "account B impl mismatch");
    }

    /// @dev Verifies invariant that Organization implementation pointer and Account beacon pointer are independent.
    function test_UPG_INV_5_organizationAndAccountImplementationPointersAreIndependent() public {
        // Setup: seed account implementation pointer and whitelist Organization V2 for upgrade.
        _setSingleAdminThresholdOne();
        address accountImplV1 = address(new AccountImplementationVersion1());
        _setAccountImplementationWhitelisted(accountImplV1, true);
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);

        (AdminAuthParams memory accountAuth,) = _buildAuthForOrganization({
            organization: address(organizationProxy),
            operationType: OperationType.UpgradeAccount,
            operationData: abi.encode(accountImplV1),
            isApproval: true,
            salt: 141_306,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.prank(GUARDIAN);
        organizationProxy.setAccountImplementation(accountImplV1, accountAuth);

        (AdminAuthParams memory orgAuth,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            salt: 141_307,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: perform Organization UUPS implementation change.
        vm.prank(GUARDIAN);
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), orgAuth);

        // Verify: Organization pointer changed while account implementation pointer remained intact.
        assertEq(
            _readProxyImplementation(address(organizationProxy)), address(implementationV2), "org pointer mismatch"
        );
        assertEq(
            organizationProxy.getAccountImplementationStorage(), accountImplV1, "account pointer should be unchanged"
        );
    }

    /// @dev Verifies the stored whitelist address remains immutable across successful Organization upgrades.
    function test_ACCF_INV_8__UPG_INV_6__IWC_INV_5__IWC_INV_6_whitelistAddressRemainsImmutableAcrossUpgrades() public {
        // Setup: set whitelist address and execute successful Organization upgrade.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        address configuredWhitelist = address(whitelist);
        organizationProxy.setUpgradeState(configuredWhitelist, address(0));
        (AdminAuthParams memory auth,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            salt: 141_308,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), auth);

        // Verify: whitelist address used for upgrade checks did not change.
        (address persistedWhitelist,) = organizationProxy.getUpgradeState();
        assertEq(persistedWhitelist, configuredWhitelist, "whitelist address should remain unchanged");
    }

    /// @dev Verifies direct UUPS upgrade selectors never mutate implementation without authorized wrapper flow.
    function test_UPG_CTRL_2__UPG_INV_7_directUUPSSelectorsCannotChangeImplementationWithoutWrapperAuthorization()
        public
    {
        // Setup: whitelist target for isolation and capture baseline implementation pointer.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        address beforeImpl = _readProxyImplementation(address(organizationProxy));

        // Call: direct `upgradeToAndCall` should revert and not mutate implementation.
        vm.expectRevert(IOrganization.UnauthorizedUpgrade.selector);
        IUUPSOrgEntrypoints(address(organizationProxy)).upgradeToAndCall(address(implementationV2), bytes(""));
        assertEq(
            _readProxyImplementation(address(organizationProxy)), beforeImpl, "impl changed via direct upgradeToAndCall"
        );

        // Call: raw `upgradeTo(address)` selector should also fail to mutate implementation.
        (bool success,) = address(organizationProxy)
            .call(abi.encodeWithSelector(bytes4(keccak256("upgradeTo(address)")), address(implementationV2)));

        // Verify: raw selector path cannot mutate implementation.
        assertFalse(success, "raw upgradeTo should not succeed");
        assertEq(_readProxyImplementation(address(organizationProxy)), beforeImpl, "impl changed via raw upgradeTo");
    }
}
