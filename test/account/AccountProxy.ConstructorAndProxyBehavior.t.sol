// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Test} from "forge-std/Test.sol";

import {AccountProxy} from "account/AccountProxy.sol";
import {AccountOrganizationBeaconMock} from "test/account/AccountImplementationMocks.sol";
import {
    AccountProxyBehaviorImplementationV1,
    AccountProxyBehaviorImplementationV2
} from "test/account/AccountProxyMocks.sol";

/**
 * @dev Unit tests for `AccountProxy` constructor and proxy behavior.
 */
contract AccountProxyConstructorAndBehaviorTest is Test {
    AccountProxyBehaviorImplementationV1 internal implementationV1;
    AccountProxyBehaviorImplementationV2 internal implementationV2;
    AccountOrganizationBeaconMock internal beacon;

    /**
     * @dev Deploys versioned implementations and beacon fixture.
     */
    function setUp() public {
        implementationV1 = new AccountProxyBehaviorImplementationV1();
        implementationV2 = new AccountProxyBehaviorImplementationV2();
        beacon = new AccountOrganizationBeaconMock(address(implementationV1));
    }

    /// @dev Verifies constructor accepts beacon and init-data parameters and deploys successfully.
    function test_constructor_validBeaconAndData_deploysSuccessfully() public {
        // Setup: prepare initialization calldata consumed by constructor delegatecall.
        bytes memory initData = abi.encodeWithSelector(AccountProxyBehaviorImplementationV1.initialize.selector, 111);

        // Call: deploy proxy with valid beacon and initialization payload.
        AccountProxy proxy = new AccountProxy(address(beacon), initData);

        // Verify: deployment succeeds and initialization payload was applied to proxy storage.
        uint256 initializedValue = AccountProxyBehaviorImplementationV1(payable(address(proxy))).initializedValue();
        assertEq(initializedValue, 111, "constructor init-data should initialize proxy storage");
    }

    /// @dev Verifies proxy delegates calls to current implementation returned by beacon.
    function test_proxy_delegatesCallsToCurrentBeaconImplementation() public {
        // Setup: deploy proxy bound to beacon implementation V1.
        AccountProxy proxy = new AccountProxy(address(beacon), bytes(""));

        // Call: invoke implementation function through proxy.
        uint256 reportedVersion = AccountProxyBehaviorImplementationV1(payable(address(proxy))).version();

        // Verify: delegated call result comes from beacon implementation V1.
        assertEq(reportedVersion, 1, "proxy should delegate to beacon implementation");
    }

    /// @dev Verifies beacon implementation update changes behavior for all existing account proxies.
    function test_proxy_beaconUpgrade_changesBehaviorForAllExistingAccounts() public {
        // Setup: deploy two proxies bound to the same beacon.
        AccountProxy proxyA = new AccountProxy(address(beacon), bytes(""));
        AccountProxy proxyB = new AccountProxy(address(beacon), bytes(""));

        uint256 versionABefore = AccountProxyBehaviorImplementationV1(payable(address(proxyA))).version();
        uint256 versionBBefore = AccountProxyBehaviorImplementationV1(payable(address(proxyB))).version();
        assertEq(versionABefore, 1, "proxy A should start on implementation V1");
        assertEq(versionBBefore, 1, "proxy B should start on implementation V1");

        // Call: switch beacon implementation to V2.
        beacon.setImplementation(address(implementationV2));

        uint256 versionAAfter = AccountProxyBehaviorImplementationV2(payable(address(proxyA))).version();
        uint256 versionBAfter = AccountProxyBehaviorImplementationV2(payable(address(proxyB))).version();

        // Verify: both proxies reflect upgraded behavior simultaneously.
        assertEq(versionAAfter, 2, "proxy A should follow upgraded beacon implementation");
        assertEq(versionBAfter, 2, "proxy B should follow upgraded beacon implementation");
    }

    /// @dev Verifies account proxy accepts ETH via implementation `receive` path.
    function test_proxy_receiveEth_forwardsToImplementationReceive() public {
        // Setup: deploy proxy and fund deterministic sender.
        AccountProxy proxy = new AccountProxy(address(beacon), bytes(""));
        address sender = address(0x5001);
        uint256 value = 0.42 ether;
        vm.deal(sender, value);

        vm.prank(sender);
        // Call: transfer ETH to proxy with empty calldata.
        (bool success,) = address(proxy).call{value: value}("");

        // Verify: receive path succeeds and proxy storage records received amount.
        assertTrue(success, "proxy receive call should succeed");
        assertEq(address(proxy).balance, value, "proxy balance should increase by transfer value");
        assertEq(
            AccountProxyBehaviorImplementationV1(payable(address(proxy))).totalReceived(),
            value,
            "implementation receive logic should run via delegatecall"
        );
    }

    /// @dev Verifies account proxy resolves organization address (beacon address) through delegated implementation.
    function test_proxy_getOrganizationAddress_returnsBeaconAddress() public {
        // Setup: deploy proxy bound to beacon.
        AccountProxy proxy = new AccountProxy(address(beacon), bytes(""));

        // Call: read organization address via delegated implementation view.
        address organization = AccountProxyBehaviorImplementationV1(payable(address(proxy))).getOrganizationAddress();

        // Verify: organization address equals configured beacon.
        assertEq(organization, address(beacon), "organization address should equal beacon address");
    }

    /// @dev Verifies constructor reverts when beacon address is not a contract.
    function test_constructor_beaconAddressNotContract_revertsERC1967InvalidBeacon() public {
        // Setup: choose deterministic non-contract beacon address.
        address nonContractBeacon = address(0x7500);

        // Verify: non-contract beacon should be rejected.
        vm.expectRevert(abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidBeacon.selector, nonContractBeacon));
        // Call: deploy proxy with non-contract beacon address.
        new AccountProxy(nonContractBeacon, bytes(""));
    }

    /// @dev Verifies constructor reverts when beacon returns implementation with no runtime code.
    function test_constructor_beaconImplementationHasNoCode_revertsERC1967InvalidImplementation() public {
        address noCodeImplementation = address(0x7600);

        // Setup: deploy beacon mock configured to return a no-code implementation address.
        AccountOrganizationBeaconMock badBeacon = new AccountOrganizationBeaconMock(noCodeImplementation);

        // Verify: no-code implementation should be rejected by BeaconProxy constructor checks.
        vm.expectRevert(
            abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidImplementation.selector, noCodeImplementation)
        );
        // Call: deploy proxy with bad beacon.
        new AccountProxy(address(badBeacon), bytes(""));
    }

    /// @dev Verifies non-zero constructor value is rejected when `AccountProxy` constructor is non-payable.
    function test_constructor_emptyDataWithNonZeroValue_revertsForNonPayableConstructor() public {
        // Setup: use valid beacon and empty init data with non-zero deployment value.
        // Verify: non-zero value should revert with empty data (compiler-generated callvalue check).
        vm.expectRevert(bytes(""));
        // Call: deploy proxy bytecode with value and empty init data via low-level create.
        _deployProxyBytecodeOrBubbleRevert(address(beacon), bytes(""), 1 wei);
    }

    /**
     * @dev Deploys AccountProxy creation bytecode with optional value and bubbles constructor revert data.
     */
    function _deployProxyBytecodeOrBubbleRevert(address beaconAddress, bytes memory data, uint256 value)
        internal
        returns (address proxy)
    {
        bytes memory bytecode = abi.encodePacked(type(AccountProxy).creationCode, abi.encode(beaconAddress, data));
        assembly {
            proxy := create(value, add(bytecode, 0x20), mload(bytecode))
            if and(iszero(proxy), not(iszero(returndatasize()))) {
                let p := mload(0x40)
                returndatacopy(p, 0, returndatasize())
                revert(p, returndatasize())
            }
        }
    }
}
