// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {StorageLayoutTestBase} from "test/helpers/storage/StorageLayoutTestBase.sol";
import {ContractType} from "types/CommonTypes.sol";
import {GuardianRecoveryState, TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Storage Layout State Tests
 *      Deterministic state read/write coverage and cross-namespace isolation checks.
 */
contract StorageLayoutStateTest is StorageLayoutTestBase {
    /**
     * @dev Verifies that the implementation whitelist stores and retrieves per-ContractType, per-address entries
     * independently.
     */
    function test_implementationWhitelist_readWrite_multipleContractTypesAndImplementations() public {
        address accountImpl = address(0xAAA1);
        address organizationImpl = address(0xAAA2);

        harness.setImplementationWhitelisted(ContractType.Account, accountImpl, true);
        harness.setImplementationWhitelisted(ContractType.Organization, organizationImpl, true);
        harness.setImplementationWhitelisted(ContractType.Account, organizationImpl, false);

        assertTrue(
            harness.isImplementationWhitelisted(ContractType.Account, accountImpl),
            "Account implementation should be whitelisted"
        );
        assertTrue(
            harness.isImplementationWhitelisted(ContractType.Organization, organizationImpl),
            "Organization implementation should be whitelisted"
        );
        assertFalse(
            harness.isImplementationWhitelisted(ContractType.Account, organizationImpl),
            "Account mapping should preserve per-key status"
        );
        assertFalse(
            harness.isImplementationWhitelisted(ContractType.Organization, accountImpl),
            "Unwritten contract-type pair should remain false"
        );
    }

    /**
     * @dev Verifies that the deployedAccounts mapping and accountImplementation address persist correctly after writes.
     */
    function test_accountFactoryStorage_readWrite_deployedAccountsAndAccountImplementation() public {
        harness.setDeployedAccount(TEST_DEPLOYED_ACCOUNT, true);
        harness.setAccountImplementation(TEST_ACCOUNT_IMPLEMENTATION);

        assertTrue(harness.isDeployedAccount(TEST_DEPLOYED_ACCOUNT), "deployedAccounts mapping value was not persisted");
        assertEq(
            harness.getAccountImplementation(),
            TEST_ACCOUNT_IMPLEMENTATION,
            "accountImplementation value was not persisted"
        );
    }

    /**
     * @dev Verifies that adminOperationTimelockDurationSeconds persists correctly after a write.
     */
    function test_adminOperationTimelockStorage_readWrite_durationSeconds() public {
        uint256 timelockDuration = 5 days;

        harness.setAdminOperationTimelockDurationSeconds(timelockDuration);

        assertEq(
            harness.getAdminOperationTimelockDurationSeconds(),
            timelockDuration,
            "adminOperationTimelockDurationSeconds was not persisted"
        );
    }

    /**
     * @dev Verifies that the isAdmin mapping, adminCount, and votingThreshold fields all persist correctly after
     * writes.
     */
    function test_adminStorage_readWrite_isAdminAndScalars() public {
        harness.setAdminStatus(TEST_ADMIN, true);
        harness.setAdminCount(7);
        harness.setVotingThreshold(5);

        assertTrue(harness.getAdminStatus(TEST_ADMIN), "isAdmin mapping value was not persisted");
        assertEq(harness.getAdminCount(), 7, "adminCount value was not persisted");
        assertEq(harness.getVotingThreshold(), 5, "votingThreshold value was not persisted");
    }

    /**
     * @dev Verifies that deployerAddress persists correctly after a write.
     */
    function test_deployerAddressStorage_readWrite_deployerAddress() public {
        harness.setDeployerAddress(TEST_DEPLOYER);

        assertEq(harness.getDeployerAddress(), TEST_DEPLOYER, "deployerAddress value was not persisted");
    }

    /**
     * @dev Verifies that isGroup, isGroupMember, and wasGroupDeleted mappings store values independently per key.
     */
    function test_groupsStorage_readWrite_andIndependence() public {
        uint256 groupIdA = TEST_GROUP_ID;
        uint256 groupIdB = TEST_GROUP_ID + 1;

        address memberA = TEST_MEMBER;
        address memberB = address(0xF002);

        harness.setGroupExists(groupIdA, true);
        harness.setGroupMember(groupIdA, memberA, true);
        harness.setWasGroupDeleted(groupIdB, true);

        assertTrue(harness.isGroup(groupIdA), "isGroup value was not persisted");
        assertTrue(harness.isGroupMember(groupIdA, memberA), "isGroupMember value was not persisted");
        assertTrue(harness.wasGroupDeleted(groupIdB), "wasGroupDeleted value was not persisted");

        assertFalse(harness.isGroup(groupIdB), "isGroup should not be affected by wasGroupDeleted writes");
        assertFalse(
            harness.isGroupMember(groupIdA, memberB), "isGroupMember should remain scoped to the written member key"
        );
        assertFalse(harness.wasGroupDeleted(groupIdA), "wasGroupDeleted should remain scoped to the written group key");
    }

    /**
     * @dev Verifies that all guardian fields (guardian, isReady, pendingGuardian, pendingGuardianTimestamp) persist
     * correctly.
     */
    function test_guardianStorage_readWrite_allFields() public {
        uint256 pendingTimestamp = block.timestamp + 10 days;

        harness.setGuardianState(TEST_GUARDIAN, true, TEST_PENDING_GUARDIAN, pendingTimestamp);

        (address guardian, bool isReady, address pendingGuardian, uint256 pendingGuardianTimestamp) =
            harness.getGuardianState();

        assertEq(guardian, TEST_GUARDIAN, "guardian value was not persisted");
        assertTrue(isReady, "isGuardianUpdateReadyForAcceptance value was not persisted");
        assertEq(pendingGuardian, TEST_PENDING_GUARDIAN, "pendingGuardian value was not persisted");
        assertEq(pendingGuardianTimestamp, pendingTimestamp, "pendingGuardianUpdateTimestamp value was not persisted");
    }

    /**
     * @dev Verifies that the isMember mapping persists correctly after a write.
     */
    function test_membersStorage_readWrite_isMember() public {
        harness.setMemberStatus(TEST_MEMBER, true);

        assertTrue(harness.getMemberStatus(TEST_MEMBER), "isMember mapping value was not persisted");
    }

    /**
     * @dev Verifies that policiesRoot and the nested policyUsage mapping persist correctly after writes.
     */
    function test_policyStorage_readWrite_policiesRootAndPolicyUsage() public {
        uint256 usageAmount = 777;

        harness.setPoliciesRoot(TEST_POLICIES_ROOT);
        harness.setPolicyUsage(TEST_POLICY_USAGE_KEY, TEST_POLICY_WINDOW, usageAmount);

        assertEq(harness.getPoliciesRoot(), TEST_POLICIES_ROOT, "policiesRoot value was not persisted");
        assertEq(
            harness.getPolicyUsage(TEST_POLICY_USAGE_KEY, TEST_POLICY_WINDOW),
            usageAmount,
            "policyUsage value was not persisted"
        );
    }

    /**
     * @dev Verifies that the usedNonces mapping persists correctly after a write.
     */
    function test_signaturesStorage_readWrite_usedNonces() public {
        harness.setUsedNonce(TEST_NONCE, true);

        assertTrue(harness.getUsedNonce(TEST_NONCE), "usedNonces mapping value was not persisted");
    }

    /**
     * @dev Verifies that whitelistAddress and authorizedUpgradeImplementation persist correctly after a write.
     */
    function test_upgradeStorage_readWrite_whitelistAddressAndAuthorizedUpgradeImplementation() public {
        harness.setUpgradeState(TEST_UPGRADE_WHITELIST, TEST_IMPLEMENTATION);

        (address whitelistAddress, address authorizedUpgradeImplementation) = harness.getUpgradeState();

        assertEq(whitelistAddress, TEST_UPGRADE_WHITELIST, "whitelistAddress value was not persisted");
        assertEq(
            authorizedUpgradeImplementation,
            TEST_IMPLEMENTATION,
            "authorizedUpgradeImplementation value was not persisted"
        );
    }

    /**
     * @dev Verifies that all TxRecoveryState nested fields round-trip correctly through a write and read.
     */
    function test_recoveryStorage_readWrite_txRecovery_allNestedFields() public {
        TxRecoveryState memory expected =
            _buildTxRecoveryState(address(0xC001), true, 2 days, 12_345, address(0xC002), 3 days, 67_890);

        harness.setTxRecoveryState(expected);

        TxRecoveryState memory actual = harness.getTxRecoveryState();
        _assertTxRecoveryStateEquals(actual, expected);
    }

    /**
     * @dev Verifies that all GuardianRecoveryState nested fields round-trip correctly through a write and read.
     */
    function test_recoveryStorage_readWrite_guardianRecovery_allNestedFields() public {
        GuardianRecoveryState memory expected = _buildGuardianRecoveryState(
            address(0xD001), true, address(0xD002), 4 days, 101_202, address(0xD003), 5 days, 303_404
        );

        harness.setGuardianRecoveryState(expected);

        GuardianRecoveryState memory actual = harness.getGuardianRecoveryState();
        _assertGuardianRecoveryStateEquals(actual, expected);
    }

    /**
     * @dev Verifies that writing to one namespace does not mutate scalar or flag values in other namespaces.
     */
    function test_namespaceIsolation_writesInOneNamespace_doNotMutateOtherNamespaces() public {
        harness.setPoliciesRoot(TEST_POLICIES_ROOT);
        harness.setDeployerAddress(TEST_DEPLOYER);
        harness.setUpgradeState(TEST_UPGRADE_WHITELIST, TEST_IMPLEMENTATION);

        harness.setAdminStatus(TEST_ADMIN, true);
        harness.setAdminCount(9);
        harness.setVotingThreshold(6);

        assertEq(harness.getPoliciesRoot(), TEST_POLICIES_ROOT, "policy namespace was unexpectedly mutated");
        assertEq(harness.getDeployerAddress(), TEST_DEPLOYER, "deployer namespace was unexpectedly mutated");

        (address whitelistAddress, address authorizedUpgradeImplementation) = harness.getUpgradeState();
        assertEq(whitelistAddress, TEST_UPGRADE_WHITELIST, "upgrade whitelist was unexpectedly mutated");
        assertEq(
            authorizedUpgradeImplementation,
            TEST_IMPLEMENTATION,
            "authorized upgrade implementation was unexpectedly mutated"
        );
    }

    /**
     * @dev Verifies that mapping writes across multiple namespaces do not mutate scalar fields in other namespaces.
     */
    function test_namespaceIsolation_mappingWrites_doNotMutateScalarFieldsInOtherNamespaces() public {
        uint256 expectedTimelock = 9 days;
        address expectedDeployer = address(0xABCD);
        address expectedGuardian = address(0xABCE);

        harness.setAdminOperationTimelockDurationSeconds(expectedTimelock);
        harness.setDeployerAddress(expectedDeployer);
        harness.setGuardianState(expectedGuardian, false, address(0), 123);

        harness.setAdminStatus(TEST_ADMIN, true);
        harness.setMemberStatus(TEST_MEMBER, true);
        harness.setGroupMember(TEST_GROUP_ID, TEST_MEMBER, true);
        harness.setPolicyUsage(TEST_POLICY_USAGE_KEY, TEST_POLICY_WINDOW, 55);
        harness.setUsedNonce(TEST_NONCE, true);
        harness.setImplementationWhitelisted(ContractType.Organization, TEST_IMPLEMENTATION, true);

        assertEq(
            harness.getAdminOperationTimelockDurationSeconds(),
            expectedTimelock,
            "adminOperationTimelockDurationSeconds scalar was unexpectedly mutated"
        );
        assertEq(harness.getDeployerAddress(), expectedDeployer, "deployerAddress scalar was unexpectedly mutated");

        (address guardian,,,) = harness.getGuardianState();
        assertEq(guardian, expectedGuardian, "guardian scalar was unexpectedly mutated");
    }

    /**
     * @dev Verifies that mixed writes across all namespaces preserve every previously written value.
     */
    function test_namespaceIsolation_mixedWritesAcrossAllNamespaces_preserveValues() public {
        _writeTestFixtureValues(harness);
        _assertTestFixtureValues(harness);
    }
}
