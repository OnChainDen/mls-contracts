// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IImplementationWhitelist} from "interfaces/IImplementationWhitelist.sol";
import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {
    AccountImplementationVersion1,
    AccountImplementationVersion2,
    IVersionedAccount,
    OrganizationUpgradesCrossFileSuiteBase
} from "test/organization/integration/OrganizationUpgradesCrossFileSuiteBase.sol";
import {OrganizationImplementationHarness} from "test/organization/shared/OrganizationUpgradeHarnesses.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Cross-file integration tests for organization/account upgrade security flows.
 */
contract OrganizationUpgradesCrossFileTest is OrganizationUpgradesCrossFileSuiteBase {
    /// @dev Verifies full flow: whitelist Organization impl + guardian/admin auth -> Organization upgrade succeeds.
    function test_UPG_CFS_1_fullFlow_organizationUpgradeSucceeds() public {
        // Setup: seed valid guardian/admin config and whitelist V2 Organization implementation.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        (AdminAuthParams memory auth,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            salt: 141_001,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: execute wrapper-based Organization upgrade.
        vm.prank(GUARDIAN);
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), auth);

        // Verify: proxy now points to whitelisted V2 implementation.
        assertEq(
            _readProxyImplementation(address(organizationProxy)), address(implementationV2), "upgrade should succeed"
        );
    }

    /// @dev Verifies full flow: whitelist Account impl + guardian/admin auth upgrades all deployed accounts.
    function test_UPG_CFS_2_fullFlow_accountImplementationUpgradeAffectsAllAccounts() public {
        // Setup: deploy two account implementation versions and whitelist both.
        _setSingleAdminThresholdOne();
        address accountImplV1 = address(new AccountImplementationVersion1());
        address accountImplV2 = address(new AccountImplementationVersion2());
        _setAccountImplementationWhitelisted(accountImplV1, true);
        _setAccountImplementationWhitelisted(accountImplV2, true);

        (AdminAuthParams memory setV1Auth,) = _buildAuthForOrganization({
            organization: address(organizationProxy),
            operationType: OperationType.UpgradeAccount,
            operationData: abi.encode(accountImplV1),
            isApproval: true,
            salt: 141_002,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        organizationProxy.setAccountImplementation(accountImplV1, setV1Auth);

        (AdminAuthParams memory deployAuthA,) = _buildAuthForOrganization({
            organization: address(organizationProxy),
            operationType: OperationType.DeployAccount,
            operationData: abi.encode(bytes32(uint256(1))),
            isApproval: true,
            salt: 141_003,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        (AdminAuthParams memory deployAuthB,) = _buildAuthForOrganization({
            organization: address(organizationProxy),
            operationType: OperationType.DeployAccount,
            operationData: abi.encode(bytes32(uint256(2))),
            isApproval: true,
            salt: 141_004,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        address accountA = organizationProxy.deployAccount(bytes32(uint256(1)), deployAuthA);
        vm.prank(GUARDIAN);
        address accountB = organizationProxy.deployAccount(bytes32(uint256(2)), deployAuthB);

        assertEq(IVersionedAccount(accountA).version(), 1, "account A should start on v1");
        assertEq(IVersionedAccount(accountB).version(), 1, "account B should start on v1");

        (AdminAuthParams memory setV2Auth,) = _buildAuthForOrganization({
            organization: address(organizationProxy),
            operationType: OperationType.UpgradeAccount,
            operationData: abi.encode(accountImplV2),
            isApproval: true,
            salt: 141_005,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: switch account implementation pointer to v2.
        vm.prank(GUARDIAN);
        organizationProxy.setAccountImplementation(accountImplV2, setV2Auth);

        // Verify: both previously deployed accounts now execute v2 code.
        assertEq(IVersionedAccount(accountA).version(), 2, "account A should resolve to v2");
        assertEq(IVersionedAccount(accountB).version(), 2, "account B should resolve to v2");
    }

    /// @dev Verifies unwhitelisting blocks future upgrades but does not mutate already-active implementation pointers.
    function test_UPG_CFS_3_unwhitelistingBlocksFutureUpgradeWithoutMutatingActivePointers() public {
        // Setup: activate Organization V2 and Account implementation V1 while both are whitelisted.
        _setSingleAdminThresholdOne();
        address accountImplV1 = address(new AccountImplementationVersion1());
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        _setAccountImplementationWhitelisted(accountImplV1, true);

        (AdminAuthParams memory orgUpgradeAuth,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            salt: 141_006,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.prank(GUARDIAN);
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), orgUpgradeAuth);

        (AdminAuthParams memory setAccountAuth,) = _buildAuthForOrganization({
            organization: address(organizationProxy),
            operationType: OperationType.UpgradeAccount,
            operationData: abi.encode(accountImplV1),
            isApproval: true,
            salt: 141_007,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.prank(GUARDIAN);
        organizationProxy.setAccountImplementation(accountImplV1, setAccountAuth);

        // Setup: unwhitelist both active targets.
        _setOrganizationImplementationWhitelisted(address(implementationV2), false);
        _setAccountImplementationWhitelisted(accountImplV1, false);

        // Verify: future attempts to set same unwhitelisted targets fail.
        (AdminAuthParams memory retryOrgAuth,) = _buildAuthForOrganization({
            organization: address(organizationProxy),
            operationType: OperationType.Upgrade,
            operationData: _encodeOperationDataForUpgrade(address(implementationV2)),
            isApproval: true,
            salt: 141_008,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector, address(implementationV2)
            )
        );
        vm.prank(GUARDIAN);
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), retryOrgAuth);

        (AdminAuthParams memory retryAccountAuth,) = _buildAuthForOrganization({
            organization: address(organizationProxy),
            operationType: OperationType.UpgradeAccount,
            operationData: abi.encode(accountImplV1),
            isApproval: true,
            salt: 141_009,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.expectRevert(
            abi.encodeWithSelector(IImplementationWhitelist.ImplementationNotWhitelisted.selector, accountImplV1)
        );
        vm.prank(GUARDIAN);
        organizationProxy.setAccountImplementation(accountImplV1, retryAccountAuth);

        // Verify: already-active pointers remain unchanged.
        assertEq(_readProxyImplementation(address(organizationProxy)), address(implementationV2), "org pointer changed");
        assertEq(organizationProxy.getAccountImplementationStorage(), accountImplV1, "account pointer changed");
    }

    /// @dev Verifies unwhitelisting active Organization implementation does not block upgrading to new whitelisted
    /// impl.
    function test_UPG_CFS_4_unwhitelistedActiveOrgImpl_canUpgradeToNewWhitelistedImpl() public {
        // Setup: upgrade to V2, unwhitelist V2, and whitelist V3.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        _setOrganizationImplementationWhitelisted(address(implementationV3), true);

        (AdminAuthParams memory toV2Auth,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            salt: 141_010,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.prank(GUARDIAN);
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), toV2Auth);

        _setOrganizationImplementationWhitelisted(address(implementationV2), false);

        (AdminAuthParams memory toV3Auth,) = _buildAuthForOrganization({
            organization: address(organizationProxy),
            operationType: OperationType.Upgrade,
            operationData: _encodeOperationDataForUpgrade(address(implementationV3)),
            isApproval: true,
            salt: 141_011,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: upgrade from unwhitelisted-active V2 to newly whitelisted V3.
        vm.prank(GUARDIAN);
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV3), bytes(""), toV3Auth);

        // Verify: upgrade succeeds because execution target is whitelisted at execution time.
        assertEq(
            _readProxyImplementation(address(organizationProxy)), address(implementationV3), "upgrade to v3 failed"
        );
    }

    /// @dev Verifies unwhitelisting active Account implementation does not block upgrade to a new whitelisted target.
    function test_UPG_CFS_5_unwhitelistedActiveAccountImpl_canUpgradeToNewWhitelistedImpl() public {
        // Setup: activate account impl V1, unwhitelist V1, whitelist V2.
        _setSingleAdminThresholdOne();
        address accountImplV1 = address(new AccountImplementationVersion1());
        address accountImplV2 = address(new AccountImplementationVersion2());
        _setAccountImplementationWhitelisted(accountImplV1, true);
        _setAccountImplementationWhitelisted(accountImplV2, true);

        (AdminAuthParams memory setV1Auth,) = _buildAuthForOrganization({
            organization: address(organizationProxy),
            operationType: OperationType.UpgradeAccount,
            operationData: abi.encode(accountImplV1),
            isApproval: true,
            salt: 141_012,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.prank(GUARDIAN);
        organizationProxy.setAccountImplementation(accountImplV1, setV1Auth);

        _setAccountImplementationWhitelisted(accountImplV1, false);

        (AdminAuthParams memory setV2Auth,) = _buildAuthForOrganization({
            organization: address(organizationProxy),
            operationType: OperationType.UpgradeAccount,
            operationData: abi.encode(accountImplV2),
            isApproval: true,
            salt: 141_013,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: move pointer to new whitelisted account implementation.
        vm.prank(GUARDIAN);
        organizationProxy.setAccountImplementation(accountImplV2, setV2Auth);

        // Verify: upgrade succeeds to whitelisted V2 despite V1 being unwhitelisted.
        assertEq(organizationProxy.getAccountImplementationStorage(), accountImplV2, "account impl upgrade failed");
    }

    /// @dev Verifies Organization upgrades do not bypass Account implementation whitelist/type checks.
    function test_UPG_CFS_6_organizationUpgrade_doesNotBypassAccountWhitelistChecks() public {
        // Setup: upgrade Organization to V2, then try account implementation update using Organization-type whitelist
        // only.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);

        (AdminAuthParams memory orgAuth,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            salt: 141_014,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.prank(GUARDIAN);
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), orgAuth);

        address target = address(new AccountImplementationVersion1());
        _setOrganizationImplementationWhitelisted(target, true);

        (AdminAuthParams memory accountAuth,) = _buildAuthForOrganization({
            organization: address(organizationProxy),
            operationType: OperationType.UpgradeAccount,
            operationData: abi.encode(target),
            isApproval: true,
            salt: 141_015,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: account upgrade still enforces Account-type whitelist namespace.
        vm.expectRevert(abi.encodeWithSelector(IImplementationWhitelist.ImplementationNotWhitelisted.selector, target));
        vm.prank(GUARDIAN);
        // Call: attempt account implementation update with Organization-only whitelist entry.
        organizationProxy.setAccountImplementation(target, accountAuth);
    }

    /// @dev Verifies without valid admin auth, neither Organization nor Account upgrade path executes.
    function test_UPG_CFS_7_withoutValidAdminAuth_neitherUpgradePathExecutes() public {
        // Setup: whitelist valid targets but use empty/invalid auth payload.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        address accountImplV1 = address(new AccountImplementationVersion1());
        _setAccountImplementationWhitelisted(accountImplV1, true);
        AdminAuthParams memory invalidAuth;

        // Verify: Organization upgrade path rejects invalid auth.
        vm.expectRevert();
        vm.prank(GUARDIAN);
        // Call: wrapper-based Organization upgrade with invalid auth.
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), invalidAuth);

        // Verify: Account implementation upgrade path also rejects invalid auth.
        vm.expectRevert();
        vm.prank(GUARDIAN);
        // Call: account implementation update with invalid auth.
        organizationProxy.setAccountImplementation(accountImplV1, invalidAuth);
    }

    /// @dev Verifies execution fails if implementation is unwhitelisted after signatures are collected.
    function test_UPG_CFS_8_unwhitelistedAfterSigning_beforeExecution_fails() public {
        // Setup: build valid auth while target is whitelisted, then unwhitelist before execution.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        (AdminAuthParams memory auth,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            salt: 141_016,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        _setOrganizationImplementationWhitelisted(address(implementationV2), false);

        // Verify: whitelist is enforced at execution time.
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector, address(implementationV2)
            )
        );
        vm.prank(GUARDIAN);
        // Call: execute with signatures collected before unwhitelisting.
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), auth);
    }

    /// @dev Verifies re-whitelisting re-enables upgrades only with fresh valid auth at execution time.
    function test_UPG_CFS_9_reWhitelistingRequiresFreshValidAuth() public {
        // Setup: collect auth, force initial failure by unwhitelisting, then let auth expire before retry.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        (AdminAuthParams memory oldAuth,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            salt: 141_017,
            expiration: block.timestamp + 1,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        _setOrganizationImplementationWhitelisted(address(implementationV2), false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector, address(implementationV2)
            )
        );
        vm.prank(GUARDIAN);
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), oldAuth);

        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        vm.warp(block.timestamp + 2);

        vm.expectPartialRevert(IOrganizationAdmin.AdminOperationExpired.selector);
        vm.prank(GUARDIAN);
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), oldAuth);

        (AdminAuthParams memory freshAuth,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            salt: 141_018,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: execute with fresh valid auth after re-whitelisting.
        vm.prank(GUARDIAN);
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), freshAuth);

        // Verify: fresh auth succeeds.
        assertEq(
            _readProxyImplementation(address(organizationProxy)), address(implementationV2), "fresh auth should succeed"
        );
    }

    /// @dev Verifies signatures for Organization A cannot authorize same call on Organization B.
    function test_UPG_CFS_10_signaturesAreDomainSeparatedPerOrganizationProxy() public {
        // Setup: deploy and configure a second Organization proxy with same admin members and whitelist.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        OrganizationImplementationHarness organizationProxyB = _deployAndConfigureSecondOrganizationProxy();

        // Build auth for Organization A domain.
        (AdminAuthParams memory authForOrgA,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            salt: 141_019,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: Organization A signatures fail on Organization B.
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        // Call: attempt Organization B upgrade with signatures generated for Organization A.
        organizationProxyB.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), authForOrgA);
    }
}
