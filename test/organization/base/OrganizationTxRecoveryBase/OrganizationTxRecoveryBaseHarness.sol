// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";

import {OrganizationTxRecoveryBase} from "organization/base/OrganizationTxRecoveryBase.sol";
import {LibOrganizationTxRecovery} from "organization/libraries/LibOrganizationTxRecovery.sol";
import {
    LibOrganizationAccountFactoryStorage
} from "organization/libraries/storage/LibOrganizationAccountFactoryStorage.sol";
import {LibOrganizationAdminStorage} from "organization/libraries/storage/LibOrganizationAdminStorage.sol";
import {LibOrganizationPolicyStorage} from "organization/libraries/storage/LibOrganizationPolicyStorage.sol";
import {LibOrganizationRecoveryStorage} from "organization/libraries/storage/LibOrganizationRecoveryStorage.sol";
import {OrganizationGuardianStateHarness} from "test/organization/shared/OrganizationGuardianStateHarness.sol";
import {GuardianRecoveryState, TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Base-contract-focused test harness for `OrganizationTxRecoveryBase`.
 *      Combines shared policy/admin/account state surface with real external base entry points.
 */
contract OrganizationTxRecoveryBaseHarness is OrganizationGuardianStateHarness, OrganizationTxRecoveryBase, IBeacon {
    /// @dev Beacon implementation pointer used by account proxy integration checks.
    address internal _accountImplementation;

    /**
     * @dev Sets the beacon implementation used by account proxies in tests.
     */
    function setAccountImplementation(address newImplementation) external {
        _accountImplementation = newImplementation;
    }

    /**
     * @dev Sets deployed-account status in account-factory storage.
     */
    function setDeployedAccount(address account, bool isDeployed) external {
        LibOrganizationAccountFactoryStorage.layout().deployedAccounts[account] = isDeployed;
    }

    /**
     * @dev Sets full tx-recovery state.
     */
    function setTxRecoveryState(TxRecoveryState calldata state) external {
        LibOrganizationRecoveryStorage.layout().txRecovery = state;
    }

    /**
     * @dev Sets full guardian-recovery state.
     */
    function setGuardianRecoveryState(GuardianRecoveryState calldata state) external {
        LibOrganizationRecoveryStorage.layout().guardianRecovery = state;
    }

    /**
     * @dev Sets policies merkle root directly in storage.
     */
    function setPoliciesRoot(bytes32 policiesRoot) external {
        LibOrganizationPolicyStorage.layout().policiesRoot = policiesRoot;
    }

    /**
     * @dev Returns beacon implementation address.
     */
    function implementation() external view returns (address) {
        return _accountImplementation;
    }

    /**
     * @dev Reads full guardian-recovery state.
     */
    function getGuardianRecoveryState() external view returns (GuardianRecoveryState memory) {
        return LibOrganizationRecoveryStorage.layout().guardianRecovery;
    }

    /**
     * @dev Reads policies merkle root directly from storage.
     */
    function getPoliciesRoot() external view returns (bytes32) {
        return LibOrganizationPolicyStorage.layout().policiesRoot;
    }

    /**
     * @dev Reads admin voting threshold directly from storage.
     */
    function getVotingThreshold() external view returns (uint256) {
        return LibOrganizationAdminStorage.layout().votingThreshold;
    }

    /**
     * @dev Reads admin count directly from storage.
     */
    function getAdminCount() external view returns (uint256) {
        return LibOrganizationAdminStorage.layout().adminCount;
    }

    /**
     * @dev Exposes tx-recovery execution-guard validation for invariant checks.
     */
    function validateRecoveryAccountTransactionAllowedOrRevertViaHarness() external view {
        LibOrganizationTxRecovery.validateRecoveryAccountTransactionAllowedOrRevert();
    }

    /**
     * @dev Exposes recovery-signature validation for direct test assertions.
     */
    function isValidRecoverySignatureViaHarness(bytes32 hash, bytes calldata signature) external view returns (bool) {
        return LibOrganizationTxRecovery.isValidRecoverySignature(hash, signature);
    }

    /**
     * @dev Exposes tx-recovery parameter validation for direct test assertions.
     */
    function validateTxRecoveryParamsOrRevertViaHarness(address recoveryAddress, uint256 timelockDurationSeconds)
        external
        pure
    {
        LibOrganizationTxRecovery._validateTxRecoveryParamsOrRevert(recoveryAddress, timelockDurationSeconds);
    }
}
