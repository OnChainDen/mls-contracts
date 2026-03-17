// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {IImplementationWhitelist} from "interfaces/IImplementationWhitelist.sol";
import {OrganizationImplementation} from "organization/OrganizationImplementation.sol";
import {LibOrganizationAdmin} from "organization/libraries/LibOrganizationAdmin.sol";
import {
    LibOrganizationAccountFactoryStorage
} from "organization/libraries/storage/LibOrganizationAccountFactoryStorage.sol";
import {LibOrganizationAdminStorage} from "organization/libraries/storage/LibOrganizationAdminStorage.sol";
import {LibOrganizationGroupsStorage} from "organization/libraries/storage/LibOrganizationGroupsStorage.sol";
import {LibOrganizationGuardianStorage} from "organization/libraries/storage/LibOrganizationGuardianStorage.sol";
import {LibOrganizationMembersStorage} from "organization/libraries/storage/LibOrganizationMembersStorage.sol";
import {LibOrganizationPolicyStorage} from "organization/libraries/storage/LibOrganizationPolicyStorage.sol";
import {LibOrganizationRecoveryStorage} from "organization/libraries/storage/LibOrganizationRecoveryStorage.sol";
import {LibOrganizationSignaturesStorage} from "organization/libraries/storage/LibOrganizationSignaturesStorage.sol";
import {LibOrganizationUpgradeStorage} from "organization/libraries/storage/LibOrganizationUpgradeStorage.sol";
import {ContractType, OperationType} from "types/CommonTypes.sol";
import {GuardianRecoveryState, TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Dedicated namespaced storage for upgrade-specific migration probes in tests.
 */
library LibOrganizationUpgradeTestStorage {
    struct Layout {
        uint256 marker;
    }

    bytes32 internal constant STORAGE_LOCATION = 0x4ee5e2bbdbf6078f7de57fb1e8a69d36543917b97548229f8dcdd572f8c7f000;

    function layout() internal pure returns (Layout storage _layout) {
        assembly {
            _layout.slot := STORAGE_LOCATION
        }
    }
}

/**
 * @dev Test harness for `OrganizationImplementation` with direct state accessors and migration helpers.
 */
contract OrganizationImplementationHarness is OrganizationImplementation {
    error MigrationCallReverted();
    error UpgradeFlagNotSet();

    function setGuardian(address guardianAddress) external {
        LibOrganizationGuardianStorage.layout().guardian = guardianAddress;
    }

    function setMemberStatus(address member, bool isMember) external {
        LibOrganizationMembersStorage.layout().isMember[member] = isMember;
    }

    function getMemberStatus(address member) external view returns (bool) {
        return LibOrganizationMembersStorage.layout().isMember[member];
    }

    function setGroupStatus(uint256 groupId, bool isGroup) external {
        LibOrganizationGroupsStorage.layout().isGroup[groupId] = isGroup;
    }

    function getGroupStatus(uint256 groupId) external view returns (bool) {
        return LibOrganizationGroupsStorage.layout().isGroup[groupId];
    }

    function setGroupMemberStatus(uint256 groupId, address member, bool isGroupMember) external {
        LibOrganizationGroupsStorage.layout().isGroupMember[groupId][member] = isGroupMember;
    }

    function getGroupMemberStatus(uint256 groupId, address member) external view returns (bool) {
        return LibOrganizationGroupsStorage.layout().isGroupMember[groupId][member];
    }

    function setAdminStatus(address admin, bool isAdmin) external {
        LibOrganizationAdminStorage.layout().isAdmin[admin] = isAdmin;
    }

    function getAdminStatus(address admin) external view returns (bool) {
        return LibOrganizationAdminStorage.layout().isAdmin[admin];
    }

    function setAdminCount(uint256 count) external {
        LibOrganizationAdminStorage.layout().adminCount = count;
    }

    function setVotingThreshold(uint256 threshold) external {
        LibOrganizationAdminStorage.layout().votingThreshold = threshold;
    }

    function setUsedNonce(uint256 nonce, bool isUsed) external {
        LibOrganizationSignaturesStorage.layout().usedNonces[nonce] = isUsed;
    }

    function getUsedNonce(uint256 nonce) external view returns (bool) {
        return LibOrganizationSignaturesStorage.layout().usedNonces[nonce];
    }

    function getAdminOperationHash(
        OperationType operationType,
        bytes calldata operationData,
        uint256 salt,
        uint256 expirationTimestamp,
        bool isApproval
    ) external view returns (bytes32) {
        return LibOrganizationAdmin._getAdminOperationHash(
            operationType, operationData, salt, expirationTimestamp, isApproval
        );
    }

    function setUpgradeState(address whitelistAddress, address authorizedUpgradeImplementation) external {
        LibOrganizationUpgradeStorage.layout().whitelistAddress = whitelistAddress;
        LibOrganizationUpgradeStorage.layout().authorizedUpgradeImplementation = authorizedUpgradeImplementation;
    }

    function getUpgradeState()
        external
        view
        returns (address whitelistAddress, address authorizedUpgradeImplementation)
    {
        whitelistAddress = LibOrganizationUpgradeStorage.layout().whitelistAddress;
        authorizedUpgradeImplementation = LibOrganizationUpgradeStorage.layout().authorizedUpgradeImplementation;
    }

    function setAccountImplementationStorage(address accountImplementation) external {
        LibOrganizationAccountFactoryStorage.layout().accountImplementation = accountImplementation;
    }

    function getAccountImplementationStorage() external view returns (address) {
        return LibOrganizationAccountFactoryStorage.layout().accountImplementation;
    }

    function setGuardianStorage(address guardianAddress) external {
        LibOrganizationGuardianStorage.layout().guardian = guardianAddress;
    }

    function getGuardianStorage() external view returns (address) {
        return LibOrganizationGuardianStorage.layout().guardian;
    }

    function setPoliciesRoot(bytes32 policiesRoot) external {
        LibOrganizationPolicyStorage.layout().policiesRoot = policiesRoot;
    }

    function getPoliciesRoot() external view returns (bytes32) {
        return LibOrganizationPolicyStorage.layout().policiesRoot;
    }

    function setPolicyUsage(bytes32 usageKey, uint256 timeWindow, uint256 usage) external {
        LibOrganizationPolicyStorage.layout().policyUsage[usageKey][timeWindow] = usage;
    }

    function getPolicyUsage(bytes32 usageKey, uint256 timeWindow) external view returns (uint256) {
        return LibOrganizationPolicyStorage.layout().policyUsage[usageKey][timeWindow];
    }

    function setDeployedAccount(address account, bool isDeployed) external {
        LibOrganizationAccountFactoryStorage.layout().deployedAccounts[account] = isDeployed;
    }

    function isDeployedAccount(address account) external view returns (bool) {
        return LibOrganizationAccountFactoryStorage.layout().deployedAccounts[account];
    }

    function setTxRecoveryStateStorage(TxRecoveryState calldata state) external {
        LibOrganizationRecoveryStorage.layout().txRecovery = state;
    }

    function setGuardianRecoveryStateStorage(GuardianRecoveryState calldata state) external {
        LibOrganizationRecoveryStorage.layout().guardianRecovery = state;
    }

    function exposeAuthorizeUpgrade(address newImplementation) external view {
        _authorizeUpgrade(newImplementation);
    }

    function migrationSetMarker(uint256 marker) external {
        LibOrganizationUpgradeTestStorage.layout().marker = marker;
    }

    function migrationGetMarker() external view returns (uint256) {
        return LibOrganizationUpgradeTestStorage.layout().marker;
    }

    function migrationRequireAuthAndSetMarker(uint256 marker) external {
        if (LibOrganizationUpgradeStorage.layout().authorizedUpgradeImplementation == address(0)) {
            revert UpgradeFlagNotSet();
        }
        LibOrganizationUpgradeTestStorage.layout().marker = marker;
    }

    function migrationRevert() external pure {
        revert MigrationCallReverted();
    }

    function migrationNestedUpgrade(address newImplementation, bytes calldata data) external {
        upgradeToAndCall(newImplementation, data);
    }
}

/**
 * @dev V2 target used for Organization UUPS upgrade tests.
 */
contract OrganizationImplementationV2Harness is OrganizationImplementationHarness {
    function version() external pure returns (uint256) {
        return 2;
    }
}

/**
 * @dev V3 target used for sequential Organization UUPS upgrade tests.
 */
contract OrganizationImplementationV3Harness is OrganizationImplementationHarness {
    function version() external pure returns (uint256) {
        return 3;
    }
}

/**
 * @dev Non-UUPS implementation used to assert UUPS safety checks.
 */
contract OrganizationImplementationNonUUPS {}

/**
 * @dev UUPS implementation returning an incompatible UUID.
 */
contract OrganizationImplementationWrongUUID is UUPSUpgradeable {
    function proxiableUUID() public pure override returns (bytes32) {
        return bytes32(uint256(123));
    }

    function _authorizeUpgrade(address) internal view override {}
}

/**
 * @dev Minimal whitelist stub that always reverts during validation.
 */
contract RevertingValidationWhitelistMock {
    function validateIsImplementationWhitelistedOrRevert(ContractType, address) external pure {
        revert("VALIDATION_REVERT");
    }
}

/**
 * @dev Whitelist stub that proves upgrade authorization is not exposed before whitelist validation runs.
 */
contract ValidationOrderWhitelistMock {
    error AuthorizedTargetSetBeforeValidation(address authorizedTarget);
    error ValidationRevertedBeforeFlagSet();

    OrganizationImplementationHarness internal immutable organization;

    constructor(OrganizationImplementationHarness organization_) {
        organization = organization_;
    }

    function validateIsImplementationWhitelistedOrRevert(ContractType, address) external view {
        (, address authorizedTarget) = organization.getUpgradeState();
        if (authorizedTarget != address(0)) {
            revert AuthorizedTargetSetBeforeValidation(authorizedTarget);
        }

        revert ValidationRevertedBeforeFlagSet();
    }
}

/**
 * @dev Whitelist stub with fallback that returns malformed data without reverting.
 */
contract MalformedValidationWhitelistMock {
    fallback() external payable {
        assembly {
            mstore(0x00, 0x01)
            return(0x1f, 0x01)
        }
    }
}

/**
 * @dev Behavior-configurable whitelist mock for Organization upgrade test suites.
 */
contract UpgradeWhitelistMock is IImplementationWhitelist {
    mapping(ContractType => mapping(address => bool)) internal whitelisted;
    bool internal initialized;

    function setImplementationWhitelisted(ContractType contractType, address implementation, bool isWhitelisted)
        external
    {
        whitelisted[contractType][implementation] = isWhitelisted;
    }

    function initialize(
        address,
        address[] calldata organizationImplementations,
        address[] calldata accountImplementations
    ) external override {
        initialized = true;

        for (uint256 i = 0; i < organizationImplementations.length; ++i) {
            whitelisted[ContractType.Organization][organizationImplementations[i]] = true;
        }

        for (uint256 i = 0; i < accountImplementations.length; ++i) {
            whitelisted[ContractType.Account][accountImplementations[i]] = true;
        }
    }

    function whitelistImplementations(
        ContractType contractType,
        address[] calldata toWhitelist,
        address[] calldata toUnwhitelist
    ) external override {
        for (uint256 i = 0; i < toWhitelist.length; ++i) {
            whitelisted[contractType][toWhitelist[i]] = true;
        }

        for (uint256 i = 0; i < toUnwhitelist.length; ++i) {
            whitelisted[contractType][toUnwhitelist[i]] = false;
        }
    }

    function isInitialized() external view override returns (bool) {
        return initialized;
    }

    function isImplementationWhitelisted(ContractType contractType, address implementation)
        external
        view
        override
        returns (bool)
    {
        return whitelisted[contractType][implementation];
    }

    function validateIsImplementationWhitelistedOrRevert(ContractType contractType, address implementation)
        external
        view
        override
    {
        if (!whitelisted[contractType][implementation]) {
            revert ImplementationNotWhitelisted(implementation);
        }
    }
}
