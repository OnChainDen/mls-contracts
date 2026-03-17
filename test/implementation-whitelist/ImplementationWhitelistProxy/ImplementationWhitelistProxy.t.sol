// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {OwnableUpgradeable} from "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Test} from "forge-std/Test.sol";

import {
    ImplementationWhitelistImplementation
} from "implementation-whitelist/ImplementationWhitelistImplementation.sol";
import {ImplementationWhitelistProxy} from "implementation-whitelist/ImplementationWhitelistProxy.sol";
import {IImplementationWhitelist} from "interfaces/IImplementationWhitelist.sol";
import {ContractType} from "types/CommonTypes.sol";

contract WhitelistCodeAddressMock {}

/**
 * @dev Constructor tests for `ImplementationWhitelistProxy` ( through ).
 */
contract ImplementationWhitelistProxyTest is Test {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    address internal constant OWNER = address(0xA11CE);
    address internal constant NON_OWNER = address(0xB0B);

    ImplementationWhitelistImplementation internal implementation;

    address internal organizationImplementationA;
    address internal accountImplementationA;

    function setUp() public {
        implementation = new ImplementationWhitelistImplementation();

        organizationImplementationA = address(new WhitelistCodeAddressMock());
        accountImplementationA = address(new WhitelistCodeAddressMock());
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Helpers
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @dev Builds initialization calldata for `ImplementationWhitelistImplementation.initialize`.
     * @param initialOwner Owner address passed to initializer.
     * @param orgImpls Organization-type seed implementations.
     * @param accImpls Account-type seed implementations.
     * @return initData ABI-encoded initializer call.
     */
    function _buildInitData(address initialOwner, address[] memory orgImpls, address[] memory accImpls)
        internal
        pure
        returns (bytes memory initData)
    {
        initData = abi.encodeWithSelector(
            ImplementationWhitelistImplementation.initialize.selector, initialOwner, orgImpls, accImpls
        );
    }

    /**
     * @dev Builds a single-entry address array.
     * @param value Address to place at index 0.
     * @return values One-element address array containing `value`.
     */
    function _single(address value) internal pure returns (address[] memory values) {
        values = new address[](1);
        values[0] = value;
    }

    /**
     * @dev Reads the ERC-1967 implementation slot directly from proxy storage.
     * @param proxy Proxy address whose implementation slot should be inspected.
     * @return implementationAddress Current implementation address stored in `IMPLEMENTATION_SLOT`.
     */
    function _readProxyImplementation(address proxy) internal view returns (address implementationAddress) {
        implementationAddress = address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT))));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Tests
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Verifies deploying proxy with valid `initData` initializes owner and seed whitelists atomically.
    function test_constructor_validInitData_initializesAtomically() public {
        // Setup: build initialization data with owner and seed arrays.
        address[] memory orgSeeds = _single(organizationImplementationA);
        address[] memory accSeeds = _single(accountImplementationA);
        bytes memory initData = _buildInitData(OWNER, orgSeeds, accSeeds);

        // Call: deploy proxy with valid initData.
        ImplementationWhitelistProxy proxy = new ImplementationWhitelistProxy(address(implementation), initData);
        IImplementationWhitelist whitelist = IImplementationWhitelist(address(proxy));

        // Verify: owner is set, implementation stored, seed entries whitelisted.
        assertEq(OwnableUpgradeable(address(proxy)).owner(), OWNER, "owner mismatch");
        assertTrue(whitelist.isInitialized(), "proxy should be initialized");
        assertTrue(
            whitelist.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA),
            "org seed should be whitelisted"
        );
        assertTrue(
            whitelist.isImplementationWhitelisted(ContractType.Account, accountImplementationA),
            "account seed should be whitelisted"
        );
    }

    /// @dev Verifies deploying proxy with `implementation == address(0)` reverts.
    function test_constructor_zeroImplementation_reverts() public {
        // Setup: build valid initData but use zero implementation address.
        bytes memory initData = _buildInitData(OWNER, new address[](0), new address[](0));

        // Verify: ERC1967Proxy rejects zero-address implementation.
        vm.expectRevert(abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidImplementation.selector, address(0)));

        // Call: deploy proxy with address(0) implementation.
        new ImplementationWhitelistProxy(address(0), initData);
    }

    /// @dev Verifies deploying proxy with no-code implementation address reverts.
    function test_constructor_noCodeImplementation_reverts() public {
        // Setup: build valid initData but use an EOA (no-code) implementation address.
        address noCodeAddr = address(0xDEADCAFE);
        bytes memory initData = _buildInitData(OWNER, new address[](0), new address[](0));

        // Verify: ERC1967Proxy rejects implementation with no code.
        vm.expectRevert(abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidImplementation.selector, noCodeAddr));

        // Call: deploy proxy with no-code implementation.
        new ImplementationWhitelistProxy(noCodeAddr, initData);
    }

    /// @dev Verifies deploying proxy with malformed/garbage initData causes constructor revert.
    function test_constructor_malformedInitData_reverts() public {
        // Setup: construct garbage initData that does not match any function selector.
        bytes memory malformedData = hex"DEADBEEF";

        // Verify: delegatecall with malformed data reverts (function selector mismatch).
        vm.expectRevert();

        // Call: deploy proxy with garbage initData.
        new ImplementationWhitelistProxy(address(implementation), malformedData);
    }

    /// @dev Verifies if delegated initialize reverts, proxy deployment reverts atomically.
    function test_constructor_initializeReverts_proxyDeploymentRevertsAtomically() public {
        // Setup: build initData that calls initialize with zero owner (which reverts).
        bytes memory initData = _buildInitData(address(0), new address[](0), new address[](0));

        // Verify: OwnableInvalidOwner revert propagates through proxy constructor.
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableInvalidOwner.selector, address(0)));

        // Call: deploy proxy with initData that triggers initializer revert.
        new ImplementationWhitelistProxy(address(implementation), initData);
    }

    /// @dev Verifies implementation slot points to provided implementation address after deploy.
    function test_constructor_implementationSlotPointsToProvidedAddress() public {
        // Setup: deploy proxy with valid initData.
        bytes memory initData = _buildInitData(OWNER, new address[](0), new address[](0));
        ImplementationWhitelistProxy proxy = new ImplementationWhitelistProxy(address(implementation), initData);

        // Call: read ERC-1967 implementation slot from proxy storage.
        address storedImpl = _readProxyImplementation(address(proxy));

        // Verify: stored implementation matches the address provided to constructor.
        assertEq(storedImpl, address(implementation), "implementation slot mismatch");
    }

    /// @dev Verifies proxy delegates calls to implementation correctly (read and write paths).
    function test_proxyDelegatesCallsCorrectly() public {
        // Setup: deploy initialized proxy.
        bytes memory initData = _buildInitData(OWNER, new address[](0), new address[](0));
        ImplementationWhitelistProxy proxy = new ImplementationWhitelistProxy(address(implementation), initData);
        IImplementationWhitelist whitelist = IImplementationWhitelist(address(proxy));

        // Call (read path): verify isInitialized() returns true via delegation.
        assertTrue(whitelist.isInitialized(), "read delegation should return initialized state");

        // Call (write path): whitelist an implementation through proxy.
        vm.prank(OWNER);
        whitelist.whitelistImplementations(
            ContractType.Organization, _single(organizationImplementationA), new address[](0)
        );

        // Verify: state change persists in proxy storage via delegated write.
        assertTrue(
            whitelist.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA),
            "write delegation should persist state"
        );
    }

    /// @dev Verifies [DESIRED] empty initData deployment should revert to prevent uninitialized proxy.
    ///      Current behavior: ERC1967Proxy allows empty initData, leaving the proxy uninitialized.
    ///      This test documents the desired behavior and will fail with the current implementation.
    function test_constructor_emptyInitData_shouldRevertDesiredBehavior() public {
        // Setup: empty initData bytes.
        bytes memory emptyData = bytes("");

        // DESIRED: deploying with empty initData should revert to prevent uninitialized proxy takeover.
        // Current behavior: ERC1967Proxy allows empty initData without reverting.
        // This test documents the desired behavior and is expected to fail with the current implementation.
        vm.expectRevert();

        // Call: deploy proxy with empty initData.
        new ImplementationWhitelistProxy(address(implementation), emptyData);
    }
}
