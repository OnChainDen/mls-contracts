// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";

import {StorageLayoutFuzzDerivationHelpers} from "test/helpers/storage/StorageLayoutFuzzDerivationHelpers.sol";
import {StorageLayoutHarness} from "test/helpers/storage/StorageLayoutHarnesses.sol";
import {StorageLayoutRecoveryBuilders} from "test/helpers/storage/StorageLayoutRecoveryBuilders.sol";
import {StorageLayoutSlots} from "test/helpers/storage/StorageLayoutSlots.sol";
import {ContractType} from "types/CommonTypes.sol";
import {GuardianRecoveryState, TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Base Test contract for storage layout tests.
 *      Contains shared fixtures and helper utilities for storage layout tests.
 */
abstract contract StorageLayoutTestBase is Test, StorageLayoutRecoveryBuilders, StorageLayoutFuzzDerivationHelpers {
    /// @dev Harness used for direct storage-library read/write tests.
    StorageLayoutHarness internal harness;

    /// @dev ERC-1967 implementation slot constant.
    bytes32 internal constant ERC1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @dev ERC-1967 admin slot constant.
    bytes32 internal constant ERC1967_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /// @dev ERC-1967 beacon slot constant.
    bytes32 internal constant ERC1967_BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    /// @dev OpenZeppelin Initializable ERC-7201 namespace.
    string internal constant OZ_INITIALIZABLE_NAMESPACE = "openzeppelin.storage.Initializable";

    /// @dev OpenZeppelin OwnableUpgradeable ERC-7201 namespace.
    string internal constant OZ_OWNABLE_UPGRADEABLE_NAMESPACE = "openzeppelin.storage.Ownable";

    /// @dev Deterministic test fixture key for implementation-whitelist assertions.
    address internal constant TEST_IMPLEMENTATION = address(0x101);

    /// @dev Deterministic test fixture key for deployed account assertions.
    address internal constant TEST_DEPLOYED_ACCOUNT = address(0x102);

    /// @dev Deterministic test fixture account implementation for account-factory namespace.
    address internal constant TEST_ACCOUNT_IMPLEMENTATION = address(0x103);

    /// @dev Deterministic test fixture key for admin mapping assertions.
    address internal constant TEST_ADMIN = address(0x104);

    /// @dev Deterministic test fixture deployer value.
    address internal constant TEST_DEPLOYER = address(0x105);

    /// @dev Deterministic test fixture group id.
    uint256 internal constant TEST_GROUP_ID = 11;

    /// @dev Deterministic test fixture member key for members/group-membership assertions.
    address internal constant TEST_MEMBER = address(0x106);

    /// @dev Deterministic test fixture guardian value.
    address internal constant TEST_GUARDIAN = address(0x107);

    /// @dev Deterministic test fixture pending guardian value.
    address internal constant TEST_PENDING_GUARDIAN = address(0x108);

    /// @dev Deterministic test fixture policies root.
    bytes32 internal constant TEST_POLICIES_ROOT = keccak256("storage-layout.test-fixture.policies-root");

    /// @dev Deterministic test fixture policy usage key.
    bytes32 internal constant TEST_POLICY_USAGE_KEY = keccak256("storage-layout.test-fixture.policy-usage");

    /// @dev Deterministic test fixture policy usage window.
    uint256 internal constant TEST_POLICY_WINDOW = 1111;

    /// @dev Deterministic test fixture nonce key.
    uint256 internal constant TEST_NONCE = 2222;

    /// @dev Deterministic test fixture whitelist address for upgrade namespace.
    address internal constant TEST_UPGRADE_WHITELIST = address(0x109);

    /**
     * @dev Deploys the storage harness for test contracts.
     */
    function setUp() public virtual {
        harness = new StorageLayoutHarness();
    }

    /**
     * @dev Returns all project ERC-7201 storage slots covered by the storage layout plan.
     */
    function _allProjectStorageSlots() internal pure returns (bytes32[] memory slots) {
        return StorageLayoutSlots.allProjectStorageSlots();
    }

    /**
     * @dev Asserts that no slot in `slots` equals `forbiddenSlot`.
     * @param slots Candidate slots to validate.
     * @param forbiddenSlot Slot that must not collide.
     * @param slotLabel Human-readable label used in assertion errors.
     */
    function _assertNoCollisionWithSlot(bytes32[] memory slots, bytes32 forbiddenSlot, string memory slotLabel)
        internal
        pure
    {
        for (uint256 i = 0; i < slots.length; i++) {
            assertTrue(slots[i] != forbiddenSlot, string.concat("Slot collision detected with ", slotLabel));
        }
    }

    /**
     * @dev Writes deterministic test fixture values to every storage namespace.
     * @param target Harness or proxy-backed harness instance.
     */
    function _writeTestFixtureValues(StorageLayoutHarness target) internal {
        target.setImplementationWhitelisted(ContractType.Account, TEST_IMPLEMENTATION, true);
        target.setDeployedAccount(TEST_DEPLOYED_ACCOUNT, true);
        target.setAccountImplementation(TEST_ACCOUNT_IMPLEMENTATION);
        target.setAdminOperationTimelockDurationSeconds(7 days);
        target.setAdminStatus(TEST_ADMIN, true);
        target.setAdminCount(12);
        target.setVotingThreshold(8);
        target.setDeployerAddress(TEST_DEPLOYER);
        target.setGroupExists(TEST_GROUP_ID, true);
        target.setGroupMember(TEST_GROUP_ID, TEST_MEMBER, true);
        target.setWasGroupDeleted(TEST_GROUP_ID + 1, true);
        target.setGuardianState(TEST_GUARDIAN, true, TEST_PENDING_GUARDIAN, 987_654, 42);
        target.setMemberStatus(TEST_MEMBER, true);
        target.setPoliciesRoot(TEST_POLICIES_ROOT);
        target.setPolicyUsage(TEST_POLICY_USAGE_KEY, TEST_POLICY_WINDOW, 8888);
        target.setUsedNonce(TEST_NONCE, true);
        target.setUpgradeState(TEST_UPGRADE_WHITELIST, TEST_IMPLEMENTATION);

        target.setTxRecoveryState(
            _buildTxRecoveryState(address(0xE001), true, 2 days, 111_222, address(0xE002), 3 days, 333_444)
        );
        target.setGuardianRecoveryState(
            _buildGuardianRecoveryState(
                address(0xE003), true, address(0xE004), 4 days, 555_666, address(0xE005), 5 days, 777_888
            )
        );
    }

    /**
     * @dev Asserts deterministic test fixture values previously written to every namespace.
     * @param target Harness or proxy-backed harness instance.
     */
    function _assertTestFixtureValues(StorageLayoutHarness target) internal {
        assertTrue(
            target.isImplementationWhitelisted(ContractType.Account, TEST_IMPLEMENTATION),
            "whitelisted test fixture value mismatch"
        );
        assertTrue(target.isDeployedAccount(TEST_DEPLOYED_ACCOUNT), "deployedAccounts test fixture mismatch");
        assertEq(
            target.getAccountImplementation(),
            TEST_ACCOUNT_IMPLEMENTATION,
            "accountImplementation test fixture mismatch"
        );
        assertEq(
            target.getAdminOperationTimelockDurationSeconds(),
            7 days,
            "adminOperationTimelockDurationSeconds test fixture mismatch"
        );
        assertTrue(target.getAdminStatus(TEST_ADMIN), "isAdmin test fixture mismatch");
        assertEq(target.getAdminCount(), 12, "adminCount test fixture mismatch");
        assertEq(target.getVotingThreshold(), 8, "votingThreshold test fixture mismatch");
        assertEq(target.getDeployerAddress(), TEST_DEPLOYER, "deployerAddress test fixture mismatch");
        assertTrue(target.isGroup(TEST_GROUP_ID), "isGroup test fixture mismatch");
        assertTrue(target.isGroupMember(TEST_GROUP_ID, TEST_MEMBER), "isGroupMember test fixture mismatch");
        assertTrue(target.wasGroupDeleted(TEST_GROUP_ID + 1), "wasGroupDeleted test fixture mismatch");

        // forgefmt: disable-next-item
        (address guardian, bool ready, address pendingGuardian, uint256 pendingTimestamp, uint256 attemptId) =
            target.getGuardianState();
        assertEq(guardian, TEST_GUARDIAN, "guardian test fixture mismatch");
        assertTrue(ready, "isGuardianUpdateReadyForAcceptance test fixture mismatch");
        assertEq(pendingGuardian, TEST_PENDING_GUARDIAN, "pendingGuardian test fixture mismatch");
        assertEq(pendingTimestamp, 987_654, "pendingGuardianUpdateTimestamp test fixture mismatch");
        assertEq(attemptId, 42, "guardianUpdateAttemptId test fixture mismatch");

        assertTrue(target.getMemberStatus(TEST_MEMBER), "isMember test fixture mismatch");
        assertEq(target.getPoliciesRoot(), TEST_POLICIES_ROOT, "policiesRoot test fixture mismatch");
        assertEq(
            target.getPolicyUsage(TEST_POLICY_USAGE_KEY, TEST_POLICY_WINDOW), 8888, "policyUsage test fixture mismatch"
        );
        assertTrue(target.getUsedNonce(TEST_NONCE), "usedNonces test fixture mismatch");

        (address whitelistAddress, address authorizedUpgradeImplementation) = target.getUpgradeState();
        assertEq(whitelistAddress, TEST_UPGRADE_WHITELIST, "whitelistAddress test fixture mismatch");
        assertEq(
            authorizedUpgradeImplementation,
            TEST_IMPLEMENTATION,
            "authorizedUpgradeImplementation test fixture mismatch"
        );

        _assertTxRecoveryStateEquals(
            target.getTxRecoveryState(),
            _buildTxRecoveryState(address(0xE001), true, 2 days, 111_222, address(0xE002), 3 days, 333_444)
        );
        _assertGuardianRecoveryStateEquals(
            target.getGuardianRecoveryState(),
            _buildGuardianRecoveryState(
                address(0xE003), true, address(0xE004), 4 days, 555_666, address(0xE005), 5 days, 777_888
            )
        );
    }

    /**
     * @dev Asserts tx recovery structs are identical field-by-field.
     */
    function _assertTxRecoveryStateEquals(TxRecoveryState memory actual, TxRecoveryState memory expected)
        internal
        pure
    {
        assertEq(actual.recoveryAddress, expected.recoveryAddress, "txRecovery.recoveryAddress mismatch");
        assertEq(actual.isEnabled, expected.isEnabled, "txRecovery.isEnabled mismatch");
        assertEq(
            actual.timelockDurationSeconds,
            expected.timelockDurationSeconds,
            "txRecovery.timelockDurationSeconds mismatch"
        );
        assertEq(
            actual.pendingEnableTimestamp, expected.pendingEnableTimestamp, "txRecovery.pendingEnableTimestamp mismatch"
        );
        assertEq(
            actual.pendingInit.pendingRecoveryAddress,
            expected.pendingInit.pendingRecoveryAddress,
            "txRecovery.pendingInit.pendingRecoveryAddress mismatch"
        );
        assertEq(
            actual.pendingInit.pendingTimelockDurationSeconds,
            expected.pendingInit.pendingTimelockDurationSeconds,
            "txRecovery.pendingInit.pendingTimelockDurationSeconds mismatch"
        );
        assertEq(
            actual.pendingInit.pendingTimestamp,
            expected.pendingInit.pendingTimestamp,
            "txRecovery.pendingInit.pendingTimestamp mismatch"
        );
        assertEq(actual.initAttemptId, expected.initAttemptId, "txRecovery.initAttemptId mismatch");
    }

    /**
     * @dev Asserts guardian recovery structs are identical field-by-field.
     */
    function _assertGuardianRecoveryStateEquals(
        GuardianRecoveryState memory actual,
        GuardianRecoveryState memory expected
    ) internal pure {
        assertEq(actual.recoveryAddress, expected.recoveryAddress, "guardianRecovery.recoveryAddress mismatch");
        assertEq(
            actual.isUpdateReadyForAcceptance,
            expected.isUpdateReadyForAcceptance,
            "guardianRecovery.isUpdateReadyForAcceptance mismatch"
        );
        assertEq(actual.pendingGuardian, expected.pendingGuardian, "guardianRecovery.pendingGuardian mismatch");
        assertEq(
            actual.timelockDurationSeconds,
            expected.timelockDurationSeconds,
            "guardianRecovery.timelockDurationSeconds mismatch"
        );
        assertEq(
            actual.pendingGuardianTimestamp,
            expected.pendingGuardianTimestamp,
            "guardianRecovery.pendingGuardianTimestamp mismatch"
        );
        assertEq(
            actual.pendingInit.pendingRecoveryAddress,
            expected.pendingInit.pendingRecoveryAddress,
            "guardianRecovery.pendingInit.pendingRecoveryAddress mismatch"
        );
        assertEq(
            actual.pendingInit.pendingTimelockDurationSeconds,
            expected.pendingInit.pendingTimelockDurationSeconds,
            "guardianRecovery.pendingInit.pendingTimelockDurationSeconds mismatch"
        );
        assertEq(
            actual.pendingInit.pendingTimestamp,
            expected.pendingInit.pendingTimestamp,
            "guardianRecovery.pendingInit.pendingTimestamp mismatch"
        );
        assertEq(actual.initAttemptId, expected.initAttemptId, "guardianRecovery.initAttemptId mismatch");
    }
}
