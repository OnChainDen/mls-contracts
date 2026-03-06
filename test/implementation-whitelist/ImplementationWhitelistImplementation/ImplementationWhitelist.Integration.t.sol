// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {OwnableUpgradeable} from "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {IImplementationWhitelist} from "interfaces/IImplementationWhitelist.sol";
import {ImplementationWhitelistHarness, ImplementationWhitelistV2Harness}
    from "test/implementation-whitelist/ImplementationWhitelistImplementation/ImplementationWhitelistHarnesses.sol";
import {ImplementationWhitelistSuiteBase}
    from "test/implementation-whitelist/ImplementationWhitelistImplementation/ImplementationWhitelistSuiteBase.sol";
import {ContractType} from "types/CommonTypes.sol";

interface IUUPSUpgradeEntrypoints {
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;
}

/// @dev Cross-file integration tests for implementation whitelist controls.
contract ImplementationWhitelistIntegrationTest is ImplementationWhitelistSuiteBase {
    /// @dev IWC-INT-5: Upgrading whitelist contract preserves existing whitelist state and enforcement behavior.
    function test_IWC_INT_5_whitelistUpgrade_preservesStateAndEnforcement() public {
        // Setup: seed whitelist state with one Organization and one Account implementation.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(ContractType.Organization, _single(organizationImplementationA), new address[](0));
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(ContractType.Account, _single(accountImplementationA), new address[](0));

        // Call: upgrade whitelist proxy to V2.
        vm.prank(OWNER);
        IUUPSUpgradeEntrypoints(address(whitelistProxy)).upgradeToAndCall(address(implementationV2), bytes(""));

        // Verify: whitelist state preserved after upgrade.
        assertTrue(
            whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA),
            "org impl A should remain whitelisted after upgrade"
        );
        assertTrue(
            whitelistProxy.isImplementationWhitelisted(ContractType.Account, accountImplementationA),
            "account impl A should remain whitelisted after upgrade"
        );
        assertFalse(
            whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationB),
            "org impl B should remain non-whitelisted after upgrade"
        );

        // Verify: enforcement still works — non-whitelisted implementation reverts.
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector, organizationImplementationB
            )
        );
        whitelistProxy.validateIsImplementationWhitelistedOrRevert(ContractType.Organization, organizationImplementationB);
    }

    /// @dev IWC-INT-6: Ownership transfer of whitelist contract immediately changes who can alter implementations.
    function test_IWC_INT_6_ownershipTransfer_immediatelyChangesMutationRights() public {
        // Setup: transfer ownership from OWNER to NEW_OWNER via two-step transfer.
        vm.prank(OWNER);
        whitelistProxy.transferOwnership(NEW_OWNER);
        vm.prank(NEW_OWNER);
        whitelistProxy.acceptOwnership();

        // Call: NEW_OWNER adds an implementation.
        vm.prank(NEW_OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Organization, _single(organizationImplementationA), new address[](0)
        );

        // Verify: NEW_OWNER can mutate whitelist state.
        assertTrue(
            whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA),
            "NEW_OWNER should be able to whitelist implementations"
        );

        // Verify: OWNER can no longer mutate whitelist state.
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, OWNER));
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Organization, _single(organizationImplementationB), new address[](0)
        );
    }
}
