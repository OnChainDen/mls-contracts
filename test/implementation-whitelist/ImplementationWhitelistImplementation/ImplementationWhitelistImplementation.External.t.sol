// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IImplementationWhitelist} from "interfaces/IImplementationWhitelist.sol";
import {ContractType} from "types/CommonTypes.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {
    ImplementationWhitelistHarness,
    ImplementationWhitelistV2Harness
} from "test/implementation-whitelist/ImplementationWhitelistImplementation/ImplementationWhitelistHarnesses.sol";
import {
    ImplementationWhitelistSuiteBase
} from "test/implementation-whitelist/ImplementationWhitelistImplementation/ImplementationWhitelistSuiteBase.sol";

interface IUUPSWhitelistEntrypoints {
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;
    function proxiableUUID() external view returns (bytes32);
}

/**
 * @dev External-flow tests for `ImplementationWhitelistImplementation`.
 */
contract ImplementationWhitelistExternalTest is ImplementationWhitelistSuiteBase {
    /// @dev Verifies proxy initialization sets owner and seeds both type-specific whitelists.
    function test_IWI_INIT_1_initialize_setsOwnerAndSeedsWhitelists() public {
        // Setup: deploy uninitialized proxy and deterministic organization/account seed arrays.
        ImplementationWhitelistHarness proxy = _deployUninitializedProxy();
        address[] memory orgSeeds = _pair(organizationImplementationA, organizationImplementationB);
        address[] memory accountSeeds = _pair(accountImplementationA, accountImplementationB);

        // Call: initialize proxy with owner and both seed arrays.
        proxy.initialize(OWNER, orgSeeds, accountSeeds);

        // Verify: owner and type-specific whitelist entries are correctly initialized.
        assertEq(proxy.owner(), OWNER, "owner mismatch");
        assertTrue(proxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA));
        assertTrue(proxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationB));
        assertTrue(proxy.isImplementationWhitelisted(ContractType.Account, accountImplementationA));
        assertTrue(proxy.isImplementationWhitelisted(ContractType.Account, accountImplementationB));
    }

    /// @dev Verifies initialization emits `ImplementationWhitelistInitialized(initialOwner)`.
    function test_IWI_INIT_2_initialize_emitsInitializedEvent() public {
        // Setup: deploy uninitialized proxy with empty seed arrays.
        ImplementationWhitelistHarness proxy = _deployUninitializedProxy();
        address[] memory empty;

        // Verify: initialization emits canonical initialized event with owner.
        vm.expectEmit(true, true, true, true, address(proxy));
        emit IImplementationWhitelist.ImplementationWhitelistInitialized(OWNER);

        // Call: initialize proxy.
        proxy.initialize(OWNER, empty, empty);
    }

    /// @dev Verifies proxy cannot be initialized twice.
    function test_IWI_INIT_3_initialize_cannotBeCalledTwice() public {
        // Setup: proxy from suite setup is already initialized.
        address[] memory empty;

        // Verify: second initialize attempt reverts.
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        // Call: attempt re-initialization.
        whitelistProxy.initialize(OWNER, empty, empty);
    }

    /// @dev Verifies implementation constructor disables initializers (direct initialize reverts).
    function test_IWI_INIT_4_implementationDirectInitialize_reverts() public {
        // Setup: implementation contract is deployed once in suite setup and is initializer-disabled.
        address[] memory empty;

        // Verify: direct initialize call on implementation reverts.
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        // Call: attempt initialize on implementation contract itself.
        implementation.initialize(OWNER, empty, empty);
    }

    /// @dev Verifies `isInitialized()` transitions false -> true on successful proxy initialization.
    function test_IWI_INIT_5_isInitialized_tracksInitializationState() public {
        // Setup: deploy uninitialized proxy with empty arrays.
        ImplementationWhitelistHarness proxy = _deployUninitializedProxy();
        address[] memory empty;

        // Verify: before initialization proxy reports false.
        assertFalse(proxy.isInitialized(), "proxy should start uninitialized");

        // Call: initialize proxy.
        proxy.initialize(OWNER, empty, empty);

        // Verify: after initialization proxy reports true.
        assertTrue(proxy.isInitialized(), "proxy should be initialized");
    }

    /// @dev Verifies `initialOwner == address(0)` reverts initialization.
    function test_IWI_INIT_6_initialize_zeroOwner_reverts() public {
        // Setup: deploy uninitialized proxy.
        ImplementationWhitelistHarness proxy = _deployUninitializedProxy();
        address[] memory empty;

        // Verify: zero-owner initialization is rejected.
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableInvalidOwner.selector, address(0)));
        // Call: initialize with zero owner.
        proxy.initialize(address(0), empty, empty);
    }

    /// @dev Verifies empty initial arrays still initialize successfully and set owner.
    function test_IWI_INIT_7_initialize_withEmptyArrays_succeeds() public {
        // Setup: deploy uninitialized proxy with no seed entries.
        ImplementationWhitelistHarness proxy = _deployUninitializedProxy();
        address[] memory empty;

        // Call: initialize with empty seed arrays.
        proxy.initialize(OWNER, empty, empty);

        // Verify: owner is set and no whitelist entries are implicitly enabled.
        assertEq(proxy.owner(), OWNER, "owner mismatch");
        assertFalse(proxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA));
        assertFalse(proxy.isImplementationWhitelisted(ContractType.Account, accountImplementationA));
    }

    /// @dev Verifies same address can be seeded under both Organization and Account contract types.
    function test_IWI_INIT_8_initialize_sameAddressCanBeSeededForBothTypes() public {
        // Setup: deploy uninitialized proxy and use same seed in both arrays.
        ImplementationWhitelistHarness proxy = _deployUninitializedProxy();
        address shared = organizationImplementationA;
        address[] memory orgSeeds = _single(shared);
        address[] memory accountSeeds = _single(shared);

        // Call: initialize with shared implementation seeded for both types.
        proxy.initialize(OWNER, orgSeeds, accountSeeds);

        // Verify: same address is independently whitelisted for both contract types.
        assertTrue(proxy.isImplementationWhitelisted(ContractType.Organization, shared));
        assertTrue(proxy.isImplementationWhitelisted(ContractType.Account, shared));
    }

    /// @dev Verifies `initialize` rejects zero-address implementation entries in seed arrays.
    function test_IWI_INIT_9_initialize_rejectsZeroAddressSeeds_desiredBehavior() public {
        // Setup: deploy uninitialized proxy and include zero address in seed list.
        ImplementationWhitelistHarness proxy = _deployUninitializedProxy();
        address[] memory orgSeeds = _single(address(0));
        address[] memory empty;

        // Verify: zero-address seed entries are rejected.
        vm.expectRevert();
        // Call: initialize with zero-address organization implementation seed.
        proxy.initialize(OWNER, orgSeeds, empty);
    }

    /// @dev Verifies `initialize` rejects non-contract implementation entries in seed arrays.
    function test_IWI_INIT_10_initialize_rejectsNonContractSeeds_desiredBehavior() public {
        // Setup: deploy uninitialized proxy and include no-code address in seed list.
        ImplementationWhitelistHarness proxy = _deployUninitializedProxy();
        address[] memory orgSeeds = _single(noCodeAddress);
        address[] memory empty;

        // Verify: non-contract seed entries are rejected.
        vm.expectRevert();
        // Call: initialize with non-contract organization implementation seed.
        proxy.initialize(OWNER, orgSeeds, empty);
    }

    /// @dev Verifies owner can add and remove implementations in one `whitelistImplementations` call.
    function test_IWI_WI_1_ownerCanAddAndRemoveInSingleCall() public {
        // Setup: pre-whitelist one entry to remove, then prepare add/remove lists.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(ContractType.Organization, _single(organizationImplementationA), new address[](0));

        // Call: add B and remove A in one transaction.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Organization, _single(organizationImplementationB), _single(organizationImplementationA)
        );

        // Verify: add/remove mutations are applied atomically for the selected type.
        assertFalse(whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA));
        assertTrue(whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationB));
    }

    /// @dev Verifies non-owner callers cannot mutate whitelist entries.
    function test_IWI_WI_2_nonOwnerCaller_reverts() public {
        // Setup: prepare add/remove arrays for unauthorized caller.
        address[] memory toAdd = _single(organizationImplementationA);
        address[] memory empty;

        // Verify: only owner can call whitelist mutation endpoint.
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        vm.prank(NON_OWNER);
        // Call: non-owner attempts whitelist mutation.
        whitelistProxy.whitelistImplementations(ContractType.Organization, toAdd, empty);
    }

    /// @dev Verifies Organization and Account whitelists are independent namespaces.
    function test_IWI_WI_3_contractTypeMappings_areIndependent() public {
        // Setup: whitelist same address under Organization type only.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(ContractType.Organization, _single(organizationImplementationA), new address[](0));

        // Verify: Organization entry is true while Account entry remains false.
        assertTrue(whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA));
        assertFalse(whitelistProxy.isImplementationWhitelisted(ContractType.Account, organizationImplementationA));
    }

    /// @dev Verifies whitelist mutation emits events for each added/removed implementation.
    function test_IWI_WI_4_whitelistMutation_emitsEventsPerProcessedAddress() public {
        // Setup: configure add/remove lists and seed one pre-whitelisted entry for removal event.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(ContractType.Account, _single(accountImplementationA), new address[](0));

        // Verify: expect one whitelisted and one unwhitelisted event.
        vm.expectEmit(true, true, true, true, address(whitelistProxy));
        emit IImplementationWhitelist.ImplementationWhitelisted(ContractType.Account, accountImplementationB);
        vm.expectEmit(true, true, true, true, address(whitelistProxy));
        emit IImplementationWhitelist.ImplementationUnwhitelisted(ContractType.Account, accountImplementationA);

        // Call: mutate whitelist with one add and one remove.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Account, _single(accountImplementationB), _single(accountImplementationA)
        );
    }

    /// @dev Verifies `whitelistImplementations` rejects zero-address entries in mutation arrays.
    function test_IWI_WI_5_whitelistMutation_rejectsZeroAddress_desiredBehavior() public {
        // Setup: prepare zero-address addition payload.
        address[] memory toAdd = _single(address(0));
        address[] memory empty;

        // Verify: zero-address whitelist updates are rejected.
        vm.expectRevert();
        vm.prank(OWNER);
        // Call: owner attempts to whitelist zero address.
        whitelistProxy.whitelistImplementations(ContractType.Organization, toAdd, empty);
    }

    /// @dev Verifies `whitelistImplementations` rejects non-contract entries in mutation arrays.
    function test_IWI_WI_6_whitelistMutation_rejectsNonContractAddress_desiredBehavior() public {
        // Setup: prepare no-code address addition payload.
        address[] memory toAdd = _single(noCodeAddress);
        address[] memory empty;

        // Verify: non-contract whitelist updates are rejected.
        vm.expectRevert();
        vm.prank(OWNER);
        // Call: owner attempts to whitelist no-code address.
        whitelistProxy.whitelistImplementations(ContractType.Organization, toAdd, empty);
    }

    /// @dev Verifies same address in both add/remove arrays ends unwhitelisted (add then remove).
    function test_IWI_WI_7_sameAddressInAddAndRemove_endsUnwhitelisted() public {
        // Setup: use same address in both mutation arrays.
        address[] memory both = _single(organizationImplementationA);

        // Call: mutate with add+remove for the same implementation in one call.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(ContractType.Organization, both, both);

        // Verify: final state is unwhitelisted due remove-after-add ordering.
        assertFalse(whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA));
    }

    /// @dev Verifies empty add/remove arrays are a no-op and do not revert.
    function test_IWI_WI_8_emptyArrays_noopAndNoRevert() public {
        // Setup: capture baseline whitelist state.
        bool beforeState = whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA);
        address[] memory empty;

        // Call: invoke mutation endpoint with both arrays empty.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(ContractType.Organization, empty, empty);

        // Verify: state remains unchanged and call does not revert.
        bool afterState = whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA);
        assertEq(afterState, beforeState, "empty mutation should be a no-op");
    }

    /// @dev Verifies pending owner (before `acceptOwnership`) cannot call whitelist mutation.
    function test_IWI_WI_9_pendingOwnerBeforeAccept_cannotMutateWhitelist() public {
        // Setup: initiate ownership transfer to pending owner.
        vm.prank(OWNER);
        whitelistProxy.transferOwnership(NEW_OWNER);

        // Verify: pending owner cannot act until ownership acceptance.
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NEW_OWNER));
        vm.prank(NEW_OWNER);
        // Call: pending owner attempts whitelist mutation before `acceptOwnership`.
        whitelistProxy.whitelistImplementations(
            ContractType.Organization, _single(organizationImplementationA), new address[](0)
        );
    }

    /// @dev Verifies accepted ownership transfer switches mutation rights from old owner to new owner.
    function test_IWI_WI_10_afterAccept_newOwnerCanMutate_oldOwnerCannot() public {
        // Setup: complete ownership transfer to NEW_OWNER.
        vm.prank(OWNER);
        whitelistProxy.transferOwnership(NEW_OWNER);
        vm.prank(NEW_OWNER);
        whitelistProxy.acceptOwnership();

        // Call: new owner mutates whitelist successfully.
        vm.prank(NEW_OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Organization, _single(organizationImplementationA), new address[](0)
        );

        // Verify: new owner mutation succeeded and old owner no longer has mutation rights.
        assertTrue(whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA));

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, OWNER));
        vm.prank(OWNER);
        // Call: old owner attempts post-transfer mutation.
        whitelistProxy.whitelistImplementations(
            ContractType.Organization, _single(organizationImplementationB), new address[](0)
        );
    }

    /// @dev Verifies `isImplementationWhitelisted` is true only for matching contract type entries.
    function test_IWI_VIW_1_isImplementationWhitelisted_typeScopedTruthTable() public {
        // Setup: whitelist one Organization and one Account target independently.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Organization, _single(organizationImplementationA), new address[](0)
        );
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(ContractType.Account, _single(accountImplementationA), new address[](0));

        // Call + Verify: each address is true only under its matching contract type.
        assertTrue(whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA));
        assertFalse(whitelistProxy.isImplementationWhitelisted(ContractType.Account, organizationImplementationA));
        assertTrue(whitelistProxy.isImplementationWhitelisted(ContractType.Account, accountImplementationA));
        assertFalse(whitelistProxy.isImplementationWhitelisted(ContractType.Organization, accountImplementationA));
    }

    /// @dev Verifies `validateIsImplementationWhitelistedOrRevert` reverts for non-whitelisted targets.
    function test_IWI_VIW_2_validateWhitelisted_revertsWhenNotWhitelisted() public {
        // Setup: choose target with no whitelist entry.
        address target = organizationImplementationA;

        // Verify: validation call reverts with canonical error for non-whitelisted implementation.
        vm.expectRevert(abi.encodeWithSelector(IImplementationWhitelist.ImplementationNotWhitelisted.selector, target));
        // Call: validate un-whitelisted target.
        whitelistProxy.validateIsImplementationWhitelistedOrRevert(ContractType.Organization, target);
    }

    /// @dev Verifies `validateIsImplementationWhitelistedOrRevert` succeeds for whitelisted targets.
    function test_IWI_VIW_3_validateWhitelisted_succeedsForWhitelistedTarget() public {
        // Setup: whitelist target under Organization type.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Organization, _single(organizationImplementationA), new address[](0)
        );

        // Call: validate whitelisted target.
        whitelistProxy.validateIsImplementationWhitelistedOrRevert(
            ContractType.Organization, organizationImplementationA
        );

        // Verify: validation call did not revert.
        assertTrue(true);
    }

    /// @dev Verifies validation reverts when implementation is whitelisted only under the other contract type.
    function test_IWI_VIW_4_validateWhitelisted_otherTypeOnly_reverts() public {
        // Setup: whitelist target under Account type only.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(ContractType.Account, _single(accountImplementationA), new address[](0));

        // Verify: Organization-type validation still reverts for Account-only entry.
        vm.expectRevert(
            abi.encodeWithSelector(IImplementationWhitelist.ImplementationNotWhitelisted.selector, accountImplementationA)
        );
        // Call: validate target under wrong contract type namespace.
        whitelistProxy.validateIsImplementationWhitelistedOrRevert(
            ContractType.Organization, accountImplementationA
        );
    }

    /// @dev Verifies owner can perform UUPS upgrade through proxy `upgradeToAndCall`.
    function test_IWI_UUPS_1_ownerCanUpgradeProxyViaUUPS() public {
        // Setup: initialized proxy with owner from suite setup.

        // Call: owner upgrades proxy to V2 implementation.
        vm.prank(OWNER);
        IUUPSWhitelistEntrypoints(address(whitelistProxy)).upgradeToAndCall(address(implementationV2), bytes(""));

        // Verify: proxy implementation slot points to V2.
        assertEq(_readProxyImplementation(address(whitelistProxy)), address(implementationV2), "upgrade target mismatch");
    }

    /// @dev Verifies non-owner cannot perform UUPS upgrade.
    function test_IWI_UUPS_2_nonOwnerCannotUpgradeProxy() public {
        // Setup: initialized proxy owned by OWNER.

        // Verify: non-owner upgrade attempt reverts.
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        vm.prank(NON_OWNER);
        // Call: unauthorized UUPS upgrade attempt.
        IUUPSWhitelistEntrypoints(address(whitelistProxy)).upgradeToAndCall(address(implementationV2), bytes(""));
    }

    /// @dev Verifies pending owner cannot upgrade before ownership acceptance.
    function test_IWI_UUPS_3_pendingOwnerBeforeAccept_cannotUpgrade() public {
        // Setup: initiate ownership transfer to NEW_OWNER.
        vm.prank(OWNER);
        whitelistProxy.transferOwnership(NEW_OWNER);

        // Verify: pending owner cannot upgrade before calling `acceptOwnership`.
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NEW_OWNER));
        vm.prank(NEW_OWNER);
        // Call: pending owner attempts UUPS upgrade.
        IUUPSWhitelistEntrypoints(address(whitelistProxy)).upgradeToAndCall(address(implementationV2), bytes(""));
    }

    /// @dev Verifies accepted ownership transfer revokes old owner upgrade rights and grants new owner rights.
    function test_IWI_UUPS_4_afterAccept_oldOwnerLosesUpgradeRights_newOwnerGains() public {
        // Setup: complete ownership transfer to NEW_OWNER.
        vm.prank(OWNER);
        whitelistProxy.transferOwnership(NEW_OWNER);
        vm.prank(NEW_OWNER);
        whitelistProxy.acceptOwnership();

        // Call: new owner executes upgrade.
        vm.prank(NEW_OWNER);
        IUUPSWhitelistEntrypoints(address(whitelistProxy)).upgradeToAndCall(address(implementationV2), bytes(""));

        // Verify: upgrade succeeded, and old owner can no longer upgrade.
        assertEq(_readProxyImplementation(address(whitelistProxy)), address(implementationV2), "upgrade should succeed");

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, OWNER));
        vm.prank(OWNER);
        // Call: old owner attempts another upgrade after transfer.
        IUUPSWhitelistEntrypoints(address(whitelistProxy)).upgradeToAndCall(address(implementation), bytes(""));
    }

    /// @dev Verifies UUPS upgrade with migration calldata executes migration logic.
    function test_IWI_UUPS_5_upgradeWithMigrationCalldata_executesMigration() public {
        // Setup: encode migration call on V2 implementation.
        bytes memory migrationData = abi.encodeCall(ImplementationWhitelistV2Harness.setMigrationMarker, (505));

        // Call: owner upgrades proxy with migration calldata.
        vm.prank(OWNER);
        IUUPSWhitelistEntrypoints(address(whitelistProxy)).upgradeToAndCall(address(implementationV2), migrationData);

        // Verify: migration logic executed in proxy storage context.
        assertEq(ImplementationWhitelistV2Harness(address(whitelistProxy)).getMigrationMarker(), 505, "marker mismatch");
    }

    /// @dev Verifies whitelist storage persists across UUPS upgrades.
    function test_IWI_UUPS_6_whitelistStoragePersistsAcrossUpgrade() public {
        // Setup: seed whitelist state before upgrade.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Organization, _single(organizationImplementationA), new address[](0)
        );
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(ContractType.Account, _single(accountImplementationA), new address[](0));

        // Call: owner upgrades proxy to V2.
        vm.prank(OWNER);
        IUUPSWhitelistEntrypoints(address(whitelistProxy)).upgradeToAndCall(address(implementationV2), bytes(""));

        // Verify: whitelist state survives implementation change.
        assertTrue(whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA));
        assertTrue(whitelistProxy.isImplementationWhitelisted(ContractType.Account, accountImplementationA));
    }

    /// @dev Verifies upgrade to non-UUPS or incompatible implementation reverts.
    function test_IWI_UUPS_7_upgradeToNonUUPSOrIncompatible_reverts() public {
        // Setup: initialized proxy.

        // Verify: non-UUPS target is rejected.
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC1967Utils.ERC1967InvalidImplementation.selector, address(nonUupsImplementation)
            )
        );
        vm.prank(OWNER);
        IUUPSWhitelistEntrypoints(address(whitelistProxy)).upgradeToAndCall(address(nonUupsImplementation), bytes(""));

        // Verify: incompatible UUPS UUID target is rejected.
        vm.expectRevert(
            abi.encodeWithSelector(UUPSUpgradeable.UUPSUnsupportedProxiableUUID.selector, bytes32(uint256(0xDEAD)))
        );
        vm.prank(OWNER);
        IUUPSWhitelistEntrypoints(address(whitelistProxy)).upgradeToAndCall(address(wrongUuidImplementation), bytes(""));
    }

    /// @dev Verifies calling `upgradeToAndCall` on implementation contract directly reverts due `onlyProxy`.
    function test_IWI_UUPS_8_upgradeToAndCallOnImplementationContract_revertsOnlyProxy() public {
        // Setup: implementation call context (not delegatecall via proxy).

        // Verify: direct implementation invocation is rejected by UUPS call-context guard.
        vm.expectRevert(UUPSUpgradeable.UUPSUnauthorizedCallContext.selector);
        // Call: invoke UUPS entrypoint directly on implementation.
        IUUPSWhitelistEntrypoints(address(implementation)).upgradeToAndCall(address(implementationV2), bytes(""));
    }

    /// @dev Verifies calling `proxiableUUID` through proxy reverts due `notDelegated`.
    function test_IWI_UUPS_9_proxiableUUIDThroughProxy_revertsNotDelegated() public {
        // Setup: proxy call context.

        // Verify: `proxiableUUID` cannot be called through proxy delegatecall context.
        vm.expectRevert(UUPSUpgradeable.UUPSUnauthorizedCallContext.selector);
        // Call: invoke `proxiableUUID` through proxy.
        IUUPSWhitelistEntrypoints(address(whitelistProxy)).proxiableUUID();
    }

    /// @dev Verifies owner-triggered `upgradeToAndCall` rejects zero and no-code implementation targets.
    function test_IWI_UUPS_10_ownerCannotUpgradeToZeroOrNoCode_desiredBehavior() public {
        // Setup: initialized proxy owned by OWNER.

        // Verify: zero-address target is rejected.
        vm.expectRevert();
        vm.prank(OWNER);
        // Call: attempt UUPS upgrade to zero address.
        IUUPSWhitelistEntrypoints(address(whitelistProxy)).upgradeToAndCall(address(0), bytes(""));

        // Verify: no-code target is rejected.
        vm.expectRevert();
        vm.prank(OWNER);
        // Call: attempt UUPS upgrade to no-code address.
        IUUPSWhitelistEntrypoints(address(whitelistProxy)).upgradeToAndCall(noCodeAddress, bytes(""));
    }
}
