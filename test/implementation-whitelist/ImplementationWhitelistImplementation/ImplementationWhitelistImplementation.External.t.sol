// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {OwnableUpgradeable} from "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IImplementationWhitelist} from "interfaces/IImplementationWhitelist.sol";
import {
    ImplementationWhitelistHarness,
    ImplementationWhitelistV2Harness
} from "test/implementation-whitelist/ImplementationWhitelistImplementation/ImplementationWhitelistHarnesses.sol";
import {
    ImplementationWhitelistSuiteBase
} from "test/implementation-whitelist/ImplementationWhitelistImplementation/ImplementationWhitelistSuiteBase.sol";
import {ContractType} from "types/CommonTypes.sol";

interface IUUPSWhitelistEntrypoints {
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;
    function proxiableUUID() external view returns (bytes32);
}

/**
 * @dev External-flow tests for `ImplementationWhitelistImplementation`.
 */
contract ImplementationWhitelistExternalTest is ImplementationWhitelistSuiteBase {
    // forgefmt: disable-next-item
    /// @dev Verifies implementation constructor disables initializers (direct initialize reverts).
    function test_IWI_INIT_4_IWI_CON_1_IWI_CON_2_constructorDisablesInitializers_directCallReverts() public {
        // Setup: implementation contract is deployed once in suite setup and is initializer-disabled.
        address[] memory empty;

        // Verify: direct initialize call on implementation reverts.
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        // Call: attempt initialize on implementation contract itself.
        implementation.initialize(OWNER, empty, empty);
    }

    // forgefmt: disable-next-item
    /// @dev Verifies proxy initialization sets owner and seeds both type-specific whitelists.
    function test_IWI_INIT_1_IWI_INIT_2_IWI_INIT_3_IWI_INIT_4_IWI_INIT_5_initialize_setsOwnerAndSeedsWhitelists()
        public
    {
        // Setup: deploy uninitialized proxy and deterministic organization/account seed arrays.
        ImplementationWhitelistHarness proxy = _deployUninitializedProxy();
        address[] memory orgSeeds = _pair(organizationImplementationA, organizationImplementationB);
        address[] memory accountSeeds = _pair(accountImplementationA, accountImplementationB);

        // Call: initialize proxy with owner and both seed arrays.
        proxy.initialize(OWNER, orgSeeds, accountSeeds);

        // Verify: owner and type-specific whitelist entries are correctly initialized.
        assertEq(proxy.owner(), OWNER, "owner mismatch");
        assertTrue(
            proxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA),
            "orgA should be whitelisted"
        );
        assertTrue(
            proxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationB),
            "orgB should be whitelisted"
        );
        assertTrue(
            proxy.isImplementationWhitelisted(ContractType.Account, accountImplementationA),
            "accountA should be whitelisted"
        );
        assertTrue(
            proxy.isImplementationWhitelisted(ContractType.Account, accountImplementationB),
            "accountB should be whitelisted"
        );
    }

    /// @dev Verifies initialization emits `ImplementationWhitelistInitialized(initialOwner)`.
    function test_IWI_INIT_2_IWI_INIT_9_initialize_emitsInitializedEvent() public {
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
    function test_IWI_INIT_3_IWI_INIT_12_initialize_cannotBeCalledTwice() public {
        // Setup: proxy from suite setup is already initialized.
        address[] memory empty;

        // Verify: second initialize attempt reverts.
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        // Call: attempt re-initialization.
        whitelistProxy.initialize(OWNER, empty, empty);
    }

    // forgefmt: disable-next-item
    /// @dev Verifies `isInitialized()` transitions false -> true on successful proxy initialization.
    function test_IWI_INIT_5_IWI_INIT_1_IWI_ISI_1_IWI_ISI_2_isInitialized_tracksInitializationState() public {
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
    function test_IWI_INIT_6_IWI_INIT_11_initialize_zeroOwner_reverts() public {
        // Setup: deploy uninitialized proxy.
        ImplementationWhitelistHarness proxy = _deployUninitializedProxy();
        address[] memory empty;

        // Verify: zero-owner initialization is rejected.
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableInvalidOwner.selector, address(0)));
        // Call: initialize with zero owner.
        proxy.initialize(address(0), empty, empty);
    }

    /// @dev Verifies empty initial arrays still initialize successfully and set owner.
    function test_IWI_INIT_7_IWI_INIT_10_initialize_withEmptyArrays_succeeds() public {
        // Setup: deploy uninitialized proxy with no seed entries.
        ImplementationWhitelistHarness proxy = _deployUninitializedProxy();
        address[] memory empty;

        // Call: initialize with empty seed arrays.
        proxy.initialize(OWNER, empty, empty);

        // Verify: owner is set and no whitelist entries are implicitly enabled.
        assertEq(proxy.owner(), OWNER, "owner mismatch");
        assertFalse(
            proxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA),
            "orgA should not be whitelisted"
        );
        assertFalse(
            proxy.isImplementationWhitelisted(ContractType.Account, accountImplementationA),
            "accountA should not be whitelisted"
        );
    }

    /// @dev Verifies `initialize` emits `ImplementationWhitelisted` for each organization implementation in init array.
    function test_IWI_INIT_7_initialize_emitsWhitelistedEventPerOrgImplementation() public {
        // Setup: deploy uninitialized proxy with organization seed entries.
        ImplementationWhitelistHarness proxy = _deployUninitializedProxy();
        address[] memory orgSeeds = _pair(organizationImplementationA, organizationImplementationB);
        address[] memory empty;

        // Verify: expect one `ImplementationWhitelisted` event per org entry.
        vm.expectEmit(true, true, true, true, address(proxy));
        emit IImplementationWhitelist.ImplementationWhitelisted(ContractType.Organization, organizationImplementationA);
        vm.expectEmit(true, true, true, true, address(proxy));
        emit IImplementationWhitelist.ImplementationWhitelisted(ContractType.Organization, organizationImplementationB);

        // Call: initialize proxy with org seed entries.
        proxy.initialize(OWNER, orgSeeds, empty);
    }

    /// @dev Verifies `initialize` emits `ImplementationWhitelisted` for each account implementation in init array.
    function test_IWI_INIT_8_initialize_emitsWhitelistedEventPerAccountImplementation() public {
        // Setup: deploy uninitialized proxy with account seed entries.
        ImplementationWhitelistHarness proxy = _deployUninitializedProxy();
        address[] memory empty;
        address[] memory accountSeeds = _pair(accountImplementationA, accountImplementationB);

        // Verify: expect one `ImplementationWhitelisted` event per account entry.
        vm.expectEmit(true, true, true, true, address(proxy));
        emit IImplementationWhitelist.ImplementationWhitelisted(ContractType.Account, accountImplementationA);
        vm.expectEmit(true, true, true, true, address(proxy));
        emit IImplementationWhitelist.ImplementationWhitelisted(ContractType.Account, accountImplementationB);

        // Call: initialize proxy with account seed entries.
        proxy.initialize(OWNER, empty, accountSeeds);
    }

    /// @dev Verifies same address can be seeded under both Organization and Account contract types.
    function test_IWI_INIT_8_IWI_INIT_6_initialize_sameAddressCanBeSeededForBothTypes() public {
        // Setup: deploy uninitialized proxy and use same seed in both arrays.
        ImplementationWhitelistHarness proxy = _deployUninitializedProxy();
        address shared = organizationImplementationA;
        address[] memory orgSeeds = _single(shared);
        address[] memory accountSeeds = _single(shared);

        // Call: initialize with shared implementation seeded for both types.
        proxy.initialize(OWNER, orgSeeds, accountSeeds);

        // Verify: same address is independently whitelisted for both contract types.
        assertTrue(
            proxy.isImplementationWhitelisted(ContractType.Organization, shared),
            "shared should be whitelisted under Organization"
        );
        assertTrue(
            proxy.isImplementationWhitelisted(ContractType.Account, shared),
            "shared should be whitelisted under Account"
        );
    }

    // forgefmt: disable-next-item
    /// @dev Verifies `isInitialized()` remains true after ownership transfer via `transferOwnership` +
    // `acceptOwnership`.
    function test_IWI_ISI_3_isInitialized_remainsTrueAfterOwnershipTransfer() public {
        // Setup: proxy is initialized from suite setup. Transfer ownership.
        vm.prank(OWNER);
        whitelistProxy.transferOwnership(NEW_OWNER);
        vm.prank(NEW_OWNER);
        whitelistProxy.acceptOwnership();

        // Verify: isInitialized still returns true after ownership transfer.
        assertTrue(whitelistProxy.isInitialized(), "isInitialized should remain true after ownership transfer");
    }

    /// @dev Verifies initialization state is monotonic (false -> true only once; no return to false). [DESIRED]
    function test_IWI_ISI_4_initializationState_isPermanent() public {
        // Setup: deploy and initialize proxy.
        ImplementationWhitelistHarness proxy = _deployUninitializedProxy();
        address[] memory empty;
        assertFalse(proxy.isInitialized(), "should start uninitialized");

        proxy.initialize(OWNER, empty, empty);
        assertTrue(proxy.isInitialized(), "should be initialized after init");

        // Verify: second initialization attempt reverts (state stays true).
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        proxy.initialize(OWNER, empty, empty);

        // Verify: isInitialized remains true after failed re-initialization.
        assertTrue(proxy.isInitialized(), "should remain initialized after failed re-init");
    }

    /// @dev Verifies owner can add and remove implementations in one `whitelistImplementations` call.
    function test_IWI_WI_1_IWI_WI_4_IWI_WI_6_ownerCanAddAndRemoveInSingleCall() public {
        // Setup: pre-whitelist one entry to remove, then prepare add/remove lists.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Organization, _single(organizationImplementationA), new address[](0)
        );

        // Call: add B and remove A in one transaction.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Organization, _single(organizationImplementationB), _single(organizationImplementationA)
        );

        // Verify: add/remove mutations are applied atomically for the selected type.
        assertFalse(
            whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA),
            "orgA should be unwhitelisted after removal"
        );
        assertTrue(
            whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationB),
            "orgB should be whitelisted after addition"
        );
    }

    /// @dev Verifies non-owner callers cannot mutate whitelist entries.
    function test_IWI_WI_2_IWI_WI_1_nonOwnerCaller_reverts() public {
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
    function test_IWI_WI_3_IWI_WI_13_contractTypeMappings_areIndependent() public {
        // Setup: whitelist same address under Organization type only.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Organization, _single(organizationImplementationA), new address[](0)
        );
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(ContractType.Account, _single(accountImplementationA), new address[](0));

        // Verify: each address is true only under its matching contract type.
        assertTrue(whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA));
        assertFalse(whitelistProxy.isImplementationWhitelisted(ContractType.Account, organizationImplementationA));
        assertTrue(whitelistProxy.isImplementationWhitelisted(ContractType.Account, accountImplementationA));
        assertFalse(whitelistProxy.isImplementationWhitelisted(ContractType.Organization, accountImplementationA));
    }

    // forgefmt: disable-next-item
    /// @dev Verifies whitelist mutation emits events for each added/removed implementation.
    function test_IWI_WI_4_IWI_WI_11_IWI_WI_12_whitelistMutation_emitsEventsPerProcessedAddress() public {
        // Setup: seed two Account entries for removal and prepare two fresh additions under the same contract type.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Account, _pair(accountImplementationA, accountImplementationB), new address[](0)
        );

        // Verify: expect one event per processed add/remove entry in the external mutation call.
        vm.expectEmit(true, true, true, true, address(whitelistProxy));
        emit IImplementationWhitelist.ImplementationWhitelisted(ContractType.Account, organizationImplementationA);
        vm.expectEmit(true, true, true, true, address(whitelistProxy));
        emit IImplementationWhitelist.ImplementationWhitelisted(ContractType.Account, organizationImplementationB);
        vm.expectEmit(true, true, true, true, address(whitelistProxy));
        emit IImplementationWhitelist.ImplementationUnwhitelisted(ContractType.Account, accountImplementationA);
        vm.expectEmit(true, true, true, true, address(whitelistProxy));
        emit IImplementationWhitelist.ImplementationUnwhitelisted(ContractType.Account, accountImplementationB);

        // Call: add two new Account-type entries and remove the two seeded entries in one owner call.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Account,
            _pair(organizationImplementationA, organizationImplementationB),
            _pair(accountImplementationA, accountImplementationB)
        );

        // Verify: added entries end true and removed entries end false after the batched mutation.
        assertTrue(
            whitelistProxy.isImplementationWhitelisted(ContractType.Account, organizationImplementationA),
            "first added entry should be whitelisted"
        );
        assertTrue(
            whitelistProxy.isImplementationWhitelisted(ContractType.Account, organizationImplementationB),
            "second added entry should be whitelisted"
        );
        assertFalse(
            whitelistProxy.isImplementationWhitelisted(ContractType.Account, accountImplementationA),
            "first removed entry should be unwhitelisted"
        );
        assertFalse(
            whitelistProxy.isImplementationWhitelisted(ContractType.Account, accountImplementationB),
            "second removed entry should be unwhitelisted"
        );
    }

    /// @dev Verifies `whitelistImplementations` adds account implementation and sets whitelist to true.
    function test_IWI_WI_5_ownerCanAddAccountImplementation() public {
        // Setup: confirm account implementation is not whitelisted.
        assertFalse(
            whitelistProxy.isImplementationWhitelisted(ContractType.Account, accountImplementationA),
            "accountA should not be whitelisted initially"
        );

        // Call: owner adds account implementation.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(ContractType.Account, _single(accountImplementationA), new address[](0));

        // Verify: account implementation is now whitelisted.
        assertTrue(
            whitelistProxy.isImplementationWhitelisted(ContractType.Account, accountImplementationA),
            "accountA should be whitelisted after addition"
        );
    }

    /// @dev Verifies same address in both add/remove arrays ends unwhitelisted (add then remove).
    function test_IWI_WI_7_sameAddressInAddAndRemove_endsUnwhitelisted() public {
        // Setup: use same address in both mutation arrays.
        address[] memory both = _single(organizationImplementationA);

        // Call: mutate with add+remove for the same implementation in one call.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(ContractType.Organization, both, both);

        // Verify: final state is unwhitelisted due remove-after-add ordering.
        assertFalse(
            whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA),
            "orgA should be unwhitelisted when in both add and remove"
        );
    }

    /// @dev Verifies empty add/remove arrays are a no-op and do not revert.
    function test_IWI_WI_8_IWI_WI_10_emptyArrays_noopAndNoRevert() public {
        // Setup: capture baseline whitelist state.
        bool beforeState =
            whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA);
        address[] memory empty;

        // Call: invoke mutation endpoint with both arrays empty.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(ContractType.Organization, empty, empty);

        // Verify: state remains unchanged and call does not revert.
        bool afterState =
            whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA);
        assertEq(afterState, beforeState, "empty mutation should be a no-op");
    }

    /// @dev Verifies duplicate addresses in `toWhitelist` are idempotent at state level.
    function test_IWI_WI_8_duplicateAddressesInToWhitelist_idempotent() public {
        // Setup: create array with duplicate addresses.
        address[] memory duplicates = _pair(organizationImplementationA, organizationImplementationA);

        // Call: owner calls whitelistImplementations with duplicate addresses.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(ContractType.Organization, duplicates, new address[](0));

        // Verify: implementation is whitelisted (idempotent result).
        assertTrue(
            whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA),
            "orgA should be whitelisted despite duplicate in input"
        );
    }

    /// @dev Verifies duplicate addresses in `toUnwhitelist` are idempotent at state level.
    function test_IWI_WI_9_duplicateAddressesInToUnwhitelist_idempotent() public {
        // Setup: whitelist an entry, then create duplicate removal array.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Organization, _single(organizationImplementationA), new address[](0)
        );

        address[] memory duplicates = _pair(organizationImplementationA, organizationImplementationA);

        // Call: owner removes with duplicate addresses.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(ContractType.Organization, new address[](0), duplicates);

        // Verify: implementation is unwhitelisted (idempotent result).
        assertFalse(
            whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA),
            "orgA should be unwhitelisted despite duplicate in removal input"
        );
    }

    /// @dev Verifies pending owner (before `acceptOwnership`) cannot call whitelist mutation.
    function test_IWI_WI_9_IWI_WI_2_pendingOwnerBeforeAccept_cannotMutateWhitelist() public {
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
    function test_IWI_WI_10_IWI_WI_3_afterAccept_newOwnerCanMutate_oldOwnerCannot() public {
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
        assertTrue(
            whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA),
            "orgA should be whitelisted by new owner"
        );

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, OWNER));
        vm.prank(OWNER);
        // Call: old owner attempts post-transfer mutation.
        whitelistProxy.whitelistImplementations(
            ContractType.Organization, _single(organizationImplementationB), new address[](0)
        );
    }

    // forgefmt: disable-next-item
    /// @dev Verifies `isImplementationWhitelisted` is true only for matching contract type entries.
    function test_IWI_VIW_1_IWI_IIW_1_IWI_IIW_2_IWI_IIW_3_isImplementationWhitelisted_typeScopedTruthTable()
        public
    {
        // Setup: whitelist one Organization and one Account target independently.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Organization, _single(organizationImplementationA), new address[](0)
        );
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(ContractType.Account, _single(accountImplementationA), new address[](0));

        // Call + Verify: each address is true only under its matching contract type.
        assertTrue(
            whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA),
            "orgA should be whitelisted under Organization"
        );
        assertFalse(
            whitelistProxy.isImplementationWhitelisted(ContractType.Account, organizationImplementationA),
            "orgA should not be whitelisted under Account"
        );
        assertTrue(
            whitelistProxy.isImplementationWhitelisted(ContractType.Account, accountImplementationA),
            "accountA should be whitelisted under Account"
        );
        assertFalse(
            whitelistProxy.isImplementationWhitelisted(ContractType.Organization, accountImplementationA),
            "accountA should not be whitelisted under Organization"
        );
    }

    /// @dev Verifies `isImplementationWhitelisted` returns false for all addresses before initialization.
    function test_IWI_IIW_4_isImplementationWhitelisted_falseBeforeInit() public {
        // Setup: deploy uninitialized proxy.
        ImplementationWhitelistHarness proxy = _deployUninitializedProxy();

        // Verify: all addresses report false before initialization.
        assertFalse(
            proxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA),
            "orgA should be false before init"
        );
        assertFalse(
            proxy.isImplementationWhitelisted(ContractType.Account, accountImplementationA),
            "accountA should be false before init"
        );
        assertFalse(
            proxy.isImplementationWhitelisted(ContractType.Organization, address(0)),
            "zero address should be false before init"
        );
    }

    /// @dev Verifies `isImplementationWhitelisted` returns false for addresses added then removed from whitelist.
    function test_IWI_IIW_5_isImplementationWhitelisted_falseAfterAddThenRemove() public {
        // Setup: add implementation to whitelist.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Organization, _single(organizationImplementationA), new address[](0)
        );
        assertTrue(
            whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA),
            "orgA should be whitelisted after addition"
        );

        // Call: remove implementation from whitelist.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Organization, new address[](0), _single(organizationImplementationA)
        );

        // Verify: returns false for removed implementation.
        assertFalse(
            whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA),
            "orgA should be false after add-then-remove"
        );
    }

    // forgefmt: disable-next-item
    /// @dev Verifies `validateIsImplementationWhitelistedOrRevert` reverts for non-whitelisted targets.
    function test_IWI_VIW_2_IWI_VIIWOR_2_IWI_VIIWOR_5_validateWhitelisted_revertsWhenNotWhitelisted() public {
        // Setup: choose target with no whitelist entry.
        address target = organizationImplementationA;

        // Verify: validation call reverts with canonical error for non-whitelisted implementation.
        vm.expectRevert(abi.encodeWithSelector(IImplementationWhitelist.ImplementationNotWhitelisted.selector, target));
        // Call: validate un-whitelisted target.
        whitelistProxy.validateIsImplementationWhitelistedOrRevert(ContractType.Organization, target);
    }

    /// @dev Verifies `validateIsImplementationWhitelistedOrRevert` succeeds for whitelisted targets.
    function test_IWI_VIW_3_IWI_VIIWOR_1_validateWhitelisted_succeedsForWhitelistedTarget() public {
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
        assertTrue(true, "validation should succeed for whitelisted target");
    }

    /// @dev Verifies validation reverts when implementation is whitelisted only under the other contract type.
    function test_IWI_VIW_4_IWI_VIIWOR_4_validateWhitelisted_otherTypeOnly_reverts() public {
        // Setup: whitelist target under Account type only.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(ContractType.Account, _single(accountImplementationA), new address[](0));

        // Verify: Organization-type validation still reverts for Account-only entry.
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector, accountImplementationA
            )
        );
        // Call: validate target under wrong contract type namespace.
        whitelistProxy.validateIsImplementationWhitelistedOrRevert(ContractType.Organization, accountImplementationA);
    }

    // forgefmt: disable-next-item
    /// @dev Verifies `validateIsImplementationWhitelistedOrRevert` reverts for address added then removed from
    // whitelist.
    function test_IWI_VIIWOR_3_validateWhitelisted_revertsForAddedThenRemovedAddress() public {
        // Setup: add then remove implementation from whitelist.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Organization, _single(organizationImplementationA), new address[](0)
        );
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Organization, new address[](0), _single(organizationImplementationA)
        );

        // Verify: validation reverts for removed implementation.
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector, organizationImplementationA
            )
        );
        // Call: validate removed implementation.
        whitelistProxy.validateIsImplementationWhitelistedOrRevert(
            ContractType.Organization, organizationImplementationA
        );
    }

    /// @dev Verifies owner can perform UUPS upgrade through proxy `upgradeToAndCall`.
    function test_IWI_UUPS_1_IWI_AU_1_ownerCanUpgradeProxyViaUUPS() public {
        // Setup: initialized proxy with owner from suite setup.

        // Call: owner upgrades proxy to V2 implementation.
        vm.prank(OWNER);
        IUUPSWhitelistEntrypoints(address(whitelistProxy)).upgradeToAndCall(address(implementationV2), bytes(""));

        // Verify: proxy implementation slot points to V2.
        assertEq(
            _readProxyImplementation(address(whitelistProxy)), address(implementationV2), "upgrade target mismatch"
        );
    }

    /// @dev Verifies non-owner cannot perform UUPS upgrade.
    function test_IWI_UUPS_2_IWI_AU_2_nonOwnerCannotUpgradeProxy() public {
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
    function test_IWI_UUPS_5_IWI_AU_5_upgradeWithMigrationCalldata_executesMigration() public {
        // Setup: encode migration call on V2 implementation.
        bytes memory migrationData = abi.encodeCall(ImplementationWhitelistV2Harness.setMigrationMarker, (505));

        // Call: owner upgrades proxy with migration calldata.
        vm.prank(OWNER);
        IUUPSWhitelistEntrypoints(address(whitelistProxy)).upgradeToAndCall(address(implementationV2), migrationData);

        // Verify: migration logic executed in proxy storage context.
        assertEq(ImplementationWhitelistV2Harness(address(whitelistProxy)).getMigrationMarker(), 505, "marker mismatch");
        assertEq(_readProxyImplementation(address(whitelistProxy)), address(implementationV2));
    }

    // forgefmt: disable-next-item
    /// @dev Verifies whitelist storage persists across multiple sequential UUPS upgrades for both contract types.
    function test_IWI_UUPS_6_IWI_AU_3_whitelistStoragePersistsAcrossMultipleSequentialUpgrades() public {
        // Setup: seed whitelist state before upgrade.
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Organization, _single(organizationImplementationA), new address[](0)
        );
        vm.prank(OWNER);
        whitelistProxy.whitelistImplementations(ContractType.Account, _single(accountImplementationA), new address[](0));

        // Call: upgrade 1 — implementation -> V2.
        vm.prank(OWNER);
        IUUPSWhitelistEntrypoints(address(whitelistProxy)).upgradeToAndCall(address(implementationV2), bytes(""));

        // Verify: proxy now delegates to the V2 implementation.
        assertEq(_readProxyImplementation(address(whitelistProxy)), address(implementationV2));

        // Verify: whitelist state survives first upgrade.
        assertTrue(
            whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA),
            "orgA should persist after upgrade 1"
        );
        assertTrue(
            whitelistProxy.isImplementationWhitelisted(ContractType.Account, accountImplementationA),
            "accountA should persist after upgrade 1"
        );
        assertEq(
            _readProxyImplementation(address(whitelistProxy)),
            address(implementationV2),
            "impl slot should be V2 after upgrade 1"
        );

        // Call: upgrade 2 — V2 -> back to original implementation.
        vm.prank(OWNER);
        IUUPSWhitelistEntrypoints(address(whitelistProxy)).upgradeToAndCall(address(implementation), bytes(""));

        // Verify: whitelist state survives second upgrade.
        assertTrue(
            whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA),
            "orgA should persist after upgrade 2"
        );
        assertTrue(
            whitelistProxy.isImplementationWhitelisted(ContractType.Account, accountImplementationA),
            "accountA should persist after upgrade 2"
        );
        assertEq(
            _readProxyImplementation(address(whitelistProxy)),
            address(implementation),
            "impl slot should be original after upgrade 2"
        );

        // Call: upgrade 3 — implementation -> V2 again.
        ImplementationWhitelistV2Harness implementationV2b = new ImplementationWhitelistV2Harness();
        vm.prank(OWNER);
        IUUPSWhitelistEntrypoints(address(whitelistProxy)).upgradeToAndCall(address(implementationV2b), bytes(""));

        // Verify: whitelist state survives third upgrade.
        assertTrue(
            whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA),
            "orgA should persist after upgrade 3"
        );
        assertTrue(
            whitelistProxy.isImplementationWhitelisted(ContractType.Account, accountImplementationA),
            "accountA should persist after upgrade 3"
        );
        assertEq(
            _readProxyImplementation(address(whitelistProxy)),
            address(implementationV2b),
            "impl slot should be V2b after upgrade 3"
        );
    }

    /// @dev Verifies upgrade to non-UUPS or incompatible implementation reverts.
    function test_IWI_UUPS_7_upgradeToNonUUPSOrIncompatible_reverts() public {
        // Setup: initialized proxy.

        // Verify: non-UUPS target is rejected.
        vm.expectRevert(
            abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidImplementation.selector, address(nonUupsImplementation))
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

        // Verify: `proxiableUUID` on the implementation directly returns the correct ERC-1967 slot.
        bytes32 uuid = IUUPSWhitelistEntrypoints(address(implementation)).proxiableUUID();
        assertEq(uuid, ERC1967Utils.IMPLEMENTATION_SLOT);
    }

    /// @dev Verifies owner-triggered `upgradeToAndCall` rejects zero and no-code implementation targets.
    function test_IWI_UUPS_10_IWI_AU_6_ownerCannotUpgradeToZeroOrNoCode_reverts() public {
        // Setup: initialized proxy owned by OWNER.

        // Verify: zero-address target is rejected.
        // Note: proxiableUUID() STATICCALL returns empty data; the ABI decoder fails decoding it as bytes32.
        // Per Solidity docs, ABI decode failures inside `try` are NOT caught by `catch`, producing revert(0,0).
        vm.expectRevert(bytes(""));
        vm.prank(OWNER);
        // Call: attempt UUPS upgrade to zero address.
        IUUPSWhitelistEntrypoints(address(whitelistProxy)).upgradeToAndCall(address(0), bytes(""));

        // Verify: no-code target is rejected.
        // Note: same ABI decode failure path as address(0) — empty returndata cannot decode as bytes32.
        vm.expectRevert(bytes(""));
        vm.prank(OWNER);
        // Call: attempt UUPS upgrade to no-code address.
        IUUPSWhitelistEntrypoints(address(whitelistProxy)).upgradeToAndCall(noCodeAddress, bytes(""));
    }

    /// @dev Verifies UUPS upgrade preserves ownership state.
    function test_IWI_AU_4_upgradePreservesOwnershipState() public {
        // Setup: transfer ownership to NEW_OWNER before upgrade.
        vm.prank(OWNER);
        whitelistProxy.transferOwnership(NEW_OWNER);
        vm.prank(NEW_OWNER);
        whitelistProxy.acceptOwnership();

        // Call: new owner upgrades proxy to V2.
        vm.prank(NEW_OWNER);
        IUUPSWhitelistEntrypoints(address(whitelistProxy)).upgradeToAndCall(address(implementationV2), bytes(""));

        // Verify: ownership state preserved after upgrade.
        assertEq(whitelistProxy.owner(), NEW_OWNER, "owner should be preserved after upgrade");
    }
}
