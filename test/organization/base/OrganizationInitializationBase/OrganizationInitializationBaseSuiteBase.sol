// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {AccountImplementation} from "account/AccountImplementation.sol";
import {Test, Vm} from "forge-std/Test.sol";

import {IOrganization} from "interfaces/IOrganization.sol";
import {IOrganizationAdminOperationTimelock} from "interfaces/organization/IOrganizationAdminOperationTimelock.sol";
import {OrganizationProxy} from "organization/OrganizationProxy.sol";
import {ArrayBuilders} from "test/helpers/ArrayBuilders.sol";
import {
    InitializationWhitelistMock,
    OrganizationFactoryHarness,
    OrganizationImplementationHarness
} from "test/organization/OrganizationFactory/OrganizationFactoryHarnesses.sol";
import {ContractType, GroupModification, GroupModificationType, InitializationParams} from "types/CommonTypes.sol";
import {GuardianRecoveryState, TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Shared fixtures/helpers for initialization-focused suites.
 */
abstract contract InitializationSuiteBase is Test, ArrayBuilders {
    bytes32 internal constant ORG_DEPLOYED_TOPIC = keccak256("OrganizationDeployed(address,bytes32,address)");
    bytes32 internal constant ORG_INITIALIZED_TOPIC =
        keccak256("OrganizationInitialized(address[],uint256,address,address,uint256,address,uint256,address,uint256)");

    // ERC-1967 implementation slot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1)
    bytes32 internal constant ERC1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    address internal constant AUTHORIZED_DEPLOYER = address(0xD301);
    address internal constant UNAUTHORIZED_CALLER = address(0xD302);

    address internal constant MEMBER_1 = address(0xA101);
    address internal constant MEMBER_2 = address(0xA102);
    address internal constant MEMBER_3 = address(0xA103);

    address internal constant ADMIN_1 = address(0xB101);
    address internal constant ADMIN_2 = address(0xB102);

    address internal constant GUARDIAN = address(0xC101);
    address internal constant GUARDIAN_RECOVERY = address(0xC102);
    address internal constant TX_RECOVERY = address(0xC103);

    uint256 internal constant GROUP_ID = 7001;

    OrganizationFactoryHarness internal factory;
    OrganizationImplementationHarness internal implementation;
    AccountImplementation internal accountImplementation;
    InitializationWhitelistMock internal whitelist;

    /// @dev Deploys shared initialization fixtures and configures whitelist entries used by test suites.
    function setUp() public virtual {
        // Deploy shared mock/harness contracts for each test case.
        whitelist = new InitializationWhitelistMock();
        implementation = new OrganizationImplementationHarness();
        accountImplementation = new AccountImplementation();
        factory = new OrganizationFactoryHarness(AUTHORIZED_DEPLOYER);

        // Allow default organization/account implementations through whitelist checks.
        whitelist.setImplementationWhitelisted(ContractType.Organization, address(implementation), true);
        whitelist.setImplementationWhitelisted(ContractType.Account, address(accountImplementation), true);
    }

    /// @dev Builds a baseline valid initialization payload used by success-path tests.
    /// @return params Default initialization parameters with members, admins, one group, and recovery settings.
    function _defaultInitializationParams() internal view returns (InitializationParams memory params) {
        // Seed members/admins so admin addresses are a subset of members.
        params.members = buildArray(MEMBER_1, MEMBER_2, ADMIN_1, ADMIN_2);
        params.admins = buildArray(ADMIN_1, ADMIN_2);
        params.votingThreshold = 2;

        // Create one initial group with deterministic membership.
        GroupModification[] memory groups = new GroupModification[](1);
        groups[0] = GroupModification({
            groupId: GROUP_ID,
            modificationType: GroupModificationType.Create,
            membersToAdd: buildArray(MEMBER_1, ADMIN_1),
            membersToRemove: buildEmptyAddressArray()
        });
        params.groups = groups;

        // Apply canonical guardian, account implementation, and recovery/timelock values.
        params.guardian = GUARDIAN;
        params.accountImplementation = address(accountImplementation);
        params.adminOperationTimelockDurationSeconds = 2 days;
        params.transactionAndERC1271RecoveryAddress = TX_RECOVERY;
        params.txRecoveryTimelockDurationSeconds = 2 days;
        params.guardianRecoveryAddress = GUARDIAN_RECOVERY;
        params.guardianRecoveryTimelockDurationSeconds = 2 days;
    }

    /// @dev Deploys an organization via the shared factory using the authorized deployer.
    /// @param salt CREATE2 salt used by the factory deployment path.
    /// @param params Initialization payload forwarded to `deployOrganization`.
    /// @return organization Address of the deployed organization proxy.
    function _deployOrganization(bytes32 salt, InitializationParams memory params)
        internal
        returns (address organization)
    {
        vm.prank(AUTHORIZED_DEPLOYER);
        organization = factory.deployOrganization(salt, address(implementation), address(whitelist), params);
    }

    /// @dev Computes the expected organization address for a given salt using shared fixture addresses.
    /// @param salt CREATE2 salt used for deterministic address derivation.
    /// @return Computed organization proxy address.
    function _computeOrganizationAddress(bytes32 salt) internal view returns (address) {
        return factory.computeOrganizationAddress(salt, address(whitelist));
    }

    /// @dev Deploys an organization proxy directly (without the factory) and binds the shared
    ///      fixture implementation. Mirrors the factory's deploy + bind sequence for tests
    ///      that exercise non-factory deployment paths.
    /// @return proxy The newly deployed and implementation-bound `OrganizationProxy`.
    function _deployProxyAndBindImpl() internal returns (OrganizationProxy proxy) {
        proxy = new OrganizationProxy(address(whitelist));
        proxy.setInitialImplementation(address(implementation));
    }

    /// @dev Counts how many recorded logs use the provided topic as topic0.
    /// @param logs Recorded VM logs to scan.
    /// @param topic Target event signature topic.
    /// @return count Number of logs whose first topic matches `topic`.
    function _countTopic(Vm.Log[] memory logs, bytes32 topic) internal pure returns (uint256 count) {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == topic) {
                ++count;
            }
        }
    }

    /// @dev Returns the first index where topic0 matches the requested topic.
    /// @param logs Recorded VM logs to scan.
    /// @param topic Target event signature topic.
    /// @return Index of first match, or `type(uint256).max` when the topic is absent.
    function _firstTopicIndex(Vm.Log[] memory logs, bytes32 topic) internal pure returns (uint256) {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == topic) {
                return i;
            }
        }
        return type(uint256).max;
    }

    /// @dev Asserts that organization state matches the provided initialization payload after success, including
    /// optional recovery configuration branches.
    /// @param organization Organization instance under test.
    /// @param params Initialization parameters expected to be persisted.
    function _assertInitializedState(IOrganization organization, InitializationParams memory params) internal view {
        // Verify base membership/admin sets were materialized.
        for (uint256 i = 0; i < params.members.length; ++i) {
            assertTrue(organization.isMember(params.members[i]), "member should be initialized");
        }

        for (uint256 i = 0; i < params.admins.length; ++i) {
            assertTrue(organization.isAdmin(params.admins[i]), "admin should be initialized");
        }

        assertEq(organization.adminCount(), params.admins.length, "adminCount mismatch");
        assertEq(organization.votingThreshold(), params.votingThreshold, "votingThreshold mismatch");

        // Verify core guardian/timelock/account implementation fields.
        assertEq(organization.guardian(), params.guardian, "guardian mismatch");
        assertEq(
            IOrganizationAdminOperationTimelock(address(organization)).adminOperationTimelockDurationSeconds(),
            params.adminOperationTimelockDurationSeconds,
            "admin timelock mismatch"
        );
        assertEq(organization.implementation(), params.accountImplementation, "account implementation mismatch");

        // Verify transaction recovery configuration and downstream defaults.
        TxRecoveryState memory txRecovery = organization.getTxRecoveryState();
        if (params.transactionAndERC1271RecoveryAddress == address(0)) {
            assertEq(txRecovery.recoveryAddress, address(0), "tx recovery should stay unset when omitted");
            assertEq(txRecovery.timelockDurationSeconds, 0, "tx recovery timelock should stay unset when omitted");
        } else {
            assertEq(
                txRecovery.recoveryAddress, params.transactionAndERC1271RecoveryAddress, "tx recovery address mismatch"
            );
            assertEq(
                txRecovery.timelockDurationSeconds,
                params.txRecoveryTimelockDurationSeconds,
                "tx recovery timelock mismatch"
            );
        }
        assertFalse(txRecovery.isEnabled, "tx recovery must start disabled after init");
        assertEq(txRecovery.pendingEnableTimestamp, 0, "tx recovery pending enable timestamp must be zero after init");
        assertEq(
            txRecovery.pendingInit.pendingRecoveryAddress,
            address(0),
            "tx recovery pending init address must be zero after init"
        );
        assertEq(
            txRecovery.pendingInit.pendingTimelockDurationSeconds,
            0,
            "tx recovery pending init timelock must be zero after init"
        );
        assertEq(
            txRecovery.pendingInit.pendingTimestamp, 0, "tx recovery pending init timestamp must be zero after init"
        );

        // Verify guardian recovery configuration and downstream defaults.
        GuardianRecoveryState memory guardianRecovery = organization.getGuardianRecoveryState();
        if (params.guardianRecoveryAddress == address(0)) {
            assertEq(guardianRecovery.recoveryAddress, address(0), "guardian recovery should stay unset when omitted");
            assertEq(
                guardianRecovery.timelockDurationSeconds, 0, "guardian recovery timelock should stay unset when omitted"
            );
        } else {
            assertEq(
                guardianRecovery.recoveryAddress, params.guardianRecoveryAddress, "guardian recovery address mismatch"
            );
            assertEq(
                guardianRecovery.timelockDurationSeconds,
                params.guardianRecoveryTimelockDurationSeconds,
                "guardian recovery timelock mismatch"
            );
        }
        assertFalse(
            guardianRecovery.isUpdateReadyForAcceptance, "guardian recovery must not be ready for acceptance after init"
        );
        assertEq(
            guardianRecovery.pendingGuardian, address(0), "guardian recovery pending guardian must be zero after init"
        );
        assertEq(
            guardianRecovery.pendingGuardianTimestamp, 0, "guardian recovery pending timestamp must be zero after init"
        );
        assertEq(
            guardianRecovery.pendingInit.pendingRecoveryAddress,
            address(0),
            "guardian recovery pending init address must be zero after init"
        );
        assertEq(
            guardianRecovery.pendingInit.pendingTimelockDurationSeconds,
            0,
            "guardian recovery pending init timelock must be zero after init"
        );
        assertEq(
            guardianRecovery.pendingInit.pendingTimestamp,
            0,
            "guardian recovery pending init timestamp must be zero after init"
        );
    }

    /// @dev Asserts a deployed address has proxy runtime code rather than implementation runtime code.
    /// @param proxyAddress Address expected to hold `OrganizationProxy` runtime bytecode.
    function _assertProxyRuntimeCode(address proxyAddress) internal {
        assertGt(proxyAddress.code.length, 0, "proxy should have runtime code");
        assertTrue(
            proxyAddress.codehash != address(implementation).codehash, "proxy code must differ from implementation"
        );

        // Deploy a reference proxy and compare runtime code hash. The implementation binding
        // happens post construction so it does not affect the proxy's runtime code.
        address referenceProxy = address(_deployProxyAndBindImpl());
        assertEq(proxyAddress.codehash, referenceProxy.codehash, "proxy runtime code hash mismatch");
    }
}
