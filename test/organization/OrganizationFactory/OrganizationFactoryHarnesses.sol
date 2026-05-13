// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {IImplementationWhitelist} from "interfaces/IImplementationWhitelist.sol";
import {OrganizationFactory} from "organization/OrganizationFactory.sol";
import {OrganizationImplementation} from "organization/OrganizationImplementation.sol";
import {LibOrganizationInitialization} from "organization/libraries/LibOrganizationInitialization.sol";
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
import {LibOrganizationGuardianStorage} from "organization/libraries/storage/LibOrganizationGuardianStorage.sol";
import {LibOrganizationRecoveryStorage} from "organization/libraries/storage/LibOrganizationRecoveryStorage.sol";
import {LibOrganizationUpgradeStorage} from "organization/libraries/storage/LibOrganizationUpgradeStorage.sol";
import {OrganizationPolicyStateHarness} from "test/organization/shared/OrganizationPolicyStateHarness.sol";
import {ContractType, InitializationParams} from "types/CommonTypes.sol";
import {GuardianRecoveryState, TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Whitelist mock with configurable behavior for initialization tests.
 */
contract InitializationWhitelistMock is IImplementationWhitelist {
    error UnexpectedValidationInput(
        ContractType actualType, address actualImplementation, ContractType expectedType, address expectedImplementation
    );

    mapping(ContractType => mapping(address => bool)) internal whitelisted;
    bool internal initialized;

    bool internal assertExpectedValidationInput;
    ContractType internal expectedValidationType;
    address internal expectedValidationImplementation;

    bool internal forceRevert;
    bytes internal forcedRevertData;

    /// @dev Sets whitelist membership for one implementation under a contract type.
    /// @param contractType Contract type namespace to update.
    /// @param implementation Implementation address to mutate.
    /// @param isWhitelisted New whitelist status for the implementation.
    function setImplementationWhitelisted(ContractType contractType, address implementation, bool isWhitelisted)
        external
    {
        whitelisted[contractType][implementation] = isWhitelisted;
    }

    /// @dev Configures optional strict validation input assertions for the next whitelist validation calls.
    /// @param contractType Expected contract type when strict assertion is enabled.
    /// @param implementation Expected implementation when strict assertion is enabled.
    /// @param shouldAssert Whether to enforce strict validation-input matching.
    function setExpectedValidationInput(ContractType contractType, address implementation, bool shouldAssert) external {
        expectedValidationType = contractType;
        expectedValidationImplementation = implementation;
        assertExpectedValidationInput = shouldAssert;
    }

    /// @dev Configures forced-revert behavior for `validateIsImplementationWhitelistedOrRevert`.
    /// @param shouldForce Whether validation should always revert with custom data.
    /// @param revertData Raw revert payload returned when forced revert is enabled.
    function setForceRevert(bool shouldForce, bytes calldata revertData) external {
        forceRevert = shouldForce;
        forcedRevertData = revertData;
    }

    /// @dev Initializes mock whitelist state and optionally seeds implementation allowlists.
    /// @param _deployerAddress Deployer address argument kept for interface compatibility.
    /// @param organizationImplementations Organization implementations to mark as whitelisted.
    /// @param accountImplementations Account implementations to mark as whitelisted.
    function initialize(
        address _deployerAddress,
        address[] calldata organizationImplementations,
        address[] calldata accountImplementations
    ) external override {
        // Silence unused parameter warnings while preserving interface compatibility.
        _deployerAddress;
        initialized = true;

        // Whitelist all organization implementations supplied during initialization.
        for (uint256 i = 0; i < organizationImplementations.length; ++i) {
            whitelisted[ContractType.Organization][organizationImplementations[i]] = true;
        }

        // Whitelist all account implementations supplied during initialization.
        for (uint256 i = 0; i < accountImplementations.length; ++i) {
            whitelisted[ContractType.Account][accountImplementations[i]] = true;
        }
    }

    /// @dev Applies batch whitelist and unwhitelist updates for a contract type.
    /// @param contractType Contract type namespace to mutate.
    /// @param toWhitelist Implementations to mark as whitelisted.
    /// @param toUnwhitelist Implementations to mark as not whitelisted.
    function whitelistImplementations(
        ContractType contractType,
        address[] calldata toWhitelist,
        address[] calldata toUnwhitelist
    ) external override {
        // Apply whitelist additions first.
        for (uint256 i = 0; i < toWhitelist.length; ++i) {
            whitelisted[contractType][toWhitelist[i]] = true;
        }

        // Apply explicit removals afterwards.
        for (uint256 i = 0; i < toUnwhitelist.length; ++i) {
            whitelisted[contractType][toUnwhitelist[i]] = false;
        }
    }

    /// @dev Returns whether this mock has been initialized.
    /// @return True when `initialize` has been called at least once.
    function isInitialized() external view override returns (bool) {
        return initialized;
    }

    /// @dev Returns whitelist status for an implementation under a contract type.
    /// @param contractType Contract type namespace to query.
    /// @param implementation Implementation address to query.
    /// @return True when the implementation is currently whitelisted for the type.
    function isImplementationWhitelisted(ContractType contractType, address implementation)
        external
        view
        override
        returns (bool)
    {
        return whitelisted[contractType][implementation];
    }

    /// @dev Reverts when forced, when assertion inputs mismatch, or when implementation is not whitelisted.
    /// @param contractType Contract type to validate.
    /// @param implementation Implementation address to validate.
    function validateIsImplementationWhitelistedOrRevert(ContractType contractType, address implementation)
        external
        view
        override
    {
        // Allow tests to inject arbitrary upstream revert data from whitelist validation.
        if (forceRevert) {
            bytes memory data = forcedRevertData;
            assembly {
                revert(add(data, 0x20), mload(data))
            }
        }

        // Optionally enforce exact validation arguments to verify factory call wiring.
        if (assertExpectedValidationInput) {
            if (contractType != expectedValidationType || implementation != expectedValidationImplementation) {
                revert UnexpectedValidationInput(
                    contractType, implementation, expectedValidationType, expectedValidationImplementation
                );
            }
        }

        // Mirror production behavior by reverting for non-whitelisted implementations.
        if (!whitelisted[contractType][implementation]) {
            revert ImplementationNotWhitelisted(implementation);
        }
    }
}

/**
 * @dev Minimal incompatible implementation without `initialize(InitializationParams)`.
 */
contract IncompatibleOrganizationImplementation {
    /// @dev Returns a constant marker used by tests to confirm the harness is callable.
    /// @return Constant value `1`.
    function ping() external pure returns (uint256) {
        return 1;
    }
}

/**
 * @dev Harness exposing internal `OrganizationFactory` helper for bytecode hash coverage.
 */
contract OrganizationFactoryHarness is OrganizationFactory {
    /// @dev Forwards deployer configuration into the base factory constructor.
    /// @param deployerAddress Authorized deployer address stored immutably by the factory.
    constructor(address deployerAddress) OrganizationFactory(deployerAddress) {}

    /// @dev Exposes internal proxy-bytecode construction for deterministic CREATE2 hash assertions.
    /// @param implementationAddress Implementation address encoded into proxy creation bytecode.
    /// @param whitelistAddress Whitelist address encoded into proxy creation bytecode.
    /// @return Proxy creation bytecode assembled by `_getOrganizationProxyBytecode`.
    function getOrganizationProxyBytecode(address implementationAddress, address whitelistAddress)
        external
        pure
        returns (bytes memory)
    {
        return _getOrganizationProxyBytecode(implementationAddress, whitelistAddress);
    }
}

/**
 * @dev Organization implementation test harness exposing storage getters needed by proxy tests.
 */
contract OrganizationImplementationHarness is OrganizationImplementation {
    /// @dev Reads whitelist address directly from upgrade storage for slot-level assertions.
    /// @return Whitelist address currently stored in upgrade storage.
    function getWhitelistAddressStorageForTests() external view returns (address) {
        return LibOrganizationUpgradeStorage.layout().whitelistAddress;
    }
}

/**
 * @dev Library harness for direct `LibOrganizationInitialization` coverage.
 *      Inherits `Initializable` so the `initializer` modifier on `initializeViaLibrary` mirrors
 *      the production wrapper in `OrganizationInitializationBase` and provides the same
 *      re-initialization protection that production code relies on.
 */
contract LibOrganizationInitializationHarness is Initializable, OrganizationPolicyStateHarness {
    /// @dev Executes `LibOrganizationInitialization.initialize` using harness storage,
    ///      guarded by the OpenZeppelin `initializer` modifier that production callers apply.
    /// @param params Initialization payload forwarded into the library call.
    function initializeViaLibrary(InitializationParams calldata params) external initializer {
        LibOrganizationInitialization.initialize(params);
    }

    /// @dev Executes `LibOrganizationInitialization.enforceOnlyDeployer`.
    function enforceOnlyDeployerViaLibrary() external view {
        LibOrganizationInitialization.enforceOnlyDeployer();
    }

    /// @dev Returns deployer address via `LibOrganizationInitialization.getDeployerAddress`.
    /// @return Deployer address stored in deployer storage.
    function getDeployerAddressViaLibrary() external view returns (address) {
        return LibOrganizationInitialization.getDeployerAddress();
    }

    /// @dev Returns initialized status read from the OpenZeppelin `Initializable` storage that
    ///      now serves as the single source of truth for organization initialization.
    /// @return True when the `initializer` modifier has been run for this harness.
    function isInitializedViaLibrary() external view returns (bool) {
        return _getInitializedVersion() != 0;
    }

    /// @dev Sets deployer storage directly for library-guard test setup.
    /// @param deployerAddress Deployer address to write into storage.
    function setDeployerAddressStorage(address deployerAddress) external {
        LibOrganizationDeployerAddressStorage.layout().deployerAddress = deployerAddress;
    }

    /// @dev Sets whitelist storage directly for library test setup.
    /// @param whitelistAddress Whitelist address to write into storage.
    function setWhitelistAddressStorage(address whitelistAddress) external {
        LibOrganizationUpgradeStorage.layout().whitelistAddress = whitelistAddress;
    }

    /// @dev Sets admin operation timelock storage directly for library test setup.
    /// @param durationSeconds Timelock duration value to write into storage.
    function setAdminOperationTimelockStorage(uint256 durationSeconds) external {
        LibOrganizationAdminOperationTimelockStorage.layout().adminOperationTimelockDurationSeconds = durationSeconds;
    }

    /// @dev Reads whitelist address directly from storage.
    /// @return Whitelist address stored in upgrade storage.
    function getWhitelistAddressStorage() external view returns (address) {
        return LibOrganizationUpgradeStorage.layout().whitelistAddress;
    }

    /// @dev Reads admin count directly from storage.
    /// @return Current admin count stored in admin storage.
    function getAdminCountStorage() external view returns (uint256) {
        return LibOrganizationAdminStorage.layout().adminCount;
    }

    /// @dev Reads voting threshold directly from storage.
    /// @return Current voting threshold stored in admin storage.
    function getVotingThresholdStorage() external view returns (uint256) {
        return LibOrganizationAdminStorage.layout().votingThreshold;
    }

    /// @dev Reads guardian address directly from storage.
    /// @return Guardian address stored in guardian storage.
    function getGuardianStorage() external view returns (address) {
        return LibOrganizationGuardianStorage.layout().guardian;
    }

    /// @dev Reads admin operation timelock duration directly from storage.
    /// @return Timelock duration stored in admin-operation timelock storage.
    function getAdminOperationTimelockStorage() external view returns (uint256) {
        return LibOrganizationAdminOperationTimelockStorage.layout().adminOperationTimelockDurationSeconds;
    }

    /// @dev Reads account implementation address directly from storage.
    /// @return Account implementation stored in account-factory storage.
    function getAccountImplementationStorage() external view returns (address) {
        return LibOrganizationAccountFactoryStorage.layout().accountImplementation;
    }

    /// @dev Reads transaction recovery state directly from storage.
    /// @return txRecovery Transaction recovery state struct from storage.
    function getTxRecoveryStateViaStorage() external view returns (TxRecoveryState memory) {
        return LibOrganizationRecoveryStorage.layout().txRecovery;
    }

    /// @dev Reads guardian recovery state directly from storage.
    /// @return guardianRecovery Guardian recovery state struct from storage.
    function getGuardianRecoveryStateViaStorage() external view returns (GuardianRecoveryState memory) {
        return LibOrganizationRecoveryStorage.layout().guardianRecovery;
    }
}
