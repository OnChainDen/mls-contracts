// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {
    ImplementationWhitelistHarness,
    ImplementationWhitelistNonUUPS,
    ImplementationWhitelistV2Harness,
    ImplementationWhitelistWrongUUID
} from "test/implementation-whitelist/ImplementationWhitelistImplementation/ImplementationWhitelistHarnesses.sol";

contract WhitelistCodeAddressMock {}

/**
 * @dev Shared setup/helpers for ImplementationWhitelist test suites.
 */
abstract contract ImplementationWhitelistSuiteBase is Test {
    bytes32 internal constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    address internal constant OWNER = address(0xA11CE);
    address internal constant NON_OWNER = address(0xB0B);
    address internal constant NEW_OWNER = address(0xCAFE);

    ImplementationWhitelistHarness internal implementation;
    ImplementationWhitelistHarness internal whitelistProxy;
    ImplementationWhitelistV2Harness internal implementationV2;
    ImplementationWhitelistWrongUUID internal wrongUuidImplementation;
    ImplementationWhitelistNonUUPS internal nonUupsImplementation;

    address internal organizationImplementationA;
    address internal organizationImplementationB;
    address internal accountImplementationA;
    address internal accountImplementationB;
    address internal noCodeAddress;

    /**
     * @dev Deploys whitelist fixture implementations, seeds deterministic code/no-code addresses,
     *      and initializes the default proxy instance owned by `OWNER`.
     */
    function setUp() public virtual {
        implementation = new ImplementationWhitelistHarness();
        implementationV2 = new ImplementationWhitelistV2Harness();
        wrongUuidImplementation = new ImplementationWhitelistWrongUUID();
        nonUupsImplementation = new ImplementationWhitelistNonUUPS();

        organizationImplementationA = address(new WhitelistCodeAddressMock());
        organizationImplementationB = address(new WhitelistCodeAddressMock());
        accountImplementationA = address(new WhitelistCodeAddressMock());
        accountImplementationB = address(new WhitelistCodeAddressMock());
        noCodeAddress = address(0xDEADCAFE);

        whitelistProxy = _deployInitializedProxy(OWNER, new address[](0), new address[](0));
    }

    /**
     * @dev Deploys an ERC-1967 proxy pointing to `implementation` and executes initializer calldata in constructor.
     * @param initialOwner Address that becomes whitelist owner during initialization.
     * @param organizationImplementations Initial Organization-type implementation seed list.
     * @param accountImplementations Initial Account-type implementation seed list.
     * @return proxyInstance Initialized whitelist proxy cast to `ImplementationWhitelistHarness`.
     */
    function _deployInitializedProxy(
        address initialOwner,
        address[] memory organizationImplementations,
        address[] memory accountImplementations
    ) internal returns (ImplementationWhitelistHarness proxyInstance) {
        bytes memory initData = abi.encodeWithSelector(
            implementation.initialize.selector, initialOwner, organizationImplementations, accountImplementations
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        proxyInstance = ImplementationWhitelistHarness(payable(address(proxy)));
    }

    /**
     * @dev Deploys an ERC-1967 proxy pointing to `implementation` without running initialization.
     * @return proxyInstance Uninitialized whitelist proxy cast to `ImplementationWhitelistHarness`.
     */
    function _deployUninitializedProxy() internal returns (ImplementationWhitelistHarness proxyInstance) {
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), bytes(""));
        proxyInstance = ImplementationWhitelistHarness(payable(address(proxy)));
    }

    /**
     * @dev Builds a single-entry address array helper used by whitelist add/remove test inputs.
     * @param value Address to place at index 0.
     * @return values One-element address array containing `value`.
     */
    function _single(address value) internal pure returns (address[] memory values) {
        values = new address[](1);
        values[0] = value;
    }

    /**
     * @dev Builds a two-entry address array helper used by dual add/remove test inputs.
     * @param first Address to place at index 0.
     * @param second Address to place at index 1.
     * @return values Two-element address array containing `first` then `second`.
     */
    function _pair(address first, address second) internal pure returns (address[] memory values) {
        values = new address[](2);
        values[0] = first;
        values[1] = second;
    }

    /**
     * @dev Reads the ERC-1967 implementation slot directly from proxy storage for upgrade assertions.
     * @param proxy Proxy address whose implementation slot should be inspected.
     * @return implementationAddress Current implementation address stored in `IMPLEMENTATION_SLOT`.
     */
    function _readProxyImplementation(address proxy) internal view returns (address implementationAddress) {
        implementationAddress = address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT))));
    }
}
