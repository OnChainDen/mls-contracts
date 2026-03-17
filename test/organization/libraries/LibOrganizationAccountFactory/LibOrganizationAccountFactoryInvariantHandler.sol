// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibOrganizationAccountFactoryHarness
} from "test/organization/libraries/LibOrganizationAccountFactory/LibOrganizationAccountFactoryHarness.sol";
import {ImplementationWhitelistMock} from "test/organization/shared/OrganizationAccountFactoryMocks.sol";
import {ContractType} from "types/CommonTypes.sol";

/**
 * @dev Stateful handler for account-factory invariant fuzzing.
 */
contract LibOrganizationAccountFactoryInvariantHandler {
    /// @dev Target harness under invariant fuzzing.
    LibOrganizationAccountFactoryHarness public immutable harness;

    /// @dev Whitelist mock used to toggle implementation authorization.
    ImplementationWhitelistMock public immutable whitelist;

    /// @dev Two valid implementation candidates (both with runtime code).
    address public immutable implementationA;
    address public immutable implementationB;

    /// @dev Tracks whether a successful implementation update happened while not whitelisted.
    bool public successfulSetWithoutWhitelist;

    address[] internal trackedDeployedAccounts;
    bytes32[] internal trackedDeployedSalts;
    address[] internal trackedObservedTrueAccounts;

    mapping(address => bool) internal isTrackedDeployedAccount;
    mapping(address => bool) internal isTrackedObservedTrueAccount;

    /**
     * @dev Initializes invariant handler dependencies.
     */
    constructor(
        LibOrganizationAccountFactoryHarness harness_,
        ImplementationWhitelistMock whitelist_,
        address implementationA_,
        address implementationB_
    ) {
        harness = harness_;
        whitelist = whitelist_;
        implementationA = implementationA_;
        implementationB = implementationB_;
    }

    /**
     * @dev Attempts account deployment for fuzzed salt.
     */
    function deployAccount(bytes32 salt) external {
        try harness.deployAccountViaLibrary(salt) returns (address deployed) {
            if (!isTrackedDeployedAccount[deployed]) {
                isTrackedDeployedAccount[deployed] = true;
                trackedDeployedAccounts.push(deployed);
                trackedDeployedSalts.push(salt);
            }

            if (!isTrackedObservedTrueAccount[deployed]) {
                isTrackedObservedTrueAccount[deployed] = true;
                trackedObservedTrueAccounts.push(deployed);
            }
        } catch {}
    }

    /**
     * @dev Attempts implementation update using a toggled whitelist status.
     */
    function setAccountImplementation(uint256 implementationSeed, bool whitelistImplementation) external {
        address implementation = implementationSeed % 2 == 0 ? implementationA : implementationB;

        whitelist.setImplementationWhitelisted(ContractType.Account, implementation, whitelistImplementation);

        try harness.setAccountImplementationViaLibrary(implementation) {
            if (!whitelistImplementation) {
                successfulSetWithoutWhitelist = true;
            }
        } catch {}
    }

    /**
     * @dev Observes deployment tracking for arbitrary addresses and records true states.
     */
    function observeDeploymentStatus(address account) external {
        if (harness.isAccountDeployedByOrganizationViaLibrary(account) && !isTrackedObservedTrueAccount[account]) {
            isTrackedObservedTrueAccount[account] = true;
            trackedObservedTrueAccounts.push(account);
        }
    }

    /**
     * @dev Returns number of tracked successful deployments.
     */
    function trackedDeployedAccountsLength() external view returns (uint256) {
        return trackedDeployedAccounts.length;
    }

    /**
     * @dev Returns tracked deployed account at index.
     */
    function trackedDeployedAccountAt(uint256 index) external view returns (address) {
        return trackedDeployedAccounts[index];
    }

    /**
     * @dev Returns tracked deployed salt at index.
     */
    function trackedDeployedSaltAt(uint256 index) external view returns (bytes32) {
        return trackedDeployedSalts[index];
    }

    /**
     * @dev Returns number of addresses observed as true in deployment tracking.
     */
    function trackedObservedTrueAccountsLength() external view returns (uint256) {
        return trackedObservedTrueAccounts.length;
    }

    /**
     * @dev Returns observed-true account address at index.
     */
    function trackedObservedTrueAccountAt(uint256 index) external view returns (address) {
        return trackedObservedTrueAccounts[index];
    }
}
