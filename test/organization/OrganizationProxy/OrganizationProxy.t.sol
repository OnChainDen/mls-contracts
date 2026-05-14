// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {IImplementationWhitelist} from "interfaces/IImplementationWhitelist.sol";
import {IOrganization} from "interfaces/IOrganization.sol";
import {IOrganizationFactory} from "interfaces/IOrganizationFactory.sol";
import {IOrganizationInitialization} from "interfaces/organization/IOrganizationInitialization.sol";
import {OrganizationProxy} from "organization/OrganizationProxy.sol";
import {
    LibOrganizationDeployerAddressStorage
} from "organization/libraries/storage/LibOrganizationDeployerAddressStorage.sol";
import {LibOrganizationUpgradeStorage} from "organization/libraries/storage/LibOrganizationUpgradeStorage.sol";
import {
    OrganizationImplementationHarness
} from "test/organization/OrganizationFactory/OrganizationFactoryHarnesses.sol";
import {
    InitializationSuiteBase
} from "test/organization/base/OrganizationInitializationBase/OrganizationInitializationBaseSuiteBase.sol";
import {ContractType, InitializationParams} from "types/CommonTypes.sol";

/**
 * @dev Proxy constructor, `setInitialImplementation`, and delegation tests.
 *
 *      The proxy no longer takes an implementation address in its constructor. The
 *      implementation is bound post deployment via `setInitialImplementation`. Tests
 *      cover:
 *        - constructor behavior (whitelist argument only)
 *        - `setInitialImplementation` gating, one shot semantics, and validation
 *        - delegation after the deploy + bind sequence
 */
contract OrganizationProxyTest is InitializationSuiteBase {
    /// @dev Verifies `OrganizationProxy.constructor` writes the deployer and whitelist storage slots,
    ///      leaves the ERC-1967 implementation slot empty until `setInitialImplementation` is called,
    ///      and that the bind writes the implementation slot and remains observable through delegation.
    function test_constructor_setsDeployerAndWhitelistAndLeavesImplEmpty() public {
        // Setup: Select a direct deployer for deploying the proxy outside the factory flow.
        address directDeployer = address(0xFA01);

        // Call: Deploy the proxy.
        vm.prank(directDeployer);
        OrganizationProxy proxy = new OrganizationProxy(address(whitelist));
        address proxyAddr = address(proxy);

        // Verify: read deployer, whitelist, and implementation slots directly from proxy storage post-construction.
        bytes32 deployerWord = vm.load(proxyAddr, LibOrganizationDeployerAddressStorage.STORAGE_LOCATION);
        assertEq(
            address(uint160(uint256(deployerWord))), directDeployer, "deployer slot should store constructor msg.sender"
        );

        bytes32 whitelistWord = vm.load(proxyAddr, LibOrganizationUpgradeStorage.STORAGE_LOCATION);
        assertEq(address(uint160(uint256(whitelistWord))), address(whitelist), "whitelist slot mismatch");

        bytes32 implementationWord = vm.load(proxyAddr, ERC1967_IMPLEMENTATION_SLOT);
        assertEq(
            address(uint160(uint256(implementationWord))),
            address(0),
            "ERC1967 implementation slot should be empty pre-bind"
        );

        // Call: Bind the implementation.
        vm.prank(directDeployer);
        proxy.setInitialImplementation(address(implementation));

        // Verify: implementation slot now holds the bound implementation address.
        bytes32 implementationWordAfterBind = vm.load(proxyAddr, ERC1967_IMPLEMENTATION_SLOT);
        assertEq(
            address(uint160(uint256(implementationWordAfterBind))),
            address(implementation),
            "implementation slot should hold bound impl after setInitialImplementation"
        );

        // Verify: delegation to the bound implementation works and reports the recorded deployer.
        assertEq(
            IOrganization(proxyAddr).getDeployerAddress(),
            directDeployer,
            "deployer slot should store constructor msg.sender (via delegated read)"
        );
    }

    /// @dev Verifies `OrganizationProxy.constructor` reverts with `ZeroAddress` when whitelist is zero.
    function test_constructor_zeroWhitelist_revertsZeroAddress() public {
        // Setup: Prepare a zero whitelist address for constructor input.
        address zeroWhitelist = address(0);

        // Call: Deploy the proxy with a zero whitelist and expect `ZeroAddress`.
        vm.expectRevert(IOrganizationFactory.ZeroAddress.selector);
        new OrganizationProxy(zeroWhitelist);
    }

    /// @dev Verifies `OrganizationProxy.constructor` rejects non-contract whitelist addresses as a safety requirement.
    function test_constructor_nonContractWhitelist_revertsDesiredBehavior() public {
        // Setup: Prepare a non-contract whitelist address for proxy construction.
        address nonContractWhitelist = address(0xF402);

        // Call: Deploy the proxy with the EOA whitelist and expect `AddressEmptyCode`.
        vm.expectRevert(abi.encodeWithSelector(Address.AddressEmptyCode.selector, nonContractWhitelist));
        new OrganizationProxy(nonContractWhitelist);
    }

    /// @dev Verifies `setInitialImplementation` reverts when called by a non-deployer.
    function test_setInitialImplementation_unauthorizedCaller_reverts() public {
        // Setup: Deploy proxy with this contract as deployer. Impersonate a non-deployer for the call.
        OrganizationProxy proxy = new OrganizationProxy(address(whitelist));
        address otherCaller = address(0xF502);

        // Call: A non-deployer attempting to bind reverts with `UnauthorizedDeployer`.
        vm.expectRevert(IOrganizationInitialization.UnauthorizedDeployer.selector);
        vm.prank(otherCaller);
        proxy.setInitialImplementation(address(implementation));
    }

    /// @dev Verifies `setInitialImplementation` is one shot and cannot rebind after a successful call.
    function test_setInitialImplementation_isOneShot() public {
        // Setup: Deploy and bind once.
        OrganizationProxy proxy = new OrganizationProxy(address(whitelist));
        proxy.setInitialImplementation(address(implementation));

        // Call: A second bind attempt reverts with `ImplementationAlreadySet`.
        vm.expectRevert(IOrganizationInitialization.ImplementationAlreadySet.selector);
        proxy.setInitialImplementation(address(implementation));
    }

    /// @dev Verifies `setInitialImplementation` reverts with `ZeroAddress` for a zero implementation.
    function test_setInitialImplementation_zeroImplementation_reverts() public {
        OrganizationProxy proxy = new OrganizationProxy(address(whitelist));
        vm.expectRevert(IOrganizationFactory.ZeroAddress.selector);
        proxy.setInitialImplementation(address(0));
    }

    /// @dev Verifies `setInitialImplementation` reverts when the implementation is not whitelisted.
    function test_setInitialImplementation_nonWhitelistedImplementation_reverts() public {
        // Setup: Deploy proxy, then prepare a fresh implementation that is not on the whitelist.
        OrganizationProxy proxy = new OrganizationProxy(address(whitelist));
        OrganizationImplementationHarness unapproved = new OrganizationImplementationHarness();

        // Call: Binding a non-whitelisted implementation reverts with `ImplementationNotWhitelisted`.
        vm.expectRevert(
            abi.encodeWithSelector(IImplementationWhitelist.ImplementationNotWhitelisted.selector, address(unapproved))
        );
        proxy.setInitialImplementation(address(unapproved));
    }

    /// @dev Verifies `setInitialImplementation` reverts with `ERC1967InvalidImplementation` when the implementation
    ///      passes the whitelist but has no code.
    function test_setInitialImplementation_eoaImplementation_revertsInvalidImplementation() public {
        // Setup: Whitelist an EOA address and deploy a proxy that uses this whitelist.
        address eoaImplementation = address(0xE091);
        whitelist.setImplementationWhitelisted(ContractType.Organization, eoaImplementation, true);
        OrganizationProxy proxy = new OrganizationProxy(address(whitelist));

        // Call: Binding an EOA implementation reverts via the ERC-1967 code-presence check.
        vm.expectRevert(abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidImplementation.selector, eoaImplementation));
        proxy.setInitialImplementation(eoaImplementation);
    }

    /// @dev Verifies `setInitialImplementation` emits the standard ERC-1967 `Upgraded(implementation)` event.
    function test_setInitialImplementation_success_emitsUpgradedEvent() public {
        OrganizationProxy proxy = new OrganizationProxy(address(whitelist));

        vm.expectEmit(true, true, true, true, address(proxy));
        emit IERC1967.Upgraded(address(implementation));
        proxy.setInitialImplementation(address(implementation));

        bytes32 implementationWord = vm.load(address(proxy), ERC1967_IMPLEMENTATION_SLOT);
        assertEq(
            address(uint160(uint256(implementationWord))),
            address(implementation),
            "implementation slot should hold bound impl"
        );
    }

    /// @dev Verifies direct proxy deployment allows only the direct deployer to call `initialize`.
    function test_directDeployment_onlyDirectDeployerCanInitialize() public {
        // Setup: Deploy a proxy directly, bind the implementation, prepare init params.
        address directDeployer = address(0xF501);
        address otherCaller = address(0xF502);
        InitializationParams memory params = _defaultInitializationParams();

        vm.startPrank(directDeployer);
        OrganizationProxy proxy = new OrganizationProxy(address(whitelist));
        proxy.setInitialImplementation(address(implementation));
        vm.stopPrank();
        IOrganization organization = IOrganization(address(proxy));

        assertFalse(organization.isInitialized(), "proxy should start uninitialized");

        // Call: First attempt initialization from a non-deployer, then initialize from the direct deployer.
        vm.expectRevert(IOrganizationInitialization.UnauthorizedDeployer.selector);
        vm.prank(otherCaller);
        organization.initialize(params);

        vm.prank(directDeployer);
        organization.initialize(params);

        // Verify: Only the direct deployer can initialize.
        assertTrue(organization.isInitialized(), "direct deployer should be able to initialize once");
    }

    /// @dev Verifies proxy delegation preserves `getDeployerAddress` and `isInitialized` behavior before and after
    /// initialization.
    function test_proxyDelegatesInitializationViewsAndState() public {
        // Setup: Deploy a proxy directly with valid initialization params.
        address deployer = address(0xF601);
        InitializationParams memory params = _defaultInitializationParams();

        vm.startPrank(deployer);
        OrganizationProxy proxy = new OrganizationProxy(address(whitelist));
        proxy.setInitialImplementation(address(implementation));
        vm.stopPrank();
        IOrganization organization = IOrganization(address(proxy));

        // Call: Read delegated initialization views, then initialize through the proxy.
        assertEq(
            organization.getDeployerAddress(), deployer, "getDeployerAddress should delegate to implementation logic"
        );
        assertFalse(organization.isInitialized(), "isInitialized should be false before init");

        vm.prank(deployer);
        organization.initialize(params);

        // Verify: Delegated views still report the same deployer and updated initialized state after success.
        assertEq(organization.getDeployerAddress(), deployer, "deployer should remain stable after initialization");
        assertTrue(organization.isInitialized(), "isInitialized should be true after successful init");
    }

    /// @dev Verifies multiple proxies sharing one implementation maintain isolated initialization state.
    function test_multipleProxiesSameImplementation_keepInitializationStateIsolated() public {
        // Setup: Deploy two proxies with different deployers and distinct initialization parameter sets.
        address deployerA = address(0xF701);
        address deployerB = address(0xF702);

        InitializationParams memory paramsA = _defaultInitializationParams();
        paramsA.guardian = address(0xAA01);

        InitializationParams memory paramsB = _defaultInitializationParams();
        paramsB.guardian = address(0xBB01);
        paramsB.members = buildArray(MEMBER_3, ADMIN_1, ADMIN_2, MEMBER_1);

        vm.startPrank(deployerA);
        OrganizationProxy proxyAContract = new OrganizationProxy(address(whitelist));
        proxyAContract.setInitialImplementation(address(implementation));
        vm.stopPrank();
        IOrganization proxyA = IOrganization(address(proxyAContract));

        vm.startPrank(deployerB);
        OrganizationProxy proxyBContract = new OrganizationProxy(address(whitelist));
        proxyBContract.setInitialImplementation(address(implementation));
        vm.stopPrank();
        IOrganization proxyB = IOrganization(address(proxyBContract));

        // Call: Initialize both proxies independently using their respective deployers and params.
        vm.prank(deployerA);
        proxyA.initialize(paramsA);

        vm.prank(deployerB);
        proxyB.initialize(paramsB);

        // Verify: Guardian and membership state remains isolated per proxy instance.
        assertEq(proxyA.guardian(), paramsA.guardian, "proxy A guardian mismatch");
        assertEq(proxyB.guardian(), paramsB.guardian, "proxy B guardian mismatch");
        assertTrue(proxyB.isMember(MEMBER_3), "proxy B should include MEMBER_3");
        assertFalse(proxyA.isMember(MEMBER_3), "proxy A should not include proxy B-only member");
    }

    /// @dev Verifies factory-based proxy deployment does not expose an uninitialized proxy state.
    function test_factoryDeploymentPath_isInitializedAtomically() public {
        // Setup: Prepare a valid factory deployment tuple and initialization params.
        bytes32 salt = bytes32(uint256(6001));
        InitializationParams memory params = _defaultInitializationParams();

        // Call: Deploy an organization through the factory path.
        address deployed = _deployOrganization(salt, params);

        // Verify: The deployed proxy is already initialized in the same transaction.
        assertTrue(IOrganization(deployed).isInitialized(), "factory should not leave uninitialized proxy behind");
    }

    /// @dev Verifies proxy initialization does not overwrite deployer or whitelist constructor storage slots.
    function test_initialize_doesNotOverwriteDeployerOrWhitelistSlots() public {
        // Setup: Deploy a proxy directly, bind the implementation, snapshot deployer/whitelist storage words
        //        before initialization.
        address deployer = address(0xF801);
        InitializationParams memory params = _defaultInitializationParams();

        vm.startPrank(deployer);
        OrganizationProxy proxy = new OrganizationProxy(address(whitelist));
        proxy.setInitialImplementation(address(implementation));
        vm.stopPrank();
        address proxyAddr = address(proxy);
        IOrganization organization = IOrganization(proxyAddr);

        bytes32 deployerBefore = vm.load(proxyAddr, LibOrganizationDeployerAddressStorage.STORAGE_LOCATION);
        bytes32 whitelistBefore = vm.load(proxyAddr, LibOrganizationUpgradeStorage.STORAGE_LOCATION);

        // Call: Initialize the proxy and reload deployer/whitelist storage words.
        vm.prank(deployer);
        organization.initialize(params);

        bytes32 deployerAfter = vm.load(proxyAddr, LibOrganizationDeployerAddressStorage.STORAGE_LOCATION);
        bytes32 whitelistAfter = vm.load(proxyAddr, LibOrganizationUpgradeStorage.STORAGE_LOCATION);

        // Verify: Deployer and whitelist storage slots are unchanged by initialization.
        assertEq(deployerBefore, deployerAfter, "initialize should not mutate deployer slot");
        assertEq(whitelistBefore, whitelistAfter, "initialize should not mutate whitelist slot");
    }
}
