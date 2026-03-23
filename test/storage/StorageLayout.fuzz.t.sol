// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {StorageLayoutTestBase} from "test/helpers/storage/StorageLayoutTestBase.sol";
import {ContractType} from "types/CommonTypes.sol";
import {GuardianRecoveryState, TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Storage Layout Fuzz Tests
 *      Fuzz mixes reads/writes for across all storage namespaces and checks that
 *      values are stored and retrieved deterministically.
 */
contract StorageLayoutFuzzTest is StorageLayoutTestBase {
    /**
     * @dev Verifies that all scalar fields across every storage namespace round-trip (write then read)
     *      correctly under fuzzed inputs.
     * @param seedA First fuzz seed.
     * @param seedB Second fuzz seed.
     */
    function testFuzz_mixedWriteReadAcrossAllNamespaces_isDeterministic(bytes32 seedA, bytes32 seedB) public {
        ContractType contractType = ContractType(uint8(uint256(seedA) % 2));

        address implementation = _deriveAddress(seedA, 1);
        bool isWhitelisted = _deriveBool(seedA, 2);

        address deployedAccount = _deriveAddress(seedA, 3);
        bool isDeployedAccount = _deriveBool(seedA, 4);
        address accountImplementation = _deriveAddress(seedA, 5);

        uint256 adminOperationTimelockDuration = _deriveUint(seedA, 6);

        address admin = _deriveAddress(seedA, 7);
        bool isAdmin = _deriveBool(seedA, 8);
        uint256 adminCount = _deriveUint(seedA, 9);
        uint256 votingThreshold = _deriveUint(seedA, 10);

        address deployer = _deriveAddress(seedA, 11);

        uint256 groupId = _deriveUint(seedA, 12);
        address groupMember = _deriveAddress(seedA, 13);
        bool groupExists = _deriveBool(seedA, 14);
        bool groupMemberStatus = _deriveBool(seedA, 15);
        bool groupDeleted = _deriveBool(seedA, 16);

        address guardian = _deriveAddress(seedA, 17);
        bool guardianReady = _deriveBool(seedA, 18);
        address pendingGuardian = _deriveAddress(seedA, 19);
        uint256 pendingGuardianTimestamp = _deriveUint(seedA, 20);
        uint256 guardianUpdateAttemptId = _deriveUint(seedA, 29);

        address member = _deriveAddress(seedA, 21);
        bool memberStatus = _deriveBool(seedA, 22);

        bytes32 policiesRoot = keccak256(abi.encode(seedA, "policiesRoot"));
        bytes32 usageKey = keccak256(abi.encode(seedA, "usageKey"));
        uint256 usageWindow = _deriveUint(seedA, 23);
        uint256 usageValue = _deriveUint(seedA, 24);

        uint256 nonce = _deriveUint(seedA, 25);
        bool nonceUsed = _deriveBool(seedA, 26);

        address upgradeWhitelist = _deriveAddress(seedA, 27);
        address authorizedUpgradeImplementation = _deriveAddress(seedA, 28);

        TxRecoveryState memory txRecoveryState = _buildTxRecoveryState(
            _deriveAddress(seedB, 1),
            _deriveBool(seedB, 2),
            _deriveUint(seedB, 3),
            _deriveUint(seedB, 4),
            _deriveAddress(seedB, 5),
            _deriveUint(seedB, 6),
            _deriveUint(seedB, 7)
        );

        GuardianRecoveryState memory guardianRecoveryState = _buildGuardianRecoveryState(
            _deriveAddress(seedB, 8),
            _deriveBool(seedB, 9),
            _deriveAddress(seedB, 10),
            _deriveUint(seedB, 11),
            _deriveUint(seedB, 12),
            _deriveAddress(seedB, 13),
            _deriveUint(seedB, 14),
            _deriveUint(seedB, 15)
        );

        harness.setImplementationWhitelisted(contractType, implementation, isWhitelisted);
        harness.setDeployedAccount(deployedAccount, isDeployedAccount);
        harness.setAccountImplementation(accountImplementation);
        harness.setAdminOperationTimelockDurationSeconds(adminOperationTimelockDuration);
        harness.setAdminStatus(admin, isAdmin);
        harness.setAdminCount(adminCount);
        harness.setVotingThreshold(votingThreshold);
        harness.setDeployerAddress(deployer);
        harness.setGroupExists(groupId, groupExists);
        harness.setGroupMember(groupId, groupMember, groupMemberStatus);
        harness.setWasGroupDeleted(groupId, groupDeleted);
        harness.setGuardianState(
            guardian, guardianReady, pendingGuardian, pendingGuardianTimestamp, guardianUpdateAttemptId
        );
        harness.setMemberStatus(member, memberStatus);
        harness.setPoliciesRoot(policiesRoot);
        harness.setPolicyUsage(usageKey, usageWindow, usageValue);
        harness.setUsedNonce(nonce, nonceUsed);
        harness.setUpgradeState(upgradeWhitelist, authorizedUpgradeImplementation);
        harness.setTxRecoveryState(txRecoveryState);
        harness.setGuardianRecoveryState(guardianRecoveryState);

        assertEq(
            harness.isImplementationWhitelisted(contractType, implementation),
            isWhitelisted,
            "whitelisted mapping mismatch"
        );
        assertEq(harness.isDeployedAccount(deployedAccount), isDeployedAccount, "deployedAccounts mapping mismatch");
        assertEq(harness.getAccountImplementation(), accountImplementation, "accountImplementation mismatch");
        assertEq(
            harness.getAdminOperationTimelockDurationSeconds(),
            adminOperationTimelockDuration,
            "adminOperationTimelockDurationSeconds mismatch"
        );
        assertEq(harness.getAdminStatus(admin), isAdmin, "isAdmin mapping mismatch");
        assertEq(harness.getAdminCount(), adminCount, "adminCount mismatch");
        assertEq(harness.getVotingThreshold(), votingThreshold, "votingThreshold mismatch");
        assertEq(harness.getDeployerAddress(), deployer, "deployerAddress mismatch");
        assertEq(harness.isGroup(groupId), groupExists, "isGroup mapping mismatch");
        assertEq(harness.isGroupMember(groupId, groupMember), groupMemberStatus, "isGroupMember mapping mismatch");
        assertEq(harness.wasGroupDeleted(groupId), groupDeleted, "wasGroupDeleted mapping mismatch");

        (
            address actualGuardian,
            bool actualGuardianReady,
            address actualPendingGuardian,
            uint256 actualPendingTimestamp,
            uint256 actualAttemptId
        ) = harness.getGuardianState();
        assertEq(actualGuardian, guardian, "guardian mismatch");
        assertEq(actualGuardianReady, guardianReady, "isGuardianUpdateReadyForAcceptance mismatch");
        assertEq(actualPendingGuardian, pendingGuardian, "pendingGuardian mismatch");
        assertEq(actualPendingTimestamp, pendingGuardianTimestamp, "pendingGuardianUpdateTimestamp mismatch");
        assertEq(actualAttemptId, guardianUpdateAttemptId, "guardianUpdateAttemptId mismatch");

        assertEq(harness.getMemberStatus(member), memberStatus, "isMember mapping mismatch");
        assertEq(harness.getPoliciesRoot(), policiesRoot, "policiesRoot mismatch");
        assertEq(harness.getPolicyUsage(usageKey, usageWindow), usageValue, "policyUsage mismatch");
        assertEq(harness.getUsedNonce(nonce), nonceUsed, "usedNonces mapping mismatch");

        (address actualWhitelist, address actualAuthorizedImplementation) = harness.getUpgradeState();
        assertEq(actualWhitelist, upgradeWhitelist, "whitelistAddress mismatch");
        assertEq(
            actualAuthorizedImplementation, authorizedUpgradeImplementation, "authorizedUpgradeImplementation mismatch"
        );

        _assertTxRecoveryStateEquals(harness.getTxRecoveryState(), txRecoveryState);
        _assertGuardianRecoveryStateEquals(harness.getGuardianRecoveryState(), guardianRecoveryState);
    }

    /**
     * @dev Verifies that all mapping entries across every storage namespace round-trip correctly under fuzzed keys and
     * values.
     */
    function testFuzz_mappingKeysAndValues_areStoredDeterministically(
        address admin,
        bool isAdminStatus,
        address member,
        bool isMemberStatus,
        uint256 groupId,
        address groupMember,
        bool isGroupMemberStatus,
        bytes32 policyUsageKey,
        uint256 policyWindow,
        uint256 policyUsageAmount,
        uint256 nonce,
        bool isNonceUsed,
        uint8 contractTypeRaw,
        address implementation,
        bool isWhitelisted
    ) public {
        ContractType contractType = ContractType(contractTypeRaw % 2);

        harness.setAdminStatus(admin, isAdminStatus);
        harness.setMemberStatus(member, isMemberStatus);
        harness.setGroupMember(groupId, groupMember, isGroupMemberStatus);
        harness.setPolicyUsage(policyUsageKey, policyWindow, policyUsageAmount);
        harness.setUsedNonce(nonce, isNonceUsed);
        harness.setImplementationWhitelisted(contractType, implementation, isWhitelisted);

        assertEq(harness.getAdminStatus(admin), isAdminStatus, "isAdmin mapping mismatch");
        assertEq(harness.getMemberStatus(member), isMemberStatus, "isMember mapping mismatch");
        assertEq(harness.isGroupMember(groupId, groupMember), isGroupMemberStatus, "isGroupMember mapping mismatch");
        assertEq(
            harness.getPolicyUsage(policyUsageKey, policyWindow), policyUsageAmount, "policyUsage mapping mismatch"
        );
        assertEq(harness.getUsedNonce(nonce), isNonceUsed, "usedNonces mapping mismatch");
        assertEq(
            harness.isImplementationWhitelisted(contractType, implementation),
            isWhitelisted,
            "whitelisted mapping mismatch"
        );
    }
}
