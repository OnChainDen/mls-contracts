// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import {AccountImplementation} from "account/AccountImplementation.sol";
import {IAccount} from "interfaces/IAccount.sol";
import {
    StorageLayoutHarness,
    StorageLayoutUUPSImplementationV1,
    StorageLayoutUUPSImplementationV2,
    TestBeacon
} from "test/helpers/storage/StorageLayoutHarnesses.sol";
import {StorageLayoutTestBase} from "test/helpers/storage/StorageLayoutTestBase.sol";

/**
 * @dev Storage Layout Integration Tests
 *      Checks that values persist in storage across multiple delegatecalls and implementation upgrades.
 */
contract StorageLayoutIntegrationTest is StorageLayoutTestBase {
    /**
     * @dev Verifies values persist across multiple delegatecall transactions.
     */
    function test_delegatecallPersistence_valuesPersistAcrossMultipleTransactions() public {
        StorageLayoutUUPSImplementationV1 implementationV1 = new StorageLayoutUUPSImplementationV1();
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementationV1), bytes(""));
        StorageLayoutUUPSImplementationV1 proxied = StorageLayoutUUPSImplementationV1(address(proxy));

        proxied.setDeployerAddress(TEST_DEPLOYER);
        vm.roll(block.number + 1);

        proxied.setAdminCount(17);
        vm.roll(block.number + 1);

        proxied.setPolicyUsage(TEST_POLICY_USAGE_KEY, TEST_POLICY_WINDOW, 4242);
        vm.roll(block.number + 1);

        proxied.setUsedNonce(TEST_NONCE, true);

        assertEq(proxied.getDeployerAddress(), TEST_DEPLOYER, "deployerAddress did not persist");
        assertEq(proxied.getAdminCount(), 17, "adminCount did not persist");
        assertEq(proxied.getPolicyUsage(TEST_POLICY_USAGE_KEY, TEST_POLICY_WINDOW), 4242, "policyUsage did not persist");
        assertTrue(proxied.getUsedNonce(TEST_NONCE), "usedNonces did not persist");
    }

    /**
     * @dev Verifies test fixture storage values persist across a UUPS implementation upgrade.
     */
    function test_upgradePersistence_valuesSurviveUUPSImplementationUpgrade() public {
        StorageLayoutUUPSImplementationV1 implementationV1 = new StorageLayoutUUPSImplementationV1();
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementationV1), bytes(""));

        _writeTestFixtureValues(StorageLayoutHarness(address(proxy)));

        StorageLayoutUUPSImplementationV2 implementationV2 = new StorageLayoutUUPSImplementationV2();
        StorageLayoutUUPSImplementationV1(address(proxy)).upgradeToAndCall(address(implementationV2), bytes(""));

        StorageLayoutUUPSImplementationV2 proxiedV2 = StorageLayoutUUPSImplementationV2(address(proxy));
        assertEq(proxiedV2.implementationVersion(), 2, "proxy was not upgraded to V2");

        _assertTestFixtureValues(StorageLayoutHarness(address(proxy)));
    }

    /**
     * @dev Verifies `getOrganizationAddress()` returns the beacon address from the EIP-1967 beacon slot.
     *      Calls `AccountImplementation.getOrganizationAddress()` through a real BeaconProxy,
     *      exercising `LibAccountOrganizationAddressStorage` which reads from the standard EIP-1967 beacon slot.
     */
    function test_getOrganizationAddress_returnsBeaconAddressViaBeaconProxy() public {
        AccountImplementation accountImplementation = new AccountImplementation();
        TestBeacon beacon = new TestBeacon(address(accountImplementation));

        BeaconProxy accountProxy = new BeaconProxy(address(beacon), bytes(""));

        address organizationAddress = IAccount(payable(address(accountProxy))).getOrganizationAddress();

        assertEq(organizationAddress, address(beacon), "getOrganizationAddress should return beacon address");
    }
}
