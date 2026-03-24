// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {IOrganizationInitialization} from "interfaces/organization/IOrganizationInitialization.sol";
import {OrganizationProxy} from "organization/OrganizationProxy.sol";
import {
    InitializationSuiteBase
} from "test/organization/base/OrganizationInitializationBase/OrganizationInitializationBaseSuiteBase.sol";
import {InitializationParams} from "types/CommonTypes.sol";

/**
 * @dev Fuzz tests for `OrganizationInitializationBase`.
 */
contract OrganizationInitializationBaseFuzzTest is InitializationSuiteBase {
    /// @dev Verifies only the deployer can initialize and the base initialization path flips `false -> true` exactly
    /// once.
    /// @param directDeployer Fuzzed deployer used for the direct proxy deployment path.
    /// @param otherCaller Fuzzed non-deployer caller used for unauthorized initialization attempts.
    function testFuzz_initialize_onlyDeployerAndSingleUse(address directDeployer, address otherCaller) public {
        // Setup: deploy a proxy directly, choose a distinct unauthorized caller, and prepare valid init params.
        vm.assume(directDeployer != address(0));
        vm.assume(otherCaller != address(0));
        vm.assume(otherCaller != directDeployer);
        InitializationParams memory params = _defaultInitializationParams();

        vm.prank(directDeployer);
        IOrganizationInitialization organization =
            IOrganizationInitialization(address(new OrganizationProxy(address(implementation), address(whitelist))));
        assertFalse(organization.isInitialized(), "proxy should start uninitialized");

        // Call: try unauthorized initialization first, then initialize successfully once, then retry initialization.
        vm.expectRevert(IOrganizationInitialization.UnauthorizedDeployer.selector);
        vm.prank(otherCaller);
        organization.initialize(params);

        vm.prank(directDeployer);
        organization.initialize(params);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vm.prank(directDeployer);
        organization.initialize(params);

        // Verify: only the deployer can cross the single allowed `false -> true` initialization transition.
        assertTrue(organization.isInitialized(), "deployer should be able to initialize exactly once");
    }
}
