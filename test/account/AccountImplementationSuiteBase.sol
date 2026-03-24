// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {Test} from "forge-std/Test.sol";

import {IAccount} from "interfaces/IAccount.sol";
import {AccountImplementationHarness} from "test/account/AccountImplementationHarness.sol";
import {AccountOrganizationBeaconMock} from "test/account/AccountImplementationMocks.sol";

/**
 * @dev Shared deployment/setup helpers for account implementation suites.
 */
abstract contract AccountImplementationSuiteBase is Test {
    /// @dev Harness implementation logic contract.
    AccountImplementationHarness internal implementation;

    /// @dev Beacon mock that also acts as organization-signature contract.
    AccountOrganizationBeaconMock internal beacon;

    /// @dev Account proxy instance (typed as harness to access wrapper functions).
    AccountImplementationHarness internal account;

    /// @dev Deterministic non-organization caller for access-control negative tests.
    address internal constant NON_ORGANIZATION = address(0xBADA55);

    /**
     * @dev Deploys implementation + beacon + proxy account fixture.
     */
    function setUp() public virtual {
        implementation = new AccountImplementationHarness();
        beacon = new AccountOrganizationBeaconMock(address(implementation));
        account = AccountImplementationHarness(payable(address(new BeaconProxy(address(beacon), bytes("")))));
    }

    /**
     * @dev Returns account proxy as IAccount interface for event/selector usage.
     */
    function _asIAccount() internal view returns (IAccount) {
        return IAccount(payable(address(account)));
    }
}
