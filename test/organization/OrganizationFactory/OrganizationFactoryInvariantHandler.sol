// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {AccountImplementation} from "account/AccountImplementation.sol";
import {IOrganizationInitialization} from "interfaces/organization/IOrganizationInitialization.sol";
import {OrganizationProxy} from "organization/OrganizationProxy.sol";
import {
    InitializationWhitelistMock,
    OrganizationFactoryHarness,
    OrganizationImplementationHarness
} from "test/organization/OrganizationFactory/OrganizationFactoryHarnesses.sol";
import {ContractType, GroupModification, GroupModificationType, InitializationParams} from "types/CommonTypes.sol";

/**
 * @dev Stateful handler for initialization invariants.
 */
contract OrganizationFactoryInvariantHandler {
    struct DeploymentRecord {
        address organization;
        bytes32 salt;
        uint256 groupId;
        address adminA;
        address adminB;
        address groupMemberA;
        address groupMemberB;
        uint256 votingThreshold;
        address expectedDeployer;
        bool viaFactory;
    }

    struct FailedDirectInitRecord {
        address proxy;
        uint256 groupId;
        address memberA;
        address memberB;
        address adminA;
        address adminB;
        address expectedDeployer;
    }

    uint256 internal constant MAX_SUCCESSFUL_TRACKED = 24;
    uint256 internal constant MAX_FAILED_FACTORY_TRACKED = 24;
    uint256 internal constant MAX_FAILED_DIRECT_TRACKED = 24;

    OrganizationFactoryHarness internal immutable FACTORY;
    OrganizationImplementationHarness internal immutable IMPLEMENTATION;
    AccountImplementation internal immutable ACCOUNT_IMPLEMENTATION;
    InitializationWhitelistMock internal immutable WHITELIST;

    DeploymentRecord[] internal deploymentRecords;
    FailedDirectInitRecord[] internal failedDirectInitRecords;
    address[] internal failedFactoryAddresses;

    mapping(address => bool) internal isTrackedDeployment;
    mapping(address => bool) internal isTrackedFailedFactoryAddress;

    bool public reinitializeSucceeded;
    bool public unexpectedFailedFactorySuccess;
    bool public unexpectedFailedDirectInitSuccess;
    bool public failedFactoryRevertLeftCode;

    /// @dev Deploys invariant dependencies and configures whitelist entries used by handler actions.
    constructor() {
        WHITELIST = new InitializationWhitelistMock();
        IMPLEMENTATION = new OrganizationImplementationHarness();
        ACCOUNT_IMPLEMENTATION = new AccountImplementation();
        FACTORY = new OrganizationFactoryHarness(address(this));

        WHITELIST.setImplementationWhitelisted(ContractType.Organization, address(IMPLEMENTATION), true);
        WHITELIST.setImplementationWhitelisted(ContractType.Account, address(ACCOUNT_IMPLEMENTATION), true);
    }

    /// @dev Attempts factory deployment with valid params and tracks successful unique organizations.
    /// @param salt CREATE2 salt used for the factory deployment attempt.
    /// @param seed Entropy seed used to derive deterministic valid initialization params.
    function deployFactoryOrganization(bytes32 salt, uint256 seed) external {
        // Bound tracked state growth so invariant runs stay cheap and deterministic.
        if (deploymentRecords.length >= MAX_SUCCESSFUL_TRACKED) {
            return;
        }

        InitializationParams memory params = _buildValidParams(seed);

        // Ignore expected sporadic failures from collision/revert branches and only track successes.
        try FACTORY.deployOrganization(salt, address(IMPLEMENTATION), address(WHITELIST), params) returns (
            address organization
        ) {
            _trackSuccessfulDeployment(organization, salt, params, address(FACTORY), true);
        } catch {}
    }

    /// @dev Deploys a proxy directly and attempts initialization through the handler as deployer.
    /// @param seed Entropy seed used to derive deterministic valid initialization params.
    function deployDirectProxyAndInitialize(uint256 seed) external {
        if (deploymentRecords.length >= MAX_SUCCESSFUL_TRACKED) {
            return;
        }

        address proxy = address(new OrganizationProxy(address(IMPLEMENTATION), address(WHITELIST)));
        InitializationParams memory params = _buildValidParams(seed);

        // Successful direct-init deployments are tracked with `viaFactory = false`.
        try IOrganizationInitialization(proxy).initialize(params) {
            _trackSuccessfulDeployment(proxy, bytes32(0), params, address(this), false);
        } catch {}
    }

    /// @dev Attempts an intentionally invalid factory deployment and records rollback behavior at computed addresses.
    /// @param salt CREATE2 salt used for the failing deployment attempt.
    /// @param seed Entropy seed used to derive params before injecting an invalid guardian.
    function attemptFailedFactoryDeployment(bytes32 salt, uint256 seed) external {
        if (failedFactoryAddresses.length >= MAX_FAILED_FACTORY_TRACKED) {
            return;
        }

        InitializationParams memory params = _buildValidParams(seed);
        // Force initialization failure by violating guardian validation.
        params.guardian = address(0);

        address computed = FACTORY.computeOrganizationAddress(salt, address(IMPLEMENTATION), address(WHITELIST));
        // Skip already-deployed tuples; this path only validates failure rollback on empty targets.
        if (computed.code.length != 0) {
            return;
        }

        try FACTORY.deployOrganization(salt, address(IMPLEMENTATION), address(WHITELIST), params) returns (address) {
            unexpectedFailedFactorySuccess = true;
        } catch {
            // A revert must not leave code behind at the computed CREATE2 address.
            if (computed.code.length != 0) {
                failedFactoryRevertLeftCode = true;
            } else if (!isTrackedFailedFactoryAddress[computed]) {
                isTrackedFailedFactoryAddress[computed] = true;
                failedFactoryAddresses.push(computed);
            }
        }
    }

    /// @dev Attempts direct initialization with intentionally invalid params and records expected failures.
    /// @param seed Entropy seed used to derive params before injecting an invalid guardian.
    function attemptFailedDirectInitialization(uint256 seed) external {
        if (failedDirectInitRecords.length >= MAX_FAILED_DIRECT_TRACKED) {
            return;
        }

        address proxy = address(new OrganizationProxy(address(IMPLEMENTATION), address(WHITELIST)));
        InitializationParams memory params = _buildValidParams(seed);
        params.guardian = address(0);

        try IOrganizationInitialization(proxy).initialize(params) {
            unexpectedFailedDirectInitSuccess = true;
        } catch {
            // Capture identifying fields so invariants can verify rollback and deployer expectations.
            failedDirectInitRecords.push(
                FailedDirectInitRecord({
                    proxy: proxy,
                    groupId: params.groups[0].groupId,
                    memberA: params.members[0],
                    memberB: params.members[1],
                    adminA: params.admins[0],
                    adminB: params.admins[1],
                    expectedDeployer: address(this)
                })
            );
        }
    }

    /// @dev Attempts to reinitialize a previously successful deployment and flags unexpected success.
    /// @param indexSeed Entropy used to select a tracked deployment record.
    /// @param seed Entropy seed used to derive a fresh initialization payload for reinit attempt.
    function attemptReinitializeExisting(uint256 indexSeed, uint256 seed) external {
        uint256 length = deploymentRecords.length;
        if (length == 0) {
            return;
        }

        DeploymentRecord memory record = deploymentRecords[indexSeed % length];
        InitializationParams memory params = _buildValidParams(seed);

        try IOrganizationInitialization(record.organization).initialize(params) {
            reinitializeSucceeded = true;
        } catch {}
    }

    /// @dev Returns the number of tracked successful deployment records.
    /// @return Number of entries currently stored in `deploymentRecords`.
    function deploymentRecordsLength() external view returns (uint256) {
        return deploymentRecords.length;
    }

    /// @dev Returns a tracked successful deployment record by index.
    /// @param index Zero-based index into `deploymentRecords`.
    /// @return Deployment record at the requested index.
    function deploymentRecordAt(uint256 index) external view returns (DeploymentRecord memory) {
        return deploymentRecords[index];
    }

    /// @dev Returns the number of unique failed-factory computed addresses tracked.
    /// @return Number of entries currently stored in `failedFactoryAddresses`.
    function failedFactoryAddressesLength() external view returns (uint256) {
        return failedFactoryAddresses.length;
    }

    /// @dev Returns a tracked failed-factory computed address by index.
    /// @param index Zero-based index into `failedFactoryAddresses`.
    /// @return Failed-factory computed address at the requested index.
    function failedFactoryAddressAt(uint256 index) external view returns (address) {
        return failedFactoryAddresses[index];
    }

    /// @dev Returns the number of tracked failed direct-initialization records.
    /// @return Number of entries currently stored in `failedDirectInitRecords`.
    function failedDirectInitRecordsLength() external view returns (uint256) {
        return failedDirectInitRecords.length;
    }

    /// @dev Returns a tracked failed direct-initialization record by index.
    /// @param index Zero-based index into `failedDirectInitRecords`.
    /// @return Failed direct-initialization record at the requested index.
    function failedDirectInitRecordAt(uint256 index) external view returns (FailedDirectInitRecord memory) {
        return failedDirectInitRecords[index];
    }

    /// @dev Exposes the factory address used by handler actions.
    /// @return Address of the handler-owned factory harness.
    function factoryAddress() external view returns (address) {
        return address(FACTORY);
    }

    /// @dev Exposes the organization implementation address used by handler actions.
    /// @return Address of the shared organization implementation harness.
    function implementationAddress() external view returns (address) {
        return address(IMPLEMENTATION);
    }

    /// @dev Exposes the whitelist address used by handler actions.
    /// @return Address of the shared whitelist mock.
    function whitelistAddress() external view returns (address) {
        return address(WHITELIST);
    }

    /// @dev Stores a successful deployment once, along with fields used by invariants for cross-checks.
    /// @param organization Deployed organization address to track.
    /// @param salt CREATE2 salt used for factory deployments, or zero for direct deployments.
    /// @param params Initialization params that produced the deployment.
    /// @param expectedDeployer Deployer address expected to be stored by the deployment path.
    /// @param viaFactory Whether the deployment path used the factory.
    function _trackSuccessfulDeployment(
        address organization,
        bytes32 salt,
        InitializationParams memory params,
        address expectedDeployer,
        bool viaFactory
    ) internal {
        // Keep one canonical record per organization to avoid duplicate invariant samples.
        if (isTrackedDeployment[organization]) {
            return;
        }

        isTrackedDeployment[organization] = true;
        // Persist a compact snapshot of fields invariants assert across deployment paths.
        deploymentRecords.push(
            DeploymentRecord({
                organization: organization,
                salt: salt,
                groupId: params.groups[0].groupId,
                adminA: params.admins[0],
                adminB: params.admins[1],
                groupMemberA: params.groups[0].membersToAdd[0],
                groupMemberB: params.groups[0].membersToAdd[1],
                votingThreshold: params.votingThreshold,
                expectedDeployer: expectedDeployer,
                viaFactory: viaFactory
            })
        );
    }

    /// @dev Builds a deterministic valid initialization payload from a seed for invariant state transitions.
    /// @param seed Entropy source used to derive addresses, group id, threshold, and optional recovery config.
    /// @return params Valid initialization params accepted by both factory and direct proxy flows.
    function _buildValidParams(uint256 seed) internal view returns (InitializationParams memory params) {
        // Derive disjoint participant addresses from the seed.
        address memberA = _deriveAddress(seed, 1);
        address memberB = _deriveAddress(seed, 2);
        address adminA = _deriveAddress(seed, 3);
        address adminB = _deriveAddress(seed, 4);
        address guardian = _deriveAddress(seed, 5);

        // Constrain group and threshold choices to valid ranges.
        uint256 groupId = 10_000 + (seed % 5000);
        uint256 threshold = seed % 2 == 0 ? 1 : 2;

        // Build members/admins such that admins are always members.
        params.members = new address[](4);
        params.members[0] = memberA;
        params.members[1] = memberB;
        params.members[2] = adminA;
        params.members[3] = adminB;

        params.admins = new address[](2);
        params.admins[0] = adminA;
        params.admins[1] = adminB;
        params.votingThreshold = threshold;

        // Seed one create-group operation with valid members.
        address[] memory groupMembers = new address[](2);
        groupMembers[0] = memberA;
        groupMembers[1] = adminA;
        address[] memory emptyMembers = new address[](0);

        params.groups = new GroupModification[](1);
        params.groups[0] = GroupModification({
            groupId: groupId,
            modificationType: GroupModificationType.Create,
            membersToAdd: groupMembers,
            membersToRemove: emptyMembers
        });

        // Set core initialization values and selectively include optional recovery modules.
        params.guardian = guardian;
        params.accountImplementation = address(ACCOUNT_IMPLEMENTATION);
        params.adminOperationTimelockDurationSeconds = seed % 3 == 0 ? 30 days : 2 days;

        params.transactionAndERC1271RecoveryAddress = seed % 2 == 0 ? _deriveAddress(seed, 6) : address(0);
        params.txRecoveryTimelockDurationSeconds = 2 days;

        params.guardianRecoveryAddress = seed % 5 == 0 ? address(0) : _deriveAddress(seed, 7);
        params.guardianRecoveryTimelockDurationSeconds = 2 days;
    }

    /// @dev Derives a non-zero deterministic address from a seed/nonce pair.
    /// @param seed Entropy seed for address derivation.
    /// @param nonce Per-seed nonce to derive distinct addresses.
    /// @return Derived non-zero address.
    function _deriveAddress(uint256 seed, uint256 nonce) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encode(seed, nonce))) | uint256(1)));
    }
}
