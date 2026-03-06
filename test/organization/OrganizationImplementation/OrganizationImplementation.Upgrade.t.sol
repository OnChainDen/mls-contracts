// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AccountImplementation} from "account/AccountImplementation.sol";
import {IImplementationWhitelist} from "interfaces/IImplementationWhitelist.sol";
import {IOrganization} from "interfaces/IOrganization.sol";
import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {
    OrganizationImplementationSuiteBase
} from "test/organization/OrganizationImplementation/OrganizationImplementationSuiteBase.sol";
import {
    OrganizationImplementationHarness,
    RevertingValidationWhitelistMock
} from "test/organization/shared/OrganizationUpgradeHarnesses.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";
import {GuardianRecoveryState, PendingRecoveryInitTimelock, TxRecoveryState} from "types/RecoveryTypes.sol";

interface IUUPSUpgradeableEntrypoints {
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;
    function proxiableUUID() external view returns (bytes32);
}

/**
 * @dev Upgradeability and upgrade-execution tests for `OrganizationImplementation`.
 */
contract OrganizationImplementationUpgradeTest is OrganizationImplementationSuiteBase {
    event Upgraded(address indexed implementation);

    /// @dev Verifies valid guardian + admin auth + whitelisted implementation + empty data upgrades successfully.
    function test_OI_UTACWA_1_upgradesSuccessfullyWithValidGuardianAuthAndWhitelistedImplementation() public {
        // Setup: configure valid admin auth and whitelist a UUPS-compatible Organization target.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        (AdminAuthParams memory auth,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            salt: 14_001,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: execute upgrade via the authorized wrapper with empty migration data.
        vm.prank(GUARDIAN);
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), auth);

        // Verify: proxy implementation points to the newly approved Organization implementation.
        assertEq(
            _readProxyImplementation(address(organizationProxy)), address(implementationV2), "implementation mismatch"
        );
    }

    /// @dev Verifies non-empty migration calldata executes successfully during authorized upgrade.
    function test_OI_UTACWA_2_upgradesSuccessfullyAndExecutesMigrationCall() public {
        // Setup: configure auth/whitelist and migration payload for the post-upgrade delegatecall.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        bytes memory migrationData = abi.encodeCall(OrganizationImplementationHarness.migrationSetMarker, (777));
        (AdminAuthParams memory auth,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            migrationData: migrationData,
            salt: 14_002,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: run authorized upgrade with non-empty migration data.
        vm.prank(GUARDIAN);
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), migrationData, auth);

        // Verify: upgrade happened and migration side effect was persisted.
        assertEq(
            _readProxyImplementation(address(organizationProxy)), address(implementationV2), "implementation mismatch"
        );
        assertEq(organizationProxy.migrationGetMarker(), 777, "migration call did not execute");
    }

    /// @dev Verifies non-guardian callers are rejected by `onlyGuardian`.
    function test_OI_UTACWA_3_nonGuardianCaller_revertsOnlyGuardian() public {
        // Setup: prepare otherwise-valid auth and whitelist entries.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        (AdminAuthParams memory auth,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            salt: 14_003,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: non-guardian caller should be blocked before upgrade flow is evaluated.
        _expectOnlyGuardianRevert(NON_GUARDIAN);
        vm.prank(NON_GUARDIAN);
        // Call: attempt wrapper-based upgrade from non-guardian address.
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), auth);
    }

    /// @dev Verifies expired admin auth reverts during authorization validation.
    function test_OI_UTACWA_4_expiredAdminAuth_reverts() public {
        // Setup: configure valid admin membership and whitelist with already-expired auth params.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        (AdminAuthParams memory auth,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            salt: 14_004,
            expiration: block.timestamp - 1,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: expired authorization payload must be rejected.
        vm.expectPartialRevert(IOrganizationAdmin.AdminOperationExpired.selector);
        vm.prank(GUARDIAN);
        // Call: execute authorized wrapper with expired auth params.
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), auth);
    }

    /// @dev Verifies insufficient admin signatures revert `InsufficientAdminAuthorization`.
    function test_OI_UTACWA_5_insufficientAdminSignatures_reverts() public {
        // Setup: require two admin signatures but provide only one.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        (AdminAuthParams memory auth,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            salt: 14_005,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: signature threshold enforcement should fail.
        vm.expectRevert(IOrganizationAdmin.InsufficientAdminAuthorization.selector);
        vm.prank(GUARDIAN);
        // Call: execute upgrade with insufficient signatures.
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), auth);
    }

    /// @dev Verifies replaying the same admin-auth nonce reverts after first successful execution.
    function test_OI_UTACWA_6_replayWithSameNonce_reverts() public {
        // Setup: execute one successful authorized upgrade with deterministic nonce.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        (AdminAuthParams memory auth, bytes memory operationData) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            salt: 14_006,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), auth);

        uint256 nonce = _computeUpgradeNonce(operationData, 14_006);
        assertTrue(stateHarness.getUsedNonce(nonce), "nonce should be consumed");

        // Verify: replaying with identical auth should revert `NonceAlreadyUsed`.
        _expectNonceAlreadyUsed(nonce);
        vm.prank(GUARDIAN);
        // Call: replay authorized wrapper with same auth payload.
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), auth);
    }

    /// @dev Verifies nonces already consumed via rejection flow cannot be reused for upgrade execution.
    function test_OI_UTACWA_7_rejectedNonce_revertsWhenUsedForUpgrade() public {
        // Setup: reject the exact Upgrade operation nonce using valid rejection signatures.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        (AdminAuthParams memory approvalAuth, bytes memory operationData) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            salt: 14_007,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        AdminAuthParams memory rejectionAuth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.Upgrade,
            operationData: operationData,
            isApproval: false,
            salt: 14_007,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        organizationProxy.rejectAdminOperation(OperationType.Upgrade, operationData, rejectionAuth);

        uint256 nonce = _computeUpgradeNonce(operationData, 14_007);
        assertTrue(stateHarness.getUsedNonce(nonce), "rejected nonce should be consumed");

        // Verify: upgrade execution with the same nonce is rejected.
        _expectNonceAlreadyUsed(nonce);
        vm.prank(GUARDIAN);
        // Call: attempt execution after nonce was consumed by reject flow.
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), approvalAuth);
    }

    /// @dev Verifies signatures for a different target implementation cannot authorize current upgrade call.
    function test_OI_UTACWA_8_signaturesForDifferentImplementation_reverts() public {
        // Setup: sign auth for V2 while attempting execution against V3.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        _setOrganizationImplementationWhitelisted(address(implementationV3), true);
        (AdminAuthParams memory authForV2,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            salt: 14_008,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: operation-data mismatch invalidates signature authorization.
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        // Call: execute wrapper using signatures bound to a different implementation target.
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV3), bytes(""), authForV2);
    }

    /// @dev Verifies signatures for different operation type cannot authorize Organization upgrade.
    function test_OI_UTACWA_9_signaturesForWrongOperationType_reverts() public {
        // Setup: build signatures over `OperationType.UpgradeAccount` instead of `OperationType.Upgrade`.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        bytes memory operationData = _encodeOperationDataForUpgrade(address(implementationV2));
        AdminAuthParams memory wrongTypeAuth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.UpgradeAccount,
            operationData: operationData,
            isApproval: true,
            salt: 14_009,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: wrong operation-type signatures are rejected.
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        // Call: attempt upgrade execution with signatures for a different operation domain.
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), wrongTypeAuth);
    }

    /// @dev Verifies rejection-intent signatures (`isApproval=false`) cannot execute upgrades.
    function test_OI_UTACWA_10_rejectionIntentSignatures_cannotExecuteUpgrade() public {
        // Setup: build signatures for the same operation with `isApproval = false`.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        (AdminAuthParams memory rejectionAuth,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            salt: 14_010,
            expiration: block.timestamp + 1 hours,
            isApproval: false,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: rejection signatures cannot be replayed as execution auth.
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        // Call: execute upgrade path with rejection-intent signatures.
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), rejectionAuth);
    }

    /// @dev Verifies non-whitelisted Organization implementation reverts `ImplementationNotWhitelisted`.
    function test_OI_UTACWA_11_nonWhitelistedImplementation_reverts() public {
        // Setup: configure valid auth but leave target implementation un-whitelisted.
        _setSingleAdminThresholdOne();
        (AdminAuthParams memory auth, bytes memory operationData) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            salt: 14_011,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: whitelist check should fail and nonce should rollback.
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector, address(implementationV2)
            )
        );
        vm.prank(GUARDIAN);
        // Call: execute upgrade wrapper without whitelist approval.
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), auth);

        assertFalse(stateHarness.getUsedNonce(_computeUpgradeNonce(operationData, 14_011)), "nonce should not be used");
    }

    /// @dev Verifies implementations whitelisted only for `ContractType.Account` cannot upgrade Organization proxy.
    function test_OI_UTACWA_12_accountTypeOnlyWhitelistedImplementation_revertsForOrganizationUpgrade() public {
        // Setup: whitelist the target under Account type only.
        _setSingleAdminThresholdOne();
        _setAccountImplementationWhitelisted(address(implementationV2), true);
        (AdminAuthParams memory auth,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            salt: 14_012,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: Organization-type whitelist lookup still rejects the target.
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector, address(implementationV2)
            )
        );
        vm.prank(GUARDIAN);
        // Call: execute Organization upgrade with Account-only whitelist entry.
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), auth);
    }

    /// @dev Verifies upgrade to non-UUPS target reverts due UUPS safety checks.
    function test_OI_UTACWA_13_nonUUPSTarget_reverts() public {
        // Setup: whitelist a non-UUPS contract target and prepare valid auth.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(nonUupsImplementation), true);
        (AdminAuthParams memory auth,) = _buildUpgradeAuth({
            newImplementation: address(nonUupsImplementation),
            salt: 14_013,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: UUPS upgrade path rejects non-UUPS implementations.
        vm.expectRevert(
            abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidImplementation.selector, address(nonUupsImplementation))
        );
        vm.prank(GUARDIAN);
        // Call: execute authorized upgrade to non-UUPS target.
        organizationProxy.upgradeToAndCallWithAuthorization(address(nonUupsImplementation), bytes(""), auth);
    }

    /// @dev Verifies upgrade to UUPS target with incompatible `proxiableUUID` reverts.
    function test_OI_UTACWA_14_incompatibleProxiableUUID_reverts() public {
        // Setup: whitelist incompatible-UUID UUPS target and prepare valid auth.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(wrongUuidImplementation), true);
        (AdminAuthParams memory auth,) = _buildUpgradeAuth({
            newImplementation: address(wrongUuidImplementation),
            salt: 14_014,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: UUPS UUID compatibility enforcement should revert.
        vm.expectRevert(
            abi.encodeWithSelector(UUPSUpgradeable.UUPSUnsupportedProxiableUUID.selector, bytes32(uint256(123)))
        );
        vm.prank(GUARDIAN);
        // Call: execute upgrade to incompatible UUPS implementation.
        organizationProxy.upgradeToAndCallWithAuthorization(address(wrongUuidImplementation), bytes(""), auth);
    }

    /// @dev Verifies successful upgrade emits ERC-1967 `Upgraded` event with the new implementation.
    function test_OI_UTACWA_15_success_emitsUpgradedEvent() public {
        // Setup: configure valid upgrade auth and whitelist target implementation.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        (AdminAuthParams memory auth,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            salt: 14_015,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: expect canonical ERC-1967 upgrade event from proxy.
        vm.expectEmit(true, false, false, true, address(organizationProxy));
        emit Upgraded(address(implementationV2));

        vm.prank(GUARDIAN);
        // Call: execute wrapper-based upgrade.
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), auth);
    }

    /// @dev Verifies Organization state is preserved across UUPS implementation upgrade.
    function test_OI_UTACWA_16_upgrade_preservesOrganizationState() public {
        // Setup: seed representative Organization state across members/admins/groups/policies/guardian/recovery.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);

        organizationProxy.setMemberStatus(admin2, true);
        organizationProxy.setAdminStatus(admin2, true);
        organizationProxy.setAdminCount(2);
        organizationProxy.setVotingThreshold(2);
        organizationProxy.setGroupStatus(11, true);
        organizationProxy.setPoliciesRoot(bytes32(uint256(0xABCDEF)));
        address seededGuardian = address(0xBADA55);
        organizationProxy.setGuardianStorage(seededGuardian);

        TxRecoveryState memory txRecoveryState = TxRecoveryState({
            recoveryAddress: address(0x5551),
            isEnabled: true,
            timelockDurationSeconds: 3 days,
            pendingEnableTimestamp: block.timestamp + 3 days,
            pendingInit: PendingRecoveryInitTimelock({
                pendingRecoveryAddress: address(0x5552),
                pendingTimelockDurationSeconds: 7 days,
                pendingTimestamp: block.timestamp + 1 days
            })
        });
        organizationProxy.setTxRecoveryStateStorage(txRecoveryState);

        GuardianRecoveryState memory guardianRecoveryState = GuardianRecoveryState({
            recoveryAddress: address(0x6661),
            isUpdateReadyForAcceptance: true,
            pendingGuardian: address(0x6662),
            timelockDurationSeconds: 5 days,
            pendingGuardianTimestamp: block.timestamp + 5 days,
            pendingInit: PendingRecoveryInitTimelock({
                pendingRecoveryAddress: address(0x6663),
                pendingTimelockDurationSeconds: 8 days,
                pendingTimestamp: block.timestamp + 2 days
            })
        });
        organizationProxy.setGuardianRecoveryStateStorage(guardianRecoveryState);

        (AdminAuthParams memory auth,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            salt: 14_016,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1, ADMIN_PK_2)
        });

        // Call: execute authorized Organization implementation upgrade.
        vm.prank(seededGuardian);
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), auth);

        // Verify: seeded Organization and recovery state remains unchanged post-upgrade.
        assertTrue(organizationProxy.getMemberStatus(admin2), "member state mismatch");
        assertTrue(organizationProxy.getAdminStatus(admin2), "admin state mismatch");
        assertEq(organizationProxy.adminCount(), 2, "admin count mismatch");
        assertEq(organizationProxy.votingThreshold(), 2, "threshold mismatch");
        assertTrue(organizationProxy.getGroupStatus(11), "group state mismatch");
        assertEq(organizationProxy.getPoliciesRoot(), bytes32(uint256(0xABCDEF)), "policies root mismatch");
        assertEq(organizationProxy.getGuardianStorage(), seededGuardian, "guardian mismatch");

        TxRecoveryState memory persistedTxRecovery = organizationProxy.getTxRecoveryState();
        assertEq(persistedTxRecovery.recoveryAddress, txRecoveryState.recoveryAddress, "tx recovery address mismatch");
        assertEq(persistedTxRecovery.isEnabled, txRecoveryState.isEnabled, "tx recovery enabled mismatch");
        assertEq(
            persistedTxRecovery.timelockDurationSeconds,
            txRecoveryState.timelockDurationSeconds,
            "tx recovery timelock mismatch"
        );
        assertEq(
            persistedTxRecovery.pendingEnableTimestamp,
            txRecoveryState.pendingEnableTimestamp,
            "tx recovery pending enable mismatch"
        );
        assertEq(
            persistedTxRecovery.pendingInit.pendingRecoveryAddress,
            txRecoveryState.pendingInit.pendingRecoveryAddress,
            "tx recovery pending init address mismatch"
        );

        GuardianRecoveryState memory persistedGuardianRecovery = organizationProxy.getGuardianRecoveryState();
        assertEq(
            persistedGuardianRecovery.recoveryAddress,
            guardianRecoveryState.recoveryAddress,
            "guardian recovery address mismatch"
        );
        assertEq(
            persistedGuardianRecovery.isUpdateReadyForAcceptance,
            guardianRecoveryState.isUpdateReadyForAcceptance,
            "guardian recovery readiness mismatch"
        );
        assertEq(
            persistedGuardianRecovery.pendingGuardian,
            guardianRecoveryState.pendingGuardian,
            "guardian recovery pending guardian mismatch"
        );
        assertEq(
            persistedGuardianRecovery.timelockDurationSeconds,
            guardianRecoveryState.timelockDurationSeconds,
            "guardian recovery timelock mismatch"
        );
    }

    /// @dev Verifies account-factory state remains intact across Organization UUPS upgrades.
    function test_OI_UTACWA_17_upgrade_preservesAccountFactoryState() public {
        // Setup: seed account implementation pointer and deployed-account tracking before upgrade.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        address deployedAccount = address(0xA0001);
        address initialAccountImplementation = address(new AccountImplementation());
        organizationProxy.setAccountImplementationStorage(initialAccountImplementation);
        organizationProxy.setDeployedAccount(deployedAccount, true);

        (AdminAuthParams memory auth,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            salt: 14_017,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: execute authorized Organization upgrade.
        vm.prank(GUARDIAN);
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), auth);

        // Verify: account-factory storage persisted through the implementation change.
        assertEq(
            organizationProxy.getAccountImplementationStorage(),
            initialAccountImplementation,
            "account implementation pointer changed"
        );
        assertTrue(organizationProxy.isDeployedAccount(deployedAccount), "deployed-account tracking changed");
    }

    /// @dev Verifies sequential upgrades preserve state and expected behavior at each version.
    function test_OI_UTACWA_18_sequentialUpgrades_preserveStateAndFunctionality() public {
        // Setup: whitelist V2/V3 and seed account-implementation state to check persistence.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        _setOrganizationImplementationWhitelisted(address(implementationV3), true);
        address accountImplementation = address(new AccountImplementation());
        organizationProxy.setAccountImplementationStorage(accountImplementation);

        (AdminAuthParams memory authV2,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            salt: 14_018,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        (AdminAuthParams memory authV3,) = _buildUpgradeAuth({
            newImplementation: address(implementationV3),
            salt: 14_019,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: perform V1 -> V2 -> V3 upgrade sequence.
        vm.prank(GUARDIAN);
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), authV2);

        vm.prank(GUARDIAN);
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV3), bytes(""), authV3);

        // Verify: final implementation/version are correct and seeded state persisted throughout.
        assertEq(_readProxyImplementation(address(organizationProxy)), address(implementationV3), "final impl mismatch");
        assertEq(
            organizationProxy.getAccountImplementationStorage(), accountImplementation, "account implementation changed"
        );
    }

    /// @dev Verifies reverting migration calldata reverts the full transaction and keeps implementation unchanged.
    function test_OI_UTACWA_19_revertingMigrationCall_revertsAtomicallyAndKeepsImplementation() public {
        // Setup: whitelist target and build migration payload that intentionally reverts.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        bytes memory revertingData = abi.encodeCall(OrganizationImplementationHarness.migrationRevert, ());
        (AdminAuthParams memory auth,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            migrationData: revertingData,
            salt: 14_020,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        address implementationBefore = _readProxyImplementation(address(organizationProxy));

        // Verify: post-upgrade migration revert should rollback implementation pointer.
        vm.expectRevert(OrganizationImplementationHarness.MigrationCallReverted.selector);
        vm.prank(GUARDIAN);
        // Call: execute upgrade with reverting migration payload.
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), revertingData, auth);

        assertEq(
            _readProxyImplementation(address(organizationProxy)),
            implementationBefore,
            "implementation should remain unchanged"
        );
    }

    /// @dev Verifies failing upgrade paths do not consume nonce and the same auth can succeed after fix.
    function test_OI_UTACWA_20_failedPath_doesNotConsumeNonceAndCanRetry() public {
        // Setup: build valid auth while leaving target temporarily un-whitelisted.
        _setSingleAdminThresholdOne();
        (AdminAuthParams memory auth, bytes memory operationData) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            salt: 14_021,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 nonce = _computeUpgradeNonce(operationData, 14_021);

        // Call: first attempt fails due whitelist validation.
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector, address(implementationV2)
            )
        );
        vm.prank(GUARDIAN);
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), auth);

        // Verify: nonce was not consumed by reverted path, then retry succeeds after whitelisting.
        assertFalse(stateHarness.getUsedNonce(nonce), "nonce should not be consumed on failed path");
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);

        vm.prank(GUARDIAN);
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), auth);
        assertTrue(stateHarness.getUsedNonce(nonce), "nonce should be consumed on successful retry");
    }

    /// @dev Verifies authorized-upgrade target is non-zero only during upgrade execution and zero before/after.
    function test_OI_UTACWA_21_upgradeAuthorizationFlag_scopedToExecutionWindow() public {
        // Setup: whitelist target and use migration helper that requires in-flight upgrade authorization.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        bytes memory migrationData =
            abi.encodeCall(OrganizationImplementationHarness.migrationRequireAuthAndSetMarker, (2121));
        (AdminAuthParams memory auth,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            migrationData: migrationData,
            salt: 14_022,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        (, address beforeAuthorizedTarget) = organizationProxy.getUpgradeState();
        assertEq(beforeAuthorizedTarget, address(0), "authorized target should start unset");

        // Call: execute wrapper upgrade with migration assertion helper.
        vm.prank(GUARDIAN);
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), migrationData, auth);

        // Verify: migration observed in-flight authorization, and stored authorized target resets to zero.
        assertEq(organizationProxy.migrationGetMarker(), 2121, "migration helper should run during authorized upgrade");
        (, address afterAuthorizedTarget) = organizationProxy.getUpgradeState();
        assertEq(afterAuthorizedTarget, address(0), "authorized target should reset after execution");
    }

    /// @dev Verifies failed upgrade paths never leave authorized-upgrade target stuck set.
    function test_OI_UTACWA_22_failedUpgrade_neverLeavesAuthorizationFlagTrue() public {
        // Setup: use reverting migration payload to force rollback path.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        bytes memory revertingData = abi.encodeCall(OrganizationImplementationHarness.migrationRevert, ());
        (AdminAuthParams memory auth,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            migrationData: revertingData,
            salt: 14_023,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: execute authorized upgrade that reverts during migration.
        vm.expectRevert(OrganizationImplementationHarness.MigrationCallReverted.selector);
        vm.prank(GUARDIAN);
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), revertingData, auth);

        // Verify: authorized target remains zero after reverted execution path.
        (, address authorizedTargetAfterFailure) = organizationProxy.getUpgradeState();
        assertEq(authorizedTargetAfterFailure, address(0), "authorized target should not remain set after failure");
    }

    /// @dev Verifies direct calls to inherited `upgradeToAndCall` always revert `UnauthorizedUpgrade`.
    function test_OI_UTACWA_23_directUpgradeToAndCall_revertsUnauthorizedUpgrade() public {
        // Setup: ensure target is UUPS-compatible and whitelisted to isolate bypass check.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);

        // Verify: bypassing wrapper should revert with `UnauthorizedUpgrade`.
        vm.expectRevert(IOrganization.UnauthorizedUpgrade.selector);
        // Call: invoke inherited UUPS entrypoint directly on proxy.
        IUUPSUpgradeableEntrypoints(address(organizationProxy)).upgradeToAndCall(address(implementationV2), bytes(""));
    }

    /// @dev Verifies direct `upgradeToAndCall` reverts even when caller is guardian.
    function test_OI_UTACWA_24_directUpgradeToAndCall_byGuardianStillRevertsUnauthorizedUpgrade() public {
        // Setup: isolate bypass path with compatible target.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);

        // Verify: guardian cannot bypass wrapper/admin auth flow.
        vm.expectRevert(IOrganization.UnauthorizedUpgrade.selector);
        vm.prank(GUARDIAN);
        // Call: invoke direct UUPS entrypoint from guardian account.
        IUUPSUpgradeableEntrypoints(address(organizationProxy)).upgradeToAndCall(address(implementationV2), bytes(""));
    }

    /// @dev Verifies `upgradeToAndCallWithAuthorization` binds signatures to both `newImplementation` and migration
    /// `data`.
    function test_OI_UTACWA_25_adminAuthMustBindMigrationData() public {
        // Setup: build auth for target implementation and then mutate only migration calldata at execution time.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        (AdminAuthParams memory auth,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            salt: 14_025,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        bytes memory tamperedMigrationData =
            abi.encodeCall(OrganizationImplementationHarness.migrationSetMarker, (2525));

        // Verify: swapping migration calldata after signatures are collected reverts.
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        // Call: execute wrapper with tampered migration calldata under unchanged auth payload.
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), tamperedMigrationData, auth);
    }

    /// @dev Verifies migration calldata cannot trigger a nested second upgrade without fresh authorization.
    function test_OI_UTACWA_26_nestedSecondUpgradeFromMigration_reverts() public {
        // Setup: whitelist first target only, then craft migration payload to attempt nested upgrade to un-whitelisted
        // V3.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        bytes memory nestedData = abi.encodeCall(
            OrganizationImplementationHarness.migrationNestedUpgrade, (address(implementationV3), bytes(""))
        );
        (AdminAuthParams memory auth,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            migrationData: nestedData,
            salt: 14_026,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: nested second-upgrade attempts from migration calldata are rejected.
        vm.expectRevert(IOrganization.UnauthorizedUpgrade.selector);
        vm.prank(GUARDIAN);
        // Call: execute first upgrade with nested second-upgrade payload.
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), nestedData, auth);
    }

    /// @dev Verifies chained upgrades still fail when the second target is also whitelisted and UUPS-compatible.
    function test_OI_UTACWA_27_nestedSecondUpgradeToWhitelistedTarget_revertsWithoutFreshAuth() public {
        // Setup: whitelist both targets but provide fresh admin auth only for first upgrade.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        _setOrganizationImplementationWhitelisted(address(implementationV3), true);
        bytes memory nestedData = abi.encodeCall(
            OrganizationImplementationHarness.migrationNestedUpgrade, (address(implementationV3), bytes(""))
        );
        (AdminAuthParams memory auth,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            migrationData: nestedData,
            salt: 14_027,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: each upgrade step requires its own guardian/admin authorization.
        vm.expectRevert(IOrganization.UnauthorizedUpgrade.selector);
        vm.prank(GUARDIAN);
        // Call: attempt first upgrade with migration payload that chains a second upgrade.
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), nestedData, auth);
    }

    /// @dev Verifies upgrades fail closed when the configured whitelist address has no code.
    function test_OI_UTACWA_28_whitelistAddressWithoutCode_revertsFailClosed() public {
        // Setup: configure upgrade storage with an EOA/no-code whitelist address.
        _setSingleAdminThresholdOne();
        organizationProxy.setUpgradeState(address(0xABCD), address(0));
        (AdminAuthParams memory auth, bytes memory operationData) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            salt: 14_028,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: misconfigured whitelist address must block upgrades and leave nonce unused.
        // Note: Solidity's extcodesize check on the no-code whitelist address produces revert(0,0) with no error data.
        vm.expectRevert(bytes(""));
        vm.prank(GUARDIAN);
        // Call: execute wrapper with whitelist target lacking runtime code.
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), auth);

        assertFalse(
            stateHarness.getUsedNonce(_computeUpgradeNonce(operationData, 14_028)),
            "nonce should remain unused on whitelist misconfiguration"
        );
    }

    /// @dev Verifies upgrade reverts when the whitelist validation call reverts.
    function test_OI_UTACWA_29_whitelistValidationRevert_reverts() public {
        // Setup: configure revert-on-validate whitelist behavior.
        _setSingleAdminThresholdOne();
        RevertingValidationWhitelistMock revertingWhitelist = new RevertingValidationWhitelistMock();
        organizationProxy.setUpgradeState(address(revertingWhitelist), address(0));
        (AdminAuthParams memory authReverting,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            salt: 14_029,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: revert path should fail closed.
        vm.expectRevert("VALIDATION_REVERT");
        vm.prank(GUARDIAN);
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), authReverting);
    }

    /// @dev Verifies `upgradeToAndCallWithAuthorization` rejects zero and no-code targets even when whitelisted.
    function test_OI_UTACWA_30_zeroImplementationEvenIfWhitelisted_reverts() public {
        // Setup: whitelist zero address under Organization type and build matching auth.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(0), true);
        (AdminAuthParams memory auth, bytes memory operationData) = _buildUpgradeAuth({
            newImplementation: address(0),
            salt: 14_031,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: zero/no-code implementations must fail during UUPS upgrade safety checks.
        vm.expectRevert(IOrganization.UnauthorizedUpgrade.selector);
        vm.prank(GUARDIAN);
        // Call: attempt upgrade to zero address even though whitelisted.
        organizationProxy.upgradeToAndCallWithAuthorization(address(0), bytes(""), auth);

        assertFalse(
            stateHarness.getUsedNonce(_computeUpgradeNonce(operationData, 14_031)),
            "nonce should not be consumed on invalid implementation target"
        );
    }

    /// @dev Verifies `implementation()` returns the current account implementation from storage.
    function test_OI_IMP_1_implementation_returnsCurrentAccountImplementationFromStorage() public {
        // Setup: seed account-implementation storage with a code-bearing implementation.
        address accountImplementation = address(new AccountImplementation());
        organizationProxy.setAccountImplementationStorage(accountImplementation);

        // Call: read beacon implementation through Organization override.
        address implementationAddress = organizationProxy.implementation();

        // Verify: getter returns the seeded account implementation.
        assertEq(implementationAddress, accountImplementation, "implementation getter mismatch");
    }

    /// @dev Verifies `implementation()` reverts `AccountImplementationNotSet` when unset.
    function test_OI_IMP_2_implementation_whenUnset_revertsAccountImplementationNotSet() public {
        // Setup: leave account implementation storage unset.

        // Verify: getter should revert with canonical Organization error.
        vm.expectRevert(IOrganization.AccountImplementationNotSet.selector);
        // Call: read beacon implementation before it is configured.
        organizationProxy.implementation();
    }

    /// @dev Verifies `_authorizeUpgrade` reverts `UnauthorizedUpgrade` when no target is authorized.
    function test_OI_AU_1_authorizeUpgrade_whenFlagFalse_revertsUnauthorizedUpgrade() public {
        // Setup: ensure no authorized target is set.
        organizationProxy.setUpgradeState(address(whitelist), address(0));

        // Verify: direct authorization hook call fails when wrapper flow has not set flag.
        vm.expectRevert(IOrganization.UnauthorizedUpgrade.selector);
        // Call: invoke exposed wrapper around internal `_authorizeUpgrade`.
        organizationProxy.exposeAuthorizeUpgrade(address(implementationV2));
    }

    /// @dev Verifies `_authorizeUpgrade` succeeds only during authorized wrapper flow.
    function test_OI_AU_2_authorizeUpgrade_succeedsViaAuthorizedWrapperFlow() public {
        // Setup: configure valid admin auth and whitelist target.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        (AdminAuthParams memory auth,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            salt: 14_032,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: execute wrapper path that internally triggers `_authorizeUpgrade`.
        vm.prank(GUARDIAN);
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), bytes(""), auth);

        // Verify: successful upgrade implies `_authorizeUpgrade` accepted authorized flow.
        assertEq(
            _readProxyImplementation(address(organizationProxy)), address(implementationV2), "upgrade should succeed"
        );
    }

    /// @dev Verifies `_authorizeUpgrade` should be bound to a specific `newImplementation`, not only a boolean flag.
    function test_OI_AU_3_authorizeUpgradeMustBindSpecificImplementation() public {
        // Setup: manually set an authorized target that does not match the requested implementation.
        organizationProxy.setUpgradeState(address(whitelist), address(0xBEEF));

        // Verify: `_authorizeUpgrade` should reject arbitrary targets under mismatched target authorization state.
        vm.expectRevert(IOrganization.UnauthorizedUpgrade.selector);
        // Call: invoke authorization hook for an implementation that does not match the authorized target.
        organizationProxy.exposeAuthorizeUpgrade(address(implementationV2));
    }

    /// @dev Verifies calling `upgradeToAndCall` on implementation contract directly reverts due `onlyProxy` guard.
    function test_OI_UUPS_1_upgradeToAndCallOnImplementationContract_revertsOnlyProxy() public {
        // Setup: implementation contract call context (not proxy/delegatecall).

        // Verify: UUPS entrypoint enforces proxy-only call context.
        vm.expectRevert(UUPSUpgradeable.UUPSUnauthorizedCallContext.selector);
        // Call: invoke UUPS upgrade entrypoint directly on implementation contract.
        IUUPSUpgradeableEntrypoints(address(implementationV1)).upgradeToAndCall(address(implementationV2), bytes(""));
    }

    /// @dev Verifies calling `proxiableUUID` through proxy reverts due `notDelegated` guard.
    function test_OI_UUPS_2_proxiableUUIDThroughProxy_revertsNotDelegated() public {
        // Setup: proxy call path into UUPS `proxiableUUID`.

        // Verify: `proxiableUUID` cannot be called through delegatecall/proxy context.
        vm.expectRevert(UUPSUpgradeable.UUPSUnauthorizedCallContext.selector);
        // Call: invoke `proxiableUUID` through the Organization proxy.
        IUUPSUpgradeableEntrypoints(address(organizationProxy)).proxiableUUID();
    }
}
