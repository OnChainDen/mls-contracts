// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {AccountImplementation} from "account/AccountImplementation.sol";
import {
    OrganizationUpgradesCrossFileSuiteBase
} from "test/organization/integration/OrganizationUpgradesCrossFileSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Integration tests for account-factory behavior that depends on Organization UUPS upgrade flows.
 */
contract OrganizationAccountFactoryBaseUpgradeIntegrationTest is OrganizationUpgradesCrossFileSuiteBase {
    /// @dev Verifies account implementation updates do not alter Organization proxy implementation pointer.
    function test_OAFB_SAI_16_accountImplementationUpgrade_doesNotAlterOrganizationImplementation() public {
        // Setup: capture Organization implementation pointer and prepare account implementation update.
        _setSingleAdminThresholdOne();
        address organizationImplementationBefore = _readProxyImplementation(address(organizationProxy));
        address accountImplV1 = address(new AccountImplementation());
        _setAccountImplementationWhitelisted(accountImplV1, true);

        (AdminAuthParams memory accountAuth,) = _buildAuthForOrganization({
            organization: address(organizationProxy),
            operationType: OperationType.UpgradeAccount,
            operationData: abi.encode(accountImplV1),
            isApproval: true,
            salt: 141416,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: execute account implementation update.
        vm.prank(GUARDIAN);
        organizationProxy.setAccountImplementation(accountImplV1, accountAuth);

        // Verify: Organization UUPS implementation pointer is unchanged.
        assertEq(
            _readProxyImplementation(address(organizationProxy)),
            organizationImplementationBefore,
            "organization implementation pointer should be unchanged"
        );
    }

    /// @dev Verifies nonces consumed through reject flow cannot authorize account implementation updates.
    function test_OAFB_SAI_6_rejectedNonce_revertsWhenUsedForAccountUpgrade() public {
        // Setup: configure baseline, whitelist target, and build approval/rejection auth for same nonce tuple.
        _setSingleAdminThresholdOne();
        address accountImplV1 = address(new AccountImplementation());
        _setAccountImplementationWhitelisted(accountImplV1, true);

        (AdminAuthParams memory approvalAuth, bytes memory operationData) = _buildAuthForOrganization({
            organization: address(organizationProxy),
            operationType: OperationType.UpgradeAccount,
            operationData: abi.encode(accountImplV1),
            isApproval: true,
            salt: 141382,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        (AdminAuthParams memory rejectionAuth,) = _buildAuthForOrganization({
            organization: address(organizationProxy),
            operationType: OperationType.UpgradeAccount,
            operationData: operationData,
            isApproval: false,
            salt: 141382,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        // Call: consume nonce via rejection path.
        organizationProxy.rejectAdminOperation(OperationType.UpgradeAccount, operationData, rejectionAuth);

        uint256 nonce = organizationProxy.computeNonce(OperationType.UpgradeAccount, operationData, 141382);
        assertTrue(organizationProxy.isNonceUsed(nonce), "rejected nonce should be consumed");

        // Verify: execution with same nonce is rejected.
        _expectNonceAlreadyUsed(nonce);
        vm.prank(GUARDIAN);
        // Call: attempt implementation update with already-consumed nonce.
        organizationProxy.setAccountImplementation(accountImplV1, approvalAuth);
    }

    /// @dev Verifies Organization UUPS upgrades preserve account implementation pointer used by `implementation()`.
    function test_OAFB_IMP_3_organizationUpgrade_preservesBeaconImplementationPointer() public {
        // Setup: configure account implementation and whitelist Organization V2 for upgrade.
        _setSingleAdminThresholdOne();
        address accountImplV1 = address(new AccountImplementation());
        _setAccountImplementationWhitelisted(accountImplV1, true);
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);

        (AdminAuthParams memory setAccountAuth,) = _buildAuthForOrganization({
            organization: address(organizationProxy),
            operationType: OperationType.UpgradeAccount,
            operationData: abi.encode(accountImplV1),
            isApproval: true,
            salt: 141421,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.prank(GUARDIAN);
        organizationProxy.setAccountImplementation(accountImplV1, setAccountAuth);

        (AdminAuthParams memory orgUpgradeAuth,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            salt: 141422,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: perform Organization UUPS upgrade.
        vm.prank(GUARDIAN);
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), orgUpgradeAuth);

        // Verify: account beacon implementation pointer remains unchanged across Organization upgrade.
        assertEq(organizationProxy.implementation(), accountImplV1, "beacon implementation pointer should persist");
    }
}
