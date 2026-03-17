// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test} from "forge-std/Test.sol";

import {
    ImplementationWhitelistHarness,
    ImplementationWhitelistV2Harness
} from "test/implementation-whitelist/ImplementationWhitelistImplementation/ImplementationWhitelistHarnesses.sol";
import {ContractType} from "types/CommonTypes.sol";

/// @dev Dummy contract deployed so test addresses have runtime code.
contract InvariantCodeMock {}

interface IUUPSEntrypoints {
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;
}

/**
 * @dev Invariant handler that exercises whitelist mutations and tracks a reference model.
 *      The fuzzer calls handler actions; invariant assertions compare onchain state to the reference model.
 */
contract ImplementationWhitelistInvariantHandler is Test {
    ImplementationWhitelistHarness public whitelist;
    ImplementationWhitelistV2Harness public implementationV2;
    address public owner;

    /// @dev Reference model mirrors: tracks expected whitelist state per (type, address).
    mapping(ContractType => mapping(address => bool)) public referenceWhitelisted;

    /// @dev Tracked addresses for invariant iteration.
    address[] public trackedAddresses;
    uint256 public trackedCount;

    /// @dev Tracks whether any non-owner mutation succeeded (should never happen).
    bool public nonOwnerMutationSucceeded;

    /// @dev Tracks whether initialization permanence was violated.
    bool public initializationBecameFalse;

    /// @dev Tracks whitelist UUPS upgrade count and whether state survived.
    uint256 public upgradeCount;
    bool public upgradeCorruptedState;

    /**
     * @dev Deploys a real whitelist proxy and seeds it with one tracked address per type.
     */
    constructor() {
        owner = address(0xA11CE);

        ImplementationWhitelistHarness implementation = new ImplementationWhitelistHarness();
        implementationV2 = new ImplementationWhitelistV2Harness();

        bytes memory initData =
            abi.encodeWithSelector(implementation.initialize.selector, owner, new address[](0), new address[](0));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        whitelist = ImplementationWhitelistHarness(payable(address(proxy)));

        // Seed initial tracked addresses.
        address seedOrg = address(new InvariantCodeMock());
        address seedAccount = address(new InvariantCodeMock());
        _track(seedOrg);
        _track(seedAccount);

        // Whitelist initial seeds.
        vm.prank(owner);
        whitelist.whitelistImplementations(ContractType.Organization, _single(seedOrg), new address[](0));
        referenceWhitelisted[ContractType.Organization][seedOrg] = true;

        vm.prank(owner);
        whitelist.whitelistImplementations(ContractType.Account, _single(seedAccount), new address[](0));
        referenceWhitelisted[ContractType.Account][seedAccount] = true;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Fuzzed Actions
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @dev Owner adds an implementation to Organization whitelist.
     * @param addrSeed Seed used to select a tracked address.
     */
    function ownerAddOrganization(uint256 addrSeed) external {
        address target = _getOrCreateTrackedAddress(addrSeed);
        vm.prank(owner);
        whitelist.whitelistImplementations(ContractType.Organization, _single(target), new address[](0));
        referenceWhitelisted[ContractType.Organization][target] = true;
    }

    /**
     * @dev Owner removes an implementation from Organization whitelist.
     * @param addrSeed Seed used to select a tracked address.
     */
    function ownerRemoveOrganization(uint256 addrSeed) external {
        address target = _getOrCreateTrackedAddress(addrSeed);
        vm.prank(owner);
        whitelist.whitelistImplementations(ContractType.Organization, new address[](0), _single(target));
        referenceWhitelisted[ContractType.Organization][target] = false;
    }

    /**
     * @dev Owner adds an implementation to Account whitelist.
     * @param addrSeed Seed used to select a tracked address.
     */
    function ownerAddAccount(uint256 addrSeed) external {
        address target = _getOrCreateTrackedAddress(addrSeed);
        vm.prank(owner);
        whitelist.whitelistImplementations(ContractType.Account, _single(target), new address[](0));
        referenceWhitelisted[ContractType.Account][target] = true;
    }

    /**
     * @dev Owner removes an implementation from Account whitelist.
     * @param addrSeed Seed used to select a tracked address.
     */
    function ownerRemoveAccount(uint256 addrSeed) external {
        address target = _getOrCreateTrackedAddress(addrSeed);
        vm.prank(owner);
        whitelist.whitelistImplementations(ContractType.Account, new address[](0), _single(target));
        referenceWhitelisted[ContractType.Account][target] = false;
    }

    /**
     * @dev Non-owner attempts to mutate whitelist entries (should always fail).
     * @param addrSeed Seed used to select a tracked address.
     */
    function nonOwnerAttemptMutation(uint256 addrSeed) external {
        address target = _getOrCreateTrackedAddress(addrSeed);
        address nonOwner = address(0xB0B);

        // Attempt Organization add from non-owner.
        vm.prank(nonOwner);
        (bool success,) = address(whitelist)
            .call(
                abi.encodeCall(
                    whitelist.whitelistImplementations, (ContractType.Organization, _single(target), new address[](0))
                )
            );
        if (success) nonOwnerMutationSucceeded = true;
    }

    /**
     * @dev Checks initialization state hasn't reverted to false.
     */
    function checkInitializationPermanence() external {
        if (!whitelist.isInitialized()) {
            initializationBecameFalse = true;
        }
    }

    /**
     * @dev Owner upgrades the whitelist proxy and verifies state persistence.
     */
    function ownerUpgradeWhitelist() external {
        // Snapshot one whitelisted entry state before upgrade.
        address snapshotAddr = trackedAddresses[0];
        bool orgBefore = whitelist.isImplementationWhitelisted(ContractType.Organization, snapshotAddr);
        bool accountBefore = whitelist.isImplementationWhitelisted(ContractType.Account, snapshotAddr);

        vm.prank(owner);
        IUUPSEntrypoints(address(whitelist)).upgradeToAndCall(address(implementationV2), bytes(""));
        upgradeCount++;

        // Verify state survived.
        bool orgAfter = whitelist.isImplementationWhitelisted(ContractType.Organization, snapshotAddr);
        bool accountAfter = whitelist.isImplementationWhitelisted(ContractType.Account, snapshotAddr);
        if (orgBefore != orgAfter || accountBefore != accountAfter) {
            upgradeCorruptedState = true;
        }

        // Upgrade back for next cycle.
        ImplementationWhitelistHarness freshV2 = new ImplementationWhitelistHarness();
        vm.prank(owner);
        IUUPSEntrypoints(address(whitelist)).upgradeToAndCall(address(freshV2), bytes(""));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Internal Helpers
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @dev Selects an existing tracked address by index or creates a new one.
     * @param seed Seed value used to select or create an address.
     * @return target The selected or newly created tracked address.
     */
    function _getOrCreateTrackedAddress(uint256 seed) internal returns (address target) {
        if (trackedCount == 0 || seed % 3 == 0) {
            target = address(new InvariantCodeMock());
            _track(target);
        } else {
            target = trackedAddresses[seed % trackedCount];
        }
    }

    /**
     * @dev Adds an address to the tracked set if not already present.
     * @param addr Address to track.
     */
    function _track(address addr) internal {
        trackedAddresses.push(addr);
        trackedCount++;
    }

    /**
     * @dev Builds a single-entry address array.
     * @param value Address to wrap.
     * @return values One-element array.
     */
    function _single(address value) internal pure returns (address[] memory values) {
        values = new address[](1);
        values[0] = value;
    }
}

/// @dev Invariant tests for implementation whitelist controls.
contract ImplementationWhitelistInvariantsTest is Test {
    ImplementationWhitelistInvariantHandler internal handler;

    /// @dev Deploys the handler, seeds actions, and configures it as the fuzz target.
    function setUp() public {
        handler = new ImplementationWhitelistInvariantHandler();

        // Seed baseline handler actions so each invariant has data.
        handler.ownerAddOrganization(0);
        handler.ownerAddAccount(1);
        handler.ownerRemoveOrganization(2);
        handler.nonOwnerAttemptMutation(3);
        handler.checkInitializationPermanence();

        targetContract(address(handler));
    }

    /// @dev : Only current whitelist owner can mutate whitelist entries.
    function invariant_ownerExclusivity_nonOwnerMutationsAlwaysFail() public view {
        assertFalse(handler.nonOwnerMutationSucceeded(), "non-owner mutation should never succeed");
    }

    // forgefmt: disable-next-item
    /// @dev + : Onchain whitelist state must match the reference model for every tracked address
    // under both contract types, which also proves type independence (adding to one type never affects the other).
    function invariant_3_whitelistStateMatchesReferenceModel() public view {
        ImplementationWhitelistHarness whitelist = handler.whitelist();
        uint256 count = handler.trackedCount();

        for (uint256 i = 0; i < count; ++i) {
            address addr = handler.trackedAddresses(i);

            bool orgOnchain = whitelist.isImplementationWhitelisted(ContractType.Organization, addr);
            bool orgReference = handler.referenceWhitelisted(ContractType.Organization, addr);
            assertEq(orgOnchain, orgReference, "org whitelist state must match reference model");

            bool accountOnchain = whitelist.isImplementationWhitelisted(ContractType.Account, addr);
            bool accountReference = handler.referenceWhitelisted(ContractType.Account, addr);
            assertEq(accountOnchain, accountReference, "account whitelist state must match reference model");
        }
    }

    /// @dev : `isUpgradeAuthorized` is false outside authorized org-upgrade execution window.
    ///      For the whitelist contract itself, the UUPS `_authorizeUpgrade` is owner-gated, not flag-based.
    ///      This invariant verifies the whitelist proxy always has a valid owner set (authorization state is sound).
    function invariant_upgradeAuthFlagSafety_whitelistOwnerAlwaysSet() public view {
        address currentOwner = handler.whitelist().owner();
        assertTrue(currentOwner != address(0), "whitelist owner must always be set (authorization state sound)");
        assertEq(currentOwner, handler.owner(), "whitelist owner must match expected owner");
    }

    /// @dev : Whitelist data is preserved after whitelist UUPS upgrade.
    function invariant_whitelistStateContinuity_preservedAcrossUpgrades() public view {
        assertFalse(handler.upgradeCorruptedState(), "whitelist state must survive UUPS upgrades");
    }

    /// @dev : Initialization permanence — once initialized, cannot revert to false.
    function invariant_initializationPermanence_onceInitializedCannotRevert() public view {
        assertFalse(handler.initializationBecameFalse(), "initialization must never revert to false");
        assertTrue(handler.whitelist().isInitialized(), "whitelist must remain initialized");
    }
}
