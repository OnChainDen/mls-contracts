// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";

import {OrganizationAccountTransactionBase} from "organization/base/OrganizationAccountTransactionBase.sol";
import {LibOrganizationAccountTransaction} from "organization/libraries/LibOrganizationAccountTransaction.sol";
import {OrganizationPolicyStateHarness} from "test/organization/shared/OrganizationPolicyStateHarness.sol";

/**
 * @dev Base-contract-focused test harness for `OrganizationAccountTransactionBase`.
 *      Extends shared policy/admin state helpers and exposes hash wrappers for signature fixtures.
 */
contract OrganizationAccountTransactionBaseHarness is
    OrganizationPolicyStateHarness,
    OrganizationAccountTransactionBase,
    IBeacon
{
    /// @dev Beacon implementation pointer used by account proxy integration checks.
    address internal accountImplementation;

    /**
     * @dev Sets the beacon implementation used by account proxies in tests.
     */
    function setAccountImplementation(address newImplementation) external {
        accountImplementation = newImplementation;
    }

    /**
     * @dev Returns beacon implementation address.
     */
    function implementation() external view returns (address) {
        return accountImplementation;
    }

    /**
     * @dev Wrapper around `_computeInitiatorHashFromParams`.
     */
    function computeInitiatorHashFromParamsViaLibrary(
        address account,
        address to,
        uint256 value,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bytes calldata data,
        bool isApproval
    ) external view returns (bytes32) {
        LibOrganizationAccountTransaction.TxParams memory params =
            LibOrganizationAccountTransaction.TxParams({
                account: account,
                to: to,
                value: value,
                salt: salt,
                expirationTimestamp: expirationTimestamp,
                policyId: policyId
            });
        return LibOrganizationAccountTransaction._computeInitiatorHashFromParams(params, data, isApproval);
    }

    /**
     * @dev Wrapper around `_computeReviewHashFromParams`.
     */
    function computeReviewHashFromParamsViaLibrary(
        address account,
        address to,
        uint256 value,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bytes calldata data,
        bool isApproval,
        bytes calldata initiatorSignature
    ) external view returns (bytes32) {
        LibOrganizationAccountTransaction.TxParams memory params =
            LibOrganizationAccountTransaction.TxParams({
                account: account,
                to: to,
                value: value,
                salt: salt,
                expirationTimestamp: expirationTimestamp,
                policyId: policyId
            });
        return
            LibOrganizationAccountTransaction._computeReviewHashFromParams(params, data, isApproval, initiatorSignature);
    }
}
