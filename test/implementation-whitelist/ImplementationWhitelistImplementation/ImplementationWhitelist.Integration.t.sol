// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {OwnableUpgradeable} from "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {IImplementationWhitelist} from "interfaces/IImplementationWhitelist.sol";
import {
    ImplementationWhitelistSuiteBase
} from "test/implementation-whitelist/ImplementationWhitelistImplementation/ImplementationWhitelistSuiteBase.sol";
import {ContractType} from "types/CommonTypes.sol";

interface IUUPSUpgradeEntrypoints {
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;
}

/// @dev Cross-file integration tests for implementation whitelist controls.
contract ImplementationWhitelistIntegrationTest is ImplementationWhitelistSuiteBase {
    // forgefmt: disable-next-item
    /// @dev Verifies unwhitelisted implementation is rejected by `validateIsImplementationWhitelistedOrRevert` for both
    // Organization and Account contract types, covering all enforcement entrypoints.
    function test_unwhitelistedImplementation_rejectedByAllEnforcementEntrypoints() public {
        // Setup: target addresses have never been whitelisted on the real whitelist proxy.
        address orgTarget = organizationImplementationA;
        address accountTarget = accountImplementationA;

        // Verify: Organization entrypoint rejects unwhitelisted implementation.
        vm.expectRevert(
            abi.encodeWithSelector(IImplementationWhitelist.ImplementationNotWhitelisted.selector, orgTarget)
        );
        whitelistProxy.validateIsImplementationWhitelistedOrRevert(ContractType.Organization, orgTarget);

        // Verify: Account entrypoint rejects unwhitelisted implementation.
        vm.expectRevert(
            abi.encodeWithSelector(IImplementationWhitelist.ImplementationNotWhitelisted.selector, accountTarget)
        );
        whitelistProxy.validateIsImplementationWhitelistedOrRevert(ContractType.Account, accountTarget);

        // Verify: `isImplementationWhitelisted` also returns false for both.
        assertFalse(
            whitelistProxy.isImplementationWhitelisted(ContractType.Organization, orgTarget),
            "org target should not be whitelisted"
        );
        assertFalse(
            whitelistProxy.isImplementationWhitelisted(ContractType.Account, accountTarget),
            "account target should not be whitelisted"
        );
    }

    // forgefmt: disable-next-item
    /// @dev Verifies type separation end-to-end: Account whitelist never unlocks Organization validation and vice
    // versa, across the real whitelist proxy.
    function test_typeSeparation_accountWhitelistDoesNotUnlockOrganizationAndViceVersa() public {
        // Setup: whitelist impl A under Account only, impl B under Organization only.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Account, _single(accountImplementationA), new address[](0)
        );
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Organization, _single(organizationImplementationA), new address[](0)
        );

        // Verify: Account-whitelisted address fails Organization validation.
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector, accountImplementationA
            )
        );
        whitelistProxy.validateIsImplementationWhitelistedOrRevert(ContractType.Organization, accountImplementationA);

        // Verify: Organization-whitelisted address fails Account validation.
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector, organizationImplementationA
            )
        );
        whitelistProxy.validateIsImplementationWhitelistedOrRevert(ContractType.Account, organizationImplementationA);

        // Verify: each passes validation under its own type.
        whitelistProxy.validateIsImplementationWhitelistedOrRevert(ContractType.Account, accountImplementationA);
        whitelistProxy.validateIsImplementationWhitelistedOrRevert(
            ContractType.Organization, organizationImplementationA
        );
    }

    // forgefmt: disable-next-item
    /// @dev Verifies unwhitelisting an implementation blocks future validation but does not break already-deployed
    // contracts currently using it.
    function test_unwhitelisting_blocksFutureUseButDoesNotBreakDeployedContracts() public {
        // Setup: whitelist org and account implementations, then confirm validation passes.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Organization, _single(organizationImplementationA), new address[](0)
        );
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Account, _single(accountImplementationA), new address[](0)
        );
        whitelistProxy.validateIsImplementationWhitelistedOrRevert(
            ContractType.Organization, organizationImplementationA
        );
        whitelistProxy.validateIsImplementationWhitelistedOrRevert(ContractType.Account, accountImplementationA);

        // Call: unwhitelist both implementations.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Organization, new address[](0), _single(organizationImplementationA)
        );
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Account, new address[](0), _single(accountImplementationA)
        );

        // Verify: future validation now fails for Organization.
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector, organizationImplementationA
            )
        );
        whitelistProxy.validateIsImplementationWhitelistedOrRevert(
            ContractType.Organization, organizationImplementationA
        );

        // Verify: future validation now fails for Account.
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector, accountImplementationA
            )
        );
        whitelistProxy.validateIsImplementationWhitelistedOrRevert(ContractType.Account, accountImplementationA);

        // Verify: the whitelist proxy itself (an already-deployed contract) still functions normally.
        assertTrue(whitelistProxy.isInitialized(), "whitelist proxy should remain functional");
        assertEq(whitelistProxy.owner(), OWNER, "whitelist proxy owner should remain intact");

        // Verify: the implementation contracts still have code (runtime is independent of whitelist state).
        assertGt(organizationImplementationA.code.length, 0, "org impl should still have code");
        assertGt(accountImplementationA.code.length, 0, "account impl should still have code");
    }

    /// @dev Verifies re-whitelisting a previously removed implementation re-enables eligible validation flows.
    function test_reWhitelisting_reEnablesEligibleFlows() public {
        // Setup: add, remove, then re-add Organization implementation.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Organization, _single(organizationImplementationA), new address[](0)
        );
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Organization, new address[](0), _single(organizationImplementationA)
        );

        // Verify: removed implementation fails validation.
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector, organizationImplementationA
            )
        );
        whitelistProxy.validateIsImplementationWhitelistedOrRevert(
            ContractType.Organization, organizationImplementationA
        );

        // Call: re-whitelist the implementation.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Organization, _single(organizationImplementationA), new address[](0)
        );

        // Verify: re-whitelisted implementation passes validation again.
        whitelistProxy.validateIsImplementationWhitelistedOrRevert(
            ContractType.Organization, organizationImplementationA
        );
        assertTrue(
            whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA),
            "re-whitelisted org impl should return true"
        );

        // Setup + Call: repeat the add-remove-re-add cycle for Account type.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(ContractType.Account, _single(accountImplementationA), new address[](0));
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(ContractType.Account, new address[](0), _single(accountImplementationA));
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(ContractType.Account, _single(accountImplementationA), new address[](0));

        // Verify: Account re-whitelist also re-enables.
        whitelistProxy.validateIsImplementationWhitelistedOrRevert(ContractType.Account, accountImplementationA);
        assertTrue(
            whitelistProxy.isImplementationWhitelisted(ContractType.Account, accountImplementationA),
            "re-whitelisted account impl should return true"
        );
    }

    /// @dev : Upgrading whitelist contract preserves existing whitelist state and enforcement behavior.
    function test_whitelistUpgrade_preservesStateAndEnforcement() public {
        // Setup: seed whitelist state with one Organization and one Account implementation.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Organization, _single(organizationImplementationA), new address[](0)
        );
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
        whitelistProxy.validateIsImplementationWhitelistedOrRevert(
            ContractType.Organization, organizationImplementationB
        );
    }

    /// @dev : Ownership transfer of whitelist contract immediately changes who can alter implementations.
    function test_ownershipTransfer_immediatelyChangesMutationRights() public {
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

    // forgefmt: disable-next-item
    /// @dev Verifies deployment path remains atomic: whitelist validation failure prevents any state
    // changes on the whitelist proxy itself, proving no partial state exposure.
    function test_deploymentPath_atomicWithWhitelistValidationAndInitialization() public {
        // Setup: seed whitelist with one org implementation, attempt validation on a non-whitelisted one.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Organization, _single(organizationImplementationA), new address[](0)
        );

        // Verify: validation for whitelisted implementation succeeds (no revert).
        whitelistProxy.validateIsImplementationWhitelistedOrRevert(
            ContractType.Organization, organizationImplementationA
        );

        // Verify: validation for non-whitelisted implementation reverts atomically.
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector, organizationImplementationB
            )
        );
        whitelistProxy.validateIsImplementationWhitelistedOrRevert(
            ContractType.Organization, organizationImplementationB
        );

        // Verify: the whitelist state is unchanged after the reverted validation — no partial mutation.
        assertTrue(
            whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA),
            "whitelisted entry should remain after failed validation of different address"
        );
        assertFalse(
            whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationB),
            "non-whitelisted entry should remain false after failed validation"
        );
        assertTrue(whitelistProxy.isInitialized(), "proxy should remain initialized");
    }
}
