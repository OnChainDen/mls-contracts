// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {IOrganization} from "interfaces/IOrganization.sol";
import {IOrganizationFactory} from "interfaces/IOrganizationFactory.sol";
import {IOrganizationInitialization} from "interfaces/organization/IOrganizationInitialization.sol";
import {OrganizationProxy} from "organization/OrganizationProxy.sol";
import {LibOrganizationUpgradeStorage} from "organization/libraries/storage/LibOrganizationUpgradeStorage.sol";
import {
    InitializationSuiteBase
} from "test/organization/base/OrganizationInitializationBase/OrganizationInitializationBaseSuiteBase.sol";
import {InitializationParams} from "types/CommonTypes.sol";

/**
 * @dev Proxy constructor/delegation tests for initialization paths.
 */
contract OrganizationProxyTest is InitializationSuiteBase {
    /// @dev Verifies `OrganizationProxy.constructor` stores deployer, whitelist, and implementation values in their
    /// expected storage slots.
    function test_OPX_CTOR_1__OPX_CTOR_2__OPX_CTOR_3_constructor_setsDeployerWhitelistAndImplementationSlots() public {
        // Setup: Select a direct deployer account for deploying the proxy outside the factory flow.
        address directDeployer = address(0xFA01);

        // Call: Deploy the proxy and read deployer, whitelist, and implementation storage slots.
        vm.prank(directDeployer);
        address proxy = address(new OrganizationProxy(address(implementation), address(whitelist)));

        // Verify: Constructor state writes match the deployer and constructor arguments.
        IOrganization organization = IOrganization(proxy);
        assertEq(organization.getDeployerAddress(), directDeployer, "deployer slot should store constructor msg.sender");

        bytes32 whitelistWord = vm.load(proxy, LibOrganizationUpgradeStorage.STORAGE_LOCATION);
        assertEq(address(uint160(uint256(whitelistWord))), address(whitelist), "whitelist slot mismatch");

        bytes32 implementationWord = vm.load(proxy, ERC1967_IMPLEMENTATION_SLOT);
        assertEq(
            address(uint160(uint256(implementationWord))),
            address(implementation),
            "ERC1967 implementation slot mismatch"
        );
    }

    /// @dev Verifies `OrganizationProxy.constructor` reverts when the implementation address is not a contract.
    function test_OPX_CTOR_4_constructor_nonContractImplementation_reverts() public {
        // Setup: Prepare a non-contract implementation address for constructor input.
        address nonContractImplementation = address(0xF401);

        // Call: Deploy the proxy with an EOA implementation and expect `ERC1967InvalidImplementation`.
        vm.expectRevert(
            abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidImplementation.selector, nonContractImplementation)
        );
        new OrganizationProxy(nonContractImplementation, address(whitelist));

        // Verify: Constructor safety checks reject non-contract implementations.
    }

    /// @dev Verifies `OrganizationProxy.constructor` reverts with `ZeroAddress` when whitelist is zero.
    function test_OPX_CTOR_5_constructor_zeroWhitelist_revertsZeroAddress() public {
        // Setup: Prepare a zero whitelist address for constructor input.
        address zeroWhitelist = address(0);

        // Call: Deploy the proxy with a zero whitelist and expect `ZeroAddress`.
        vm.expectRevert(IOrganizationFactory.ZeroAddress.selector);
        new OrganizationProxy(address(implementation), zeroWhitelist);

        // Verify: Constructor guard enforces non-zero whitelist configuration.
    }

    /// @dev Verifies `OrganizationProxy.constructor` rejects non-contract whitelist addresses as a safety requirement.
    function test_OPX_CTOR_6_constructor_nonContractWhitelist_revertsDesiredBehavior() public {
        // Setup: Prepare a non-contract whitelist address for proxy construction.
        address nonContractWhitelist = address(0xF402);

        // Call: Deploy the proxy with the EOA whitelist and expect `AddressEmptyCode`.
        vm.expectRevert(abi.encodeWithSelector(Address.AddressEmptyCode.selector, nonContractWhitelist));
        new OrganizationProxy(address(implementation), nonContractWhitelist);

        // Verify: Revert behavior enforces that whitelist lookups must route through a contract.
    }

    /// @dev Verifies direct proxy deployment allows only the direct deployer to call `initialize`.
    function test_OPX_CTOR_7_directDeployment_onlyDirectDeployerCanInitialize() public {
        // Setup: Deploy a proxy directly and prepare initialize calls from the deployer and a different caller.
        address directDeployer = address(0xF501);
        address otherCaller = address(0xF502);
        InitializationParams memory params = _defaultInitializationParams();

        vm.prank(directDeployer);
        IOrganization organization =
            IOrganization(address(new OrganizationProxy(address(implementation), address(whitelist))));

        // Call: First attempt initialization from a non-deployer, then initialize from the direct deployer.
        vm.expectRevert(IOrganizationInitialization.UnauthorizedDeployer.selector);
        vm.prank(otherCaller);
        organization.initialize(params);

        vm.prank(directDeployer);
        organization.initialize(params);

        // Verify: Only the direct deployer can initialize and the proxy becomes initialized after that call.
        assertTrue(organization.isInitialized(), "direct deployer should be able to initialize once");
    }

    /// @dev Verifies proxy delegation preserves `getDeployerAddress` and `isInitialized` behavior before and after
    /// initialization.
    function test_OPX_DEL_1_proxyDelegatesInitializationViewsAndState() public {
        // Setup: Deploy a proxy directly with valid initialization params.
        address deployer = address(0xF601);
        InitializationParams memory params = _defaultInitializationParams();

        vm.prank(deployer);
        IOrganization organization =
            IOrganization(address(new OrganizationProxy(address(implementation), address(whitelist))));

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
    function test_OPX_DEL_2_multipleProxiesSameImplementation_keepInitializationStateIsolated() public {
        // Setup: Deploy two proxies with different deployers and distinct initialization parameter sets.
        address deployerA = address(0xF701);
        address deployerB = address(0xF702);

        InitializationParams memory paramsA = _defaultInitializationParams();
        paramsA.guardian = address(0xAA01);

        InitializationParams memory paramsB = _defaultInitializationParams();
        paramsB.guardian = address(0xBB01);
        paramsB.members = buildArray(MEMBER_3, ADMIN_1, ADMIN_2, MEMBER_1);

        vm.prank(deployerA);
        IOrganization proxyA =
            IOrganization(address(new OrganizationProxy(address(implementation), address(whitelist))));

        vm.prank(deployerB);
        IOrganization proxyB =
            IOrganization(address(new OrganizationProxy(address(implementation), address(whitelist))));

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
    function test_OPX_DEL_3_factoryDeploymentPath_isInitializedAtomically() public {
        // Setup: Prepare a valid factory deployment tuple and initialization params.
        bytes32 salt = bytes32(uint256(6001));
        InitializationParams memory params = _defaultInitializationParams();

        // Call: Deploy an organization through the factory path.
        address deployed = _deployOrganization(salt, params);

        // Verify: The deployed proxy is already initialized in the same transaction.
        assertTrue(IOrganization(deployed).isInitialized(), "factory should not leave uninitialized proxy behind");
    }

    /// @dev Verifies proxy initialization does not overwrite deployer or whitelist constructor storage slots.
    function test_OPX_DEL_4_initialize_doesNotOverwriteDeployerOrWhitelistSlots() public {
        // Setup: Deploy a proxy directly and snapshot deployer/whitelist storage words before initialization.
        address deployer = address(0xF801);
        InitializationParams memory params = _defaultInitializationParams();

        vm.prank(deployer);
        address proxy = address(new OrganizationProxy(address(implementation), address(whitelist)));
        IOrganization organization = IOrganization(proxy);

        bytes32 deployerBefore = vm.load(proxy, 0x56adc8ceae2dbb943ac8b82714e40a1aac36fca8b6dbb11dfc9941c4d04f2400);
        bytes32 whitelistBefore = vm.load(proxy, LibOrganizationUpgradeStorage.STORAGE_LOCATION);

        // Call: Initialize the proxy and reload deployer/whitelist storage words.
        vm.prank(deployer);
        organization.initialize(params);

        bytes32 deployerAfter = vm.load(proxy, 0x56adc8ceae2dbb943ac8b82714e40a1aac36fca8b6dbb11dfc9941c4d04f2400);
        bytes32 whitelistAfter = vm.load(proxy, LibOrganizationUpgradeStorage.STORAGE_LOCATION);

        // Verify: Deployer and whitelist storage slots are unchanged by initialization.
        assertEq(deployerBefore, deployerAfter, "initialize should not mutate deployer slot");
        assertEq(whitelistBefore, whitelistAfter, "initialize should not mutate whitelist slot");
    }
}
