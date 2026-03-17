// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {
    LibImplementationWhitelistStorage
} from "implementation-whitelist/libraries/storage/LibImplementationWhitelistStorage.sol";
import {
    LibOrganizationAccountFactoryStorage
} from "organization/libraries/storage/LibOrganizationAccountFactoryStorage.sol";
import {
    LibOrganizationAdminOperationTimelockStorage
} from "organization/libraries/storage/LibOrganizationAdminOperationTimelockStorage.sol";
import {LibOrganizationAdminStorage} from "organization/libraries/storage/LibOrganizationAdminStorage.sol";
import {
    LibOrganizationDeployerAddressStorage
} from "organization/libraries/storage/LibOrganizationDeployerAddressStorage.sol";
import {LibOrganizationGroupsStorage} from "organization/libraries/storage/LibOrganizationGroupsStorage.sol";
import {LibOrganizationGuardianStorage} from "organization/libraries/storage/LibOrganizationGuardianStorage.sol";
import {LibOrganizationMembersStorage} from "organization/libraries/storage/LibOrganizationMembersStorage.sol";
import {LibOrganizationPolicyStorage} from "organization/libraries/storage/LibOrganizationPolicyStorage.sol";
import {LibOrganizationRecoveryStorage} from "organization/libraries/storage/LibOrganizationRecoveryStorage.sol";
import {LibOrganizationSignaturesStorage} from "organization/libraries/storage/LibOrganizationSignaturesStorage.sol";
import {LibOrganizationUpgradeStorage} from "organization/libraries/storage/LibOrganizationUpgradeStorage.sol";
import {ContractType} from "types/CommonTypes.sol";
import {GuardianRecoveryState, PendingRecoveryInitTimelock, TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Storage Layout Harness
 *      Exposes typed set/get wrappers for every storage library under test.
 *      This harness writes directly through each storage library's `layout()` pointer,
 *      allowing deterministic assertions for variable-level read/write coverage.
 */
contract StorageLayoutHarness {
    /**
     * @dev Sets implementation whitelist status.
     * @param contractType Contract type enum key.
     * @param implementation Implementation address key.
     * @param isWhitelisted Whitelist status to store.
     */
    function setImplementationWhitelisted(ContractType contractType, address implementation, bool isWhitelisted)
        external
    {
        LibImplementationWhitelistStorage.layout().whitelisted[contractType][implementation] = isWhitelisted;
    }

    /**
     * @dev Reads implementation whitelist status.
     * @param contractType Contract type enum key.
     * @param implementation Implementation address key.
     * @return True when the pair is whitelisted.
     */
    function isImplementationWhitelisted(ContractType contractType, address implementation)
        external
        view
        returns (bool)
    {
        return LibImplementationWhitelistStorage.layout().whitelisted[contractType][implementation];
    }

    /**
     * @dev Sets deployed account status for an account address.
     * @param account Account address key.
     * @param isDeployed Stored deployment status.
     */
    function setDeployedAccount(address account, bool isDeployed) external {
        LibOrganizationAccountFactoryStorage.layout().deployedAccounts[account] = isDeployed;
    }

    /**
     * @dev Reads deployed account status for an account address.
     * @param account Account address key.
     * @return True when account is marked as deployed.
     */
    function isDeployedAccount(address account) external view returns (bool) {
        return LibOrganizationAccountFactoryStorage.layout().deployedAccounts[account];
    }

    /**
     * @dev Sets the account implementation address.
     * @param accountImplementation Implementation address to store.
     */
    function setAccountImplementation(address accountImplementation) external {
        LibOrganizationAccountFactoryStorage.layout().accountImplementation = accountImplementation;
    }

    /**
     * @dev Reads the account implementation address.
     * @return The stored account implementation.
     */
    function getAccountImplementation() external view returns (address) {
        return LibOrganizationAccountFactoryStorage.layout().accountImplementation;
    }

    /**
     * @dev Sets the organization-wide admin operation timelock duration.
     * @param durationSeconds Timelock duration in seconds.
     */
    function setAdminOperationTimelockDurationSeconds(uint256 durationSeconds) external {
        LibOrganizationAdminOperationTimelockStorage.layout().adminOperationTimelockDurationSeconds = durationSeconds;
    }

    /**
     * @dev Reads the organization-wide admin operation timelock duration.
     * @return Timelock duration in seconds.
     */
    function getAdminOperationTimelockDurationSeconds() external view returns (uint256) {
        return LibOrganizationAdminOperationTimelockStorage.layout().adminOperationTimelockDurationSeconds;
    }

    /**
     * @dev Sets admin status for an address.
     * @param admin Address key.
     * @param isAdmin Stored admin status.
     */
    function setAdminStatus(address admin, bool isAdmin) external {
        LibOrganizationAdminStorage.layout().isAdmin[admin] = isAdmin;
    }

    /**
     * @dev Reads admin status for an address.
     * @param admin Address key.
     * @return True when address is admin.
     */
    function getAdminStatus(address admin) external view returns (bool) {
        return LibOrganizationAdminStorage.layout().isAdmin[admin];
    }

    /**
     * @dev Sets admin count scalar.
     * @param adminCount Admin count value.
     */
    function setAdminCount(uint256 adminCount) external {
        LibOrganizationAdminStorage.layout().adminCount = adminCount;
    }

    /**
     * @dev Reads admin count scalar.
     * @return Stored admin count.
     */
    function getAdminCount() external view returns (uint256) {
        return LibOrganizationAdminStorage.layout().adminCount;
    }

    /**
     * @dev Sets voting threshold scalar.
     * @param votingThreshold Voting threshold value.
     */
    function setVotingThreshold(uint256 votingThreshold) external {
        LibOrganizationAdminStorage.layout().votingThreshold = votingThreshold;
    }

    /**
     * @dev Reads voting threshold scalar.
     * @return Stored voting threshold.
     */
    function getVotingThreshold() external view returns (uint256) {
        return LibOrganizationAdminStorage.layout().votingThreshold;
    }

    /**
     * @dev Sets deployer address scalar.
     * @param deployerAddress Deployer address value.
     */
    function setDeployerAddress(address deployerAddress) external {
        LibOrganizationDeployerAddressStorage.layout().deployerAddress = deployerAddress;
    }

    /**
     * @dev Reads deployer address scalar.
     * @return Stored deployer address.
     */
    function getDeployerAddress() external view returns (address) {
        return LibOrganizationDeployerAddressStorage.layout().deployerAddress;
    }

    /**
     * @dev Sets `isGroup` status for a group id.
     * @param groupId Group id key.
     * @param groupExists Stored group existence status.
     */
    function setGroupExists(uint256 groupId, bool groupExists) external {
        LibOrganizationGroupsStorage.layout().isGroup[groupId] = groupExists;
    }

    /**
     * @dev Reads `isGroup` status for a group id.
     * @param groupId Group id key.
     * @return True when group exists.
     */
    function isGroup(uint256 groupId) external view returns (bool) {
        return LibOrganizationGroupsStorage.layout().isGroup[groupId];
    }

    /**
     * @dev Sets group membership status.
     * @param groupId Group id key.
     * @param member Member address key.
     * @param isMember Stored membership status.
     */
    function setGroupMember(uint256 groupId, address member, bool isMember) external {
        LibOrganizationGroupsStorage.layout().isGroupMember[groupId][member] = isMember;
    }

    /**
     * @dev Reads group membership status.
     * @param groupId Group id key.
     * @param member Member address key.
     * @return True when member belongs to the group.
     */
    function isGroupMember(uint256 groupId, address member) external view returns (bool) {
        return LibOrganizationGroupsStorage.layout().isGroupMember[groupId][member];
    }

    /**
     * @dev Sets `wasGroupDeleted` status for a group id.
     * @param groupId Group id key.
     * @param wasDeleted Stored deletion status.
     */
    function setWasGroupDeleted(uint256 groupId, bool wasDeleted) external {
        LibOrganizationGroupsStorage.layout().wasGroupDeleted[groupId] = wasDeleted;
    }

    /**
     * @dev Reads `wasGroupDeleted` status for a group id.
     * @param groupId Group id key.
     * @return True when group id has been deleted.
     */
    function wasGroupDeleted(uint256 groupId) external view returns (bool) {
        return LibOrganizationGroupsStorage.layout().wasGroupDeleted[groupId];
    }

    /**
     * @dev Sets all guardian namespace fields.
     * @param guardian Guardian address.
     * @param isUpdateReadyForAcceptance Ready-for-acceptance flag.
     * @param pendingGuardian Pending guardian address.
     * @param pendingGuardianUpdateTimestamp Pending guardian timestamp.
     */
    function setGuardianState(
        address guardian,
        bool isUpdateReadyForAcceptance,
        address pendingGuardian,
        uint256 pendingGuardianUpdateTimestamp
    ) external {
        LibOrganizationGuardianStorage.Layout storage layout = LibOrganizationGuardianStorage.layout();
        layout.guardian = guardian;
        layout.isGuardianUpdateReadyForAcceptance = isUpdateReadyForAcceptance;
        layout.pendingGuardian = pendingGuardian;
        layout.pendingGuardianUpdateTimestamp = pendingGuardianUpdateTimestamp;
    }

    /**
     * @dev Reads all guardian namespace fields.
     * @return guardian Guardian address.
     * @return isUpdateReadyForAcceptance Ready-for-acceptance flag.
     * @return pendingGuardian Pending guardian address.
     * @return pendingGuardianUpdateTimestamp Pending guardian timestamp.
     */
    function getGuardianState() external view returns (address, bool, address, uint256) {
        LibOrganizationGuardianStorage.Layout storage layout = LibOrganizationGuardianStorage.layout();
        return (
            layout.guardian,
            layout.isGuardianUpdateReadyForAcceptance,
            layout.pendingGuardian,
            layout.pendingGuardianUpdateTimestamp
        );
    }

    /**
     * @dev Sets member status for an address.
     * @param member Member address key.
     * @param isMember Stored membership status.
     */
    function setMemberStatus(address member, bool isMember) external {
        LibOrganizationMembersStorage.layout().isMember[member] = isMember;
    }

    /**
     * @dev Reads member status for an address.
     * @param member Member address key.
     * @return True when address is an organization member.
     */
    function getMemberStatus(address member) external view returns (bool) {
        return LibOrganizationMembersStorage.layout().isMember[member];
    }

    /**
     * @dev Sets policies merkle root.
     * @param policiesRoot Policies root value.
     */
    function setPoliciesRoot(bytes32 policiesRoot) external {
        LibOrganizationPolicyStorage.layout().policiesRoot = policiesRoot;
    }

    /**
     * @dev Reads policies merkle root.
     * @return Stored policies root.
     */
    function getPoliciesRoot() external view returns (bytes32) {
        return LibOrganizationPolicyStorage.layout().policiesRoot;
    }

    /**
     * @dev Sets policy usage value.
     * @param usageKey Usage key mapping key.
     * @param timeWindow Time window mapping key.
     * @param usage Usage amount value.
     */
    function setPolicyUsage(bytes32 usageKey, uint256 timeWindow, uint256 usage) external {
        LibOrganizationPolicyStorage.layout().policyUsage[usageKey][timeWindow] = usage;
    }

    /**
     * @dev Reads policy usage value.
     * @param usageKey Usage key mapping key.
     * @param timeWindow Time window mapping key.
     * @return Stored usage amount.
     */
    function getPolicyUsage(bytes32 usageKey, uint256 timeWindow) external view returns (uint256) {
        return LibOrganizationPolicyStorage.layout().policyUsage[usageKey][timeWindow];
    }

    /**
     * @dev Sets nonce usage status.
     * @param nonce Nonce mapping key.
     * @param isUsed Nonce usage status.
     */
    function setUsedNonce(uint256 nonce, bool isUsed) external {
        LibOrganizationSignaturesStorage.layout().usedNonces[nonce] = isUsed;
    }

    /**
     * @dev Reads nonce usage status.
     * @param nonce Nonce mapping key.
     * @return True when nonce is marked used.
     */
    function getUsedNonce(uint256 nonce) external view returns (bool) {
        return LibOrganizationSignaturesStorage.layout().usedNonces[nonce];
    }

    /**
     * @dev Sets both upgrade namespace fields.
     * @param whitelistAddress Whitelist contract address.
     * @param authorizedUpgradeImplementation Authorized Organization upgrade target.
     */
    function setUpgradeState(address whitelistAddress, address authorizedUpgradeImplementation) external {
        LibOrganizationUpgradeStorage.Layout storage layout = LibOrganizationUpgradeStorage.layout();
        layout.whitelistAddress = whitelistAddress;
        layout.authorizedUpgradeImplementation = authorizedUpgradeImplementation;
    }

    /**
     * @dev Reads both upgrade namespace fields.
     * @return whitelistAddress Whitelist contract address.
     * @return authorizedUpgradeImplementation Authorized Organization upgrade target.
     */
    function getUpgradeState() external view returns (address, address) {
        LibOrganizationUpgradeStorage.Layout storage layout = LibOrganizationUpgradeStorage.layout();
        return (layout.whitelistAddress, layout.authorizedUpgradeImplementation);
    }

    /**
     * @dev Sets full tx recovery state, including nested pending-init fields.
     * @param state Tx recovery state struct to store.
     */
    function setTxRecoveryState(TxRecoveryState calldata state) external {
        LibOrganizationRecoveryStorage.layout().txRecovery = state;
    }

    /**
     * @dev Reads full tx recovery state.
     * @return The stored tx recovery struct.
     */
    function getTxRecoveryState() external view returns (TxRecoveryState memory) {
        return LibOrganizationRecoveryStorage.layout().txRecovery;
    }

    /**
     * @dev Sets full guardian recovery state, including nested pending-init fields.
     * @param state Guardian recovery state struct to store.
     */
    function setGuardianRecoveryState(GuardianRecoveryState calldata state) external {
        LibOrganizationRecoveryStorage.layout().guardianRecovery = state;
    }

    /**
     * @dev Reads full guardian recovery state.
     * @return The stored guardian recovery struct.
     */
    function getGuardianRecoveryState() external view returns (GuardianRecoveryState memory) {
        return LibOrganizationRecoveryStorage.layout().guardianRecovery;
    }
}

/**
 * @dev UUPS Storage Layout Implementation V1
 *      Upgradeable implementation used to test delegatecall persistence and UUPS upgrades.
 *      Intentionally has open upgrade authorization for deterministic test flow.
 */
contract StorageLayoutUUPSImplementationV1 is StorageLayoutHarness, UUPSUpgradeable {
    /**
     * @dev Returns implementation version marker.
     * @return Version number for test assertions.
     */
    function implementationVersion() external pure virtual returns (uint256) {
        return 1;
    }

    /**
     * @dev UUPS authorization hook.
     *      Deliberately unrestricted for test-only upgrade flow.
     * @param newImplementation Address of the new implementation.
     */
    function _authorizeUpgrade(address newImplementation) internal pure override {
        (newImplementation);
    }
}

/**
 * @dev UUPS Storage Layout Implementation V2
 *      Second implementation version used to verify storage persistence across upgrade.
 */
contract StorageLayoutUUPSImplementationV2 is StorageLayoutUUPSImplementationV1 {
    /**
     * @dev Returns implementation version marker.
     * @return Version number for test assertions.
     */
    function implementationVersion() external pure override returns (uint256) {
        return 2;
    }
}

/**
 * @dev Test Beacon
 *      Minimal beacon for Account beacon-slot helper testing.
 */
contract TestBeacon is IBeacon {
    /// @dev Current implementation returned by the beacon.
    address internal _implementation;

    /**
     * @dev Initializes the beacon.
     * @param implementation_ Initial implementation address.
     */
    constructor(address implementation_) {
        _implementation = implementation_;
    }

    /**
     * @dev Returns the current implementation.
     * @return Implementation address.
     */
    function implementation() external view returns (address) {
        return _implementation;
    }

    /**
     * @dev Updates beacon implementation.
     * @param newImplementation New implementation address.
     */
    function setImplementation(address newImplementation) external {
        _implementation = newImplementation;
    }
}

/**
 * @dev Storage Layout Invariant Handler
 *      Stateful fuzz handler for storage namespace isolation invariants.
 *      Each mutator writes exactly one namespace and updates expected tracked values
 *      for that namespace only. Invariant assertions compare tracked values in storage
 *      against these expected mirrors to detect cross-namespace mutation.
 */
contract StorageLayoutInvariantHandler {
    /// @dev Harness instance under invariant fuzzing.
    StorageLayoutHarness public immutable HARNESS;

    /// @dev Tracked implementation key for whitelist mapping assertions.
    address public constant TRACKED_IMPLEMENTATION = address(0xA110CE);

    /// @dev Tracked account key for deployedAccounts mapping assertions.
    address public constant TRACKED_ACCOUNT = address(0xACC07);

    /// @dev Tracked admin key for isAdmin mapping assertions.
    address public constant TRACKED_ADMIN = address(0xAD0001);

    /// @dev Tracked member key for members/group-membership assertions.
    address public constant TRACKED_MEMBER = address(0xA50001);

    /// @dev Tracked group id key for groups mappings assertions.
    uint256 public constant TRACKED_GROUP_ID = 77;

    /// @dev Tracked policy usage key.
    bytes32 public constant TRACKED_POLICY_USAGE_KEY = keccak256("tracked.policy.usage");

    /// @dev Tracked policy window key.
    uint256 public constant TRACKED_POLICY_WINDOW = 9;

    /// @dev Tracked nonce key.
    uint256 public constant TRACKED_NONCE = 111;

    /// @dev Expected whitelist status for (Account, TRACKED_IMPLEMENTATION).
    bool public expectedWhitelistAccount;

    /// @dev Expected whitelist status for (Organization, TRACKED_IMPLEMENTATION).
    bool public expectedWhitelistOrganization;

    /// @dev Expected deployed status for TRACKED_ACCOUNT.
    bool public expectedTrackedAccountDeployed;

    /// @dev Expected account implementation scalar.
    address public expectedAccountImplementation;

    /// @dev Expected admin operation timelock scalar.
    uint256 public expectedAdminOperationTimelockDurationSeconds;

    /// @dev Expected admin status for TRACKED_ADMIN.
    bool public expectedTrackedAdminStatus;

    /// @dev Expected adminCount scalar.
    uint256 public expectedAdminCount;

    /// @dev Expected votingThreshold scalar.
    uint256 public expectedVotingThreshold;

    /// @dev Expected deployer address scalar.
    address public expectedDeployerAddress;

    /// @dev Expected isGroup value for TRACKED_GROUP_ID.
    bool public expectedTrackedGroupExists;

    /// @dev Expected isGroupMember value for (TRACKED_GROUP_ID, TRACKED_MEMBER).
    bool public expectedTrackedGroupMember;

    /// @dev Expected wasGroupDeleted value for TRACKED_GROUP_ID.
    bool public expectedTrackedGroupWasDeleted;

    /// @dev Expected guardian scalar.
    address public expectedGuardian;

    /// @dev Expected guardian ready-for-acceptance flag.
    bool public expectedGuardianReadyForAcceptance;

    /// @dev Expected pending guardian scalar.
    address public expectedPendingGuardian;

    /// @dev Expected pending guardian timestamp scalar.
    uint256 public expectedPendingGuardianUpdateTimestamp;

    /// @dev Expected isMember value for TRACKED_MEMBER.
    bool public expectedTrackedMemberStatus;

    /// @dev Expected policies root scalar.
    bytes32 public expectedPoliciesRoot;

    /// @dev Expected policy usage value for tracked key pair.
    uint256 public expectedTrackedPolicyUsage;

    /// @dev Expected used nonce value for TRACKED_NONCE.
    bool public expectedTrackedNonceUsed;

    /// @dev Expected upgrade whitelist address scalar.
    address public expectedUpgradeWhitelistAddress;

    /// @dev Expected authorized Organization upgrade target scalar.
    address public expectedAuthorizedUpgradeImplementation;

    /// @dev Expected tx recovery address.
    address public expectedTxRecoveryAddress;

    /// @dev Expected tx recovery enabled flag.
    bool public expectedTxRecoveryEnabled;

    /// @dev Expected tx recovery timelock scalar.
    uint256 public expectedTxRecoveryTimelockDurationSeconds;

    /// @dev Expected tx pending enable timestamp scalar.
    uint256 public expectedTxRecoveryPendingEnableTimestamp;

    /// @dev Expected tx pending init recovery address.
    address public expectedTxPendingInitRecoveryAddress;

    /// @dev Expected tx pending init timelock scalar.
    uint256 public expectedTxPendingInitTimelockDurationSeconds;

    /// @dev Expected tx pending init timestamp scalar.
    uint256 public expectedTxPendingInitTimestamp;

    /// @dev Expected guardian recovery address.
    address public expectedGuardianRecoveryAddress;

    /// @dev Expected guardian recovery ready-for-acceptance flag.
    bool public expectedGuardianRecoveryReadyForAcceptance;

    /// @dev Expected guardian recovery pending guardian.
    address public expectedGuardianRecoveryPendingGuardian;

    /// @dev Expected guardian recovery timelock scalar.
    uint256 public expectedGuardianRecoveryTimelockDurationSeconds;

    /// @dev Expected guardian recovery pending guardian timestamp scalar.
    uint256 public expectedGuardianRecoveryPendingGuardianTimestamp;

    /// @dev Expected guardian pending init recovery address.
    address public expectedGuardianPendingInitRecoveryAddress;

    /// @dev Expected guardian pending init timelock scalar.
    uint256 public expectedGuardianPendingInitTimelockDurationSeconds;

    /// @dev Expected guardian pending init timestamp scalar.
    uint256 public expectedGuardianPendingInitTimestamp;

    /**
     * @dev Initializes handler and seeds tracked values.
     * @param harness_ Harness contract to mutate during invariant fuzzing.
     */
    constructor(StorageLayoutHarness harness_) {
        HARNESS = harness_;
        _seedExpectedAndStorage();
    }

    /**
     * @dev Mutates implementation whitelist namespace.
     * @param contractTypeRaw Raw contract type selector (mod 2).
     * @param implementation Mapping key address.
     * @param isWhitelisted Value to store.
     */
    function writeImplementationWhitelist(uint8 contractTypeRaw, address implementation, bool isWhitelisted) external {
        ContractType contractType = ContractType(contractTypeRaw % 2);

        HARNESS.setImplementationWhitelisted(contractType, implementation, isWhitelisted);

        if (implementation == TRACKED_IMPLEMENTATION) {
            if (contractType == ContractType.Account) {
                expectedWhitelistAccount = isWhitelisted;
            } else {
                expectedWhitelistOrganization = isWhitelisted;
            }
        }
    }

    /**
     * @dev Mutates account-factory namespace.
     * @param account Mapping key for deployedAccounts.
     * @param isDeployed Deployment status value.
     * @param accountImplementation Account implementation scalar.
     */
    function writeAccountFactory(address account, bool isDeployed, address accountImplementation) external {
        HARNESS.setDeployedAccount(account, isDeployed);
        HARNESS.setAccountImplementation(accountImplementation);

        if (account == TRACKED_ACCOUNT) {
            expectedTrackedAccountDeployed = isDeployed;
        }
        expectedAccountImplementation = accountImplementation;
    }

    /**
     * @dev Mutates admin-operation-timelock namespace.
     * @param durationSeconds Timelock value.
     */
    function writeAdminOperationTimelock(uint256 durationSeconds) external {
        HARNESS.setAdminOperationTimelockDurationSeconds(durationSeconds);
        expectedAdminOperationTimelockDurationSeconds = durationSeconds;
    }

    /**
     * @dev Mutates admin namespace.
     * @param admin Mapping key for isAdmin.
     * @param isAdminStatus Mapping value for isAdmin.
     * @param adminCount Scalar adminCount value.
     * @param votingThreshold Scalar votingThreshold value.
     */
    function writeAdmin(address admin, bool isAdminStatus, uint256 adminCount, uint256 votingThreshold) external {
        HARNESS.setAdminStatus(admin, isAdminStatus);
        HARNESS.setAdminCount(adminCount);
        HARNESS.setVotingThreshold(votingThreshold);

        if (admin == TRACKED_ADMIN) {
            expectedTrackedAdminStatus = isAdminStatus;
        }
        expectedAdminCount = adminCount;
        expectedVotingThreshold = votingThreshold;
    }

    /**
     * @dev Mutates deployer namespace.
     * @param deployerAddress Deployer scalar value.
     */
    function writeDeployer(address deployerAddress) external {
        HARNESS.setDeployerAddress(deployerAddress);
        expectedDeployerAddress = deployerAddress;
    }

    /**
     * @dev Mutates groups namespace.
     * @param groupId Group id mapping key.
     * @param member Member mapping key.
     * @param isGroupStatus Value for isGroup[groupId].
     * @param isGroupMemberStatus Value for isGroupMember[groupId][member].
     * @param wasDeleted Value for wasGroupDeleted[groupId].
     */
    function writeGroups(uint256 groupId, address member, bool isGroupStatus, bool isGroupMemberStatus, bool wasDeleted)
        external
    {
        HARNESS.setGroupExists(groupId, isGroupStatus);
        HARNESS.setGroupMember(groupId, member, isGroupMemberStatus);
        HARNESS.setWasGroupDeleted(groupId, wasDeleted);

        if (groupId == TRACKED_GROUP_ID) {
            expectedTrackedGroupExists = isGroupStatus;
            expectedTrackedGroupWasDeleted = wasDeleted;

            if (member == TRACKED_MEMBER) {
                expectedTrackedGroupMember = isGroupMemberStatus;
            }
        }
    }

    /**
     * @dev Mutates guardian namespace.
     * @param guardian Guardian scalar value.
     * @param isReady Ready-for-acceptance flag.
     * @param pendingGuardian Pending guardian scalar value.
     * @param pendingGuardianUpdateTimestamp Pending timestamp scalar value.
     */
    function writeGuardian(
        address guardian,
        bool isReady,
        address pendingGuardian,
        uint256 pendingGuardianUpdateTimestamp
    ) external {
        HARNESS.setGuardianState(guardian, isReady, pendingGuardian, pendingGuardianUpdateTimestamp);

        expectedGuardian = guardian;
        expectedGuardianReadyForAcceptance = isReady;
        expectedPendingGuardian = pendingGuardian;
        expectedPendingGuardianUpdateTimestamp = pendingGuardianUpdateTimestamp;
    }

    /**
     * @dev Mutates members namespace.
     * @param member Member mapping key.
     * @param isMemberStatus Member mapping value.
     */
    function writeMembers(address member, bool isMemberStatus) external {
        HARNESS.setMemberStatus(member, isMemberStatus);

        if (member == TRACKED_MEMBER) {
            expectedTrackedMemberStatus = isMemberStatus;
        }
    }

    /**
     * @dev Mutates policy namespace.
     * @param policiesRoot Policies root scalar value.
     * @param usageKey Usage key mapping key.
     * @param timeWindow Time window mapping key.
     * @param usageAmount Usage mapping value.
     */
    function writePolicy(bytes32 policiesRoot, bytes32 usageKey, uint256 timeWindow, uint256 usageAmount) external {
        HARNESS.setPoliciesRoot(policiesRoot);
        HARNESS.setPolicyUsage(usageKey, timeWindow, usageAmount);

        expectedPoliciesRoot = policiesRoot;
        if (usageKey == TRACKED_POLICY_USAGE_KEY && timeWindow == TRACKED_POLICY_WINDOW) {
            expectedTrackedPolicyUsage = usageAmount;
        }
    }

    /**
     * @dev Mutates signatures namespace.
     * @param nonce Nonce mapping key.
     * @param isUsed Nonce mapping value.
     */
    function writeSignatures(uint256 nonce, bool isUsed) external {
        HARNESS.setUsedNonce(nonce, isUsed);

        if (nonce == TRACKED_NONCE) {
            expectedTrackedNonceUsed = isUsed;
        }
    }

    /**
     * @dev Mutates upgrade namespace.
     * @param whitelistAddress Whitelist scalar value.
     * @param authorizedUpgradeImplementation Authorized target scalar value.
     */
    function writeUpgrade(address whitelistAddress, address authorizedUpgradeImplementation) external {
        HARNESS.setUpgradeState(whitelistAddress, authorizedUpgradeImplementation);

        expectedUpgradeWhitelistAddress = whitelistAddress;
        expectedAuthorizedUpgradeImplementation = authorizedUpgradeImplementation;
    }

    /**
     * @dev Mutates tx-recovery namespace subtree.
     * @param recoveryAddress txRecovery.recoveryAddress.
     * @param isEnabled txRecovery.isEnabled.
     * @param timelockDurationSeconds txRecovery.timelockDurationSeconds.
     * @param pendingEnableTimestamp txRecovery.pendingEnableTimestamp.
     * @param pendingRecoveryAddress txRecovery.pendingInit.pendingRecoveryAddress.
     * @param pendingTimelockDurationSeconds txRecovery.pendingInit.pendingTimelockDurationSeconds.
     * @param pendingTimestamp txRecovery.pendingInit.pendingTimestamp.
     */
    function writeTxRecovery(
        address recoveryAddress,
        bool isEnabled,
        uint256 timelockDurationSeconds,
        uint256 pendingEnableTimestamp,
        address pendingRecoveryAddress,
        uint256 pendingTimelockDurationSeconds,
        uint256 pendingTimestamp
    ) external {
        TxRecoveryState memory txRecoveryState = TxRecoveryState({
            recoveryAddress: recoveryAddress,
            isEnabled: isEnabled,
            timelockDurationSeconds: timelockDurationSeconds,
            pendingEnableTimestamp: pendingEnableTimestamp,
            pendingInit: _buildPendingRecoveryInit(
                pendingRecoveryAddress, pendingTimelockDurationSeconds, pendingTimestamp
            )
        });

        HARNESS.setTxRecoveryState(txRecoveryState);

        expectedTxRecoveryAddress = recoveryAddress;
        expectedTxRecoveryEnabled = isEnabled;
        expectedTxRecoveryTimelockDurationSeconds = timelockDurationSeconds;
        expectedTxRecoveryPendingEnableTimestamp = pendingEnableTimestamp;
        expectedTxPendingInitRecoveryAddress = pendingRecoveryAddress;
        expectedTxPendingInitTimelockDurationSeconds = pendingTimelockDurationSeconds;
        expectedTxPendingInitTimestamp = pendingTimestamp;
    }

    /**
     * @dev Mutates guardian-recovery namespace subtree.
     * @param recoveryAddress guardianRecovery.recoveryAddress.
     * @param isUpdateReadyForAcceptance guardianRecovery.isUpdateReadyForAcceptance.
     * @param pendingGuardian guardianRecovery.pendingGuardian.
     * @param timelockDurationSeconds guardianRecovery.timelockDurationSeconds.
     * @param pendingGuardianTimestamp guardianRecovery.pendingGuardianTimestamp.
     * @param pendingRecoveryAddress guardianRecovery.pendingInit.pendingRecoveryAddress.
     * @param pendingTimelockDurationSeconds guardianRecovery.pendingInit.pendingTimelockDurationSeconds.
     * @param pendingTimestamp guardianRecovery.pendingInit.pendingTimestamp.
     */
    function writeGuardianRecovery(
        address recoveryAddress,
        bool isUpdateReadyForAcceptance,
        address pendingGuardian,
        uint256 timelockDurationSeconds,
        uint256 pendingGuardianTimestamp,
        address pendingRecoveryAddress,
        uint256 pendingTimelockDurationSeconds,
        uint256 pendingTimestamp
    ) external {
        GuardianRecoveryState memory guardianRecoveryState = GuardianRecoveryState({
            recoveryAddress: recoveryAddress,
            isUpdateReadyForAcceptance: isUpdateReadyForAcceptance,
            pendingGuardian: pendingGuardian,
            timelockDurationSeconds: timelockDurationSeconds,
            pendingGuardianTimestamp: pendingGuardianTimestamp,
            pendingInit: _buildPendingRecoveryInit(
                pendingRecoveryAddress, pendingTimelockDurationSeconds, pendingTimestamp
            )
        });

        HARNESS.setGuardianRecoveryState(guardianRecoveryState);

        expectedGuardianRecoveryAddress = recoveryAddress;
        expectedGuardianRecoveryReadyForAcceptance = isUpdateReadyForAcceptance;
        expectedGuardianRecoveryPendingGuardian = pendingGuardian;
        expectedGuardianRecoveryTimelockDurationSeconds = timelockDurationSeconds;
        expectedGuardianRecoveryPendingGuardianTimestamp = pendingGuardianTimestamp;
        expectedGuardianPendingInitRecoveryAddress = pendingRecoveryAddress;
        expectedGuardianPendingInitTimelockDurationSeconds = pendingTimelockDurationSeconds;
        expectedGuardianPendingInitTimestamp = pendingTimestamp;
    }

    /**
     * @dev Seeds tracked values in both harness storage and expected mirror state.
     */
    function _seedExpectedAndStorage() internal {
        expectedWhitelistAccount = true;
        expectedWhitelistOrganization = false;
        expectedTrackedAccountDeployed = true;
        expectedAccountImplementation = address(0xAC0011);
        expectedAdminOperationTimelockDurationSeconds = 3 days;
        expectedTrackedAdminStatus = true;
        expectedAdminCount = 5;
        expectedVotingThreshold = 3;
        expectedDeployerAddress = address(0xD3E10E2);
        expectedTrackedGroupExists = true;
        expectedTrackedGroupMember = true;
        expectedTrackedGroupWasDeleted = false;
        expectedGuardian = address(0x6001);
        expectedGuardianReadyForAcceptance = true;
        expectedPendingGuardian = address(0x6002);
        expectedPendingGuardianUpdateTimestamp = 123_456;
        expectedTrackedMemberStatus = true;
        expectedPoliciesRoot = keccak256("seed.policies.root");
        expectedTrackedPolicyUsage = 77;
        expectedTrackedNonceUsed = true;
        expectedUpgradeWhitelistAddress = address(0x7001);
        expectedAuthorizedUpgradeImplementation = address(0x7002);

        expectedTxRecoveryAddress = address(0x8001);
        expectedTxRecoveryEnabled = true;
        expectedTxRecoveryTimelockDurationSeconds = 4 days;
        expectedTxRecoveryPendingEnableTimestamp = 222_333;
        expectedTxPendingInitRecoveryAddress = address(0x8002);
        expectedTxPendingInitTimelockDurationSeconds = 6 days;
        expectedTxPendingInitTimestamp = 444_555;

        expectedGuardianRecoveryAddress = address(0x9001);
        expectedGuardianRecoveryReadyForAcceptance = true;
        expectedGuardianRecoveryPendingGuardian = address(0x9002);
        expectedGuardianRecoveryTimelockDurationSeconds = 7 days;
        expectedGuardianRecoveryPendingGuardianTimestamp = 777_888;
        expectedGuardianPendingInitRecoveryAddress = address(0x9003);
        expectedGuardianPendingInitTimelockDurationSeconds = 8 days;
        expectedGuardianPendingInitTimestamp = 999_111;

        HARNESS.setImplementationWhitelisted(ContractType.Account, TRACKED_IMPLEMENTATION, expectedWhitelistAccount);
        HARNESS.setImplementationWhitelisted(
            ContractType.Organization, TRACKED_IMPLEMENTATION, expectedWhitelistOrganization
        );

        HARNESS.setDeployedAccount(TRACKED_ACCOUNT, expectedTrackedAccountDeployed);
        HARNESS.setAccountImplementation(expectedAccountImplementation);

        HARNESS.setAdminOperationTimelockDurationSeconds(expectedAdminOperationTimelockDurationSeconds);
        HARNESS.setAdminStatus(TRACKED_ADMIN, expectedTrackedAdminStatus);
        HARNESS.setAdminCount(expectedAdminCount);
        HARNESS.setVotingThreshold(expectedVotingThreshold);

        HARNESS.setDeployerAddress(expectedDeployerAddress);

        HARNESS.setGroupExists(TRACKED_GROUP_ID, expectedTrackedGroupExists);
        HARNESS.setGroupMember(TRACKED_GROUP_ID, TRACKED_MEMBER, expectedTrackedGroupMember);
        HARNESS.setWasGroupDeleted(TRACKED_GROUP_ID, expectedTrackedGroupWasDeleted);

        HARNESS.setGuardianState(
            expectedGuardian,
            expectedGuardianReadyForAcceptance,
            expectedPendingGuardian,
            expectedPendingGuardianUpdateTimestamp
        );

        HARNESS.setMemberStatus(TRACKED_MEMBER, expectedTrackedMemberStatus);

        HARNESS.setPoliciesRoot(expectedPoliciesRoot);
        HARNESS.setPolicyUsage(TRACKED_POLICY_USAGE_KEY, TRACKED_POLICY_WINDOW, expectedTrackedPolicyUsage);

        HARNESS.setUsedNonce(TRACKED_NONCE, expectedTrackedNonceUsed);

        HARNESS.setUpgradeState(expectedUpgradeWhitelistAddress, expectedAuthorizedUpgradeImplementation);

        TxRecoveryState memory txRecoveryState = TxRecoveryState({
            recoveryAddress: expectedTxRecoveryAddress,
            isEnabled: expectedTxRecoveryEnabled,
            timelockDurationSeconds: expectedTxRecoveryTimelockDurationSeconds,
            pendingEnableTimestamp: expectedTxRecoveryPendingEnableTimestamp,
            pendingInit: _buildPendingRecoveryInit(
                expectedTxPendingInitRecoveryAddress,
                expectedTxPendingInitTimelockDurationSeconds,
                expectedTxPendingInitTimestamp
            )
        });
        HARNESS.setTxRecoveryState(txRecoveryState);

        GuardianRecoveryState memory guardianRecoveryState = GuardianRecoveryState({
            recoveryAddress: expectedGuardianRecoveryAddress,
            isUpdateReadyForAcceptance: expectedGuardianRecoveryReadyForAcceptance,
            pendingGuardian: expectedGuardianRecoveryPendingGuardian,
            timelockDurationSeconds: expectedGuardianRecoveryTimelockDurationSeconds,
            pendingGuardianTimestamp: expectedGuardianRecoveryPendingGuardianTimestamp,
            pendingInit: _buildPendingRecoveryInit(
                expectedGuardianPendingInitRecoveryAddress,
                expectedGuardianPendingInitTimelockDurationSeconds,
                expectedGuardianPendingInitTimestamp
            )
        });
        HARNESS.setGuardianRecoveryState(guardianRecoveryState);
    }

    /**
     * @dev Builds the shared pending recovery init sub-struct.
     * @param pendingRecoveryAddress Pending recovery address.
     * @param pendingTimelockDurationSeconds Pending timelock duration.
     * @param pendingTimestamp Pending timestamp.
     * @return pendingRecoveryInitTimelock The constructed sub-struct.
     */
    function _buildPendingRecoveryInit(
        address pendingRecoveryAddress,
        uint256 pendingTimelockDurationSeconds,
        uint256 pendingTimestamp
    ) internal pure returns (PendingRecoveryInitTimelock memory pendingRecoveryInitTimelock) {
        pendingRecoveryInitTimelock.pendingRecoveryAddress = pendingRecoveryAddress;
        pendingRecoveryInitTimelock.pendingTimelockDurationSeconds = pendingTimelockDurationSeconds;
        pendingRecoveryInitTimelock.pendingTimestamp = pendingTimestamp;
    }
}
