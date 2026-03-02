// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Vm} from "forge-std/Vm.sol";

import {IOrganization} from "interfaces/IOrganization.sol";
import {IOrganizationInitialization} from "interfaces/organization/IOrganizationInitialization.sol";
import {OrganizationProxy} from "organization/OrganizationProxy.sol";
import {
    InitializationSuiteBase
} from "test/organization/base/OrganizationInitializationBase/OrganizationInitializationBaseSuiteBase.sol";
import {InitializationParams} from "types/CommonTypes.sol";

/**
 * @dev OrganizationInitializationBase coverage for initialize/view behavior.
 */
contract OrganizationInitializationBaseTest is InitializationSuiteBase {
    /// @dev Verifies `OrganizationInitializationBase.initialize` rejects non-deployer callers on an uninitialized
    /// proxy.
    function test_OIB_INIT_1_uninitializedProxy_nonDeployerRevertsUnauthorizedDeployer() public {
        // Setup: Deploy an uninitialized proxy and prepare valid initialization params.
        vm.prank(AUTHORIZED_DEPLOYER);
        address proxy = address(new OrganizationProxy(address(implementation), address(whitelist)));
        InitializationParams memory params = _defaultInitializationParams();

        // Call: Attempt initialization from a non-deployer and expect `UnauthorizedDeployer`.
        vm.expectRevert(IOrganizationInitialization.UnauthorizedDeployer.selector);
        vm.prank(UNAUTHORIZED_CALLER);
        IOrganizationInitialization(proxy).initialize(params);

        // Verify: Failed initialization keeps the proxy in the uninitialized state.
        assertFalse(
            IOrganizationInitialization(proxy).isInitialized(), "failed initialize should keep proxy uninitialized"
        );
    }

    /// @dev Verifies `OrganizationInitializationBase.initialize` succeeds for the deployer, preserves deployer storage,
    /// and emits one initialization event.
    function test_OIB_INIT_2__OIB_INIT_6__OIB_VIEW_1__OIB_VIEW_2__OIB_VIEW_3__OIB_VIEW_4__OIB_VIEW_5__CFI_FLOW_6_validInitialize_setsStateAndEmitsOneInitializedEvent()
        public
    {
        // Setup: Deploy a proxy, prepare valid params, assert pre-init views, and begin log recording.
        vm.prank(AUTHORIZED_DEPLOYER);
        address proxy = address(new OrganizationProxy(address(implementation), address(whitelist)));

        InitializationParams memory params = _defaultInitializationParams();
        IOrganization organization = IOrganization(proxy);

        assertEq(organization.getDeployerAddress(), AUTHORIZED_DEPLOYER, "proxy deployer storage mismatch before init");
        assertFalse(organization.isInitialized(), "proxy should start uninitialized");

        vm.recordLogs();

        // Call: Initialize the proxy through the authorized deployer.
        vm.prank(AUTHORIZED_DEPLOYER);
        organization.initialize(params);

        // Verify: Deployer and initialized status are correct, full state is configured, and one event is emitted.
        assertEq(organization.getDeployerAddress(), AUTHORIZED_DEPLOYER, "deployer should remain unchanged after init");
        assertTrue(organization.isInitialized(), "proxy should become initialized after successful initialize");
        _assertInitializedState(organization, params);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_countTopic(logs, ORG_INITIALIZED_TOPIC), 1, "initialize should emit exactly one event");
    }

    /// @dev Verifies initialize guards for direct implementation calls, failed-init retry behavior, and post-success
    /// reinitialization attempts.
    function test_OIB_INIT_3__OIB_INIT_4__OIB_INIT_5__OIB_VIEW_6__CFI_FLOW_4__CFI_FLOW_5_reinitAndDirectImplementationPathsRevertAsExpected()
        public
    {
        // Setup: Build one valid and one invalid initialization payload.
        InitializationParams memory params = _defaultInitializationParams();
        InitializationParams memory invalidParams = _defaultInitializationParams();
        invalidParams.members = buildEmptyAddressArray();

        // Call: Exercise direct implementation initialize, failed proxy initialize, successful initialize, and both
        // reinitialize paths.
        vm.expectRevert(IOrganizationInitialization.UnauthorizedDeployer.selector);
        implementation.initialize(params);

        // Verify: Direct implementation deployer stays zero and failed initialization does not lock subsequent valid
        // initialization.
        assertEq(implementation.getDeployerAddress(), address(0), "implementation deployer slot should be zero");

        vm.prank(AUTHORIZED_DEPLOYER);
        address proxy = address(new OrganizationProxy(address(implementation), address(whitelist)));
        IOrganization organization = IOrganization(proxy);

        vm.expectRevert(IOrganizationInitialization.NoMembersProvided.selector);
        vm.prank(AUTHORIZED_DEPLOYER);
        organization.initialize(invalidParams);
        assertFalse(organization.isInitialized(), "failed initialize should not lock initialization");

        vm.prank(AUTHORIZED_DEPLOYER);
        organization.initialize(params);

        vm.expectRevert();
        vm.prank(UNAUTHORIZED_CALLER);
        organization.initialize(params);

        vm.expectRevert();
        vm.prank(AUTHORIZED_DEPLOYER);
        organization.initialize(params);
    }
}
