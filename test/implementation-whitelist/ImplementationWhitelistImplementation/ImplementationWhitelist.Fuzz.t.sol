// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {OwnableUpgradeable} from "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {IImplementationWhitelist} from "interfaces/IImplementationWhitelist.sol";
import {OrganizationProxy} from "organization/OrganizationProxy.sol";
import {
    ImplementationWhitelistHarness
} from "test/implementation-whitelist/ImplementationWhitelistImplementation/ImplementationWhitelistHarnesses.sol";
import {
    ImplementationWhitelistSuiteBase
} from "test/implementation-whitelist/ImplementationWhitelistImplementation/ImplementationWhitelistSuiteBase.sol";
import {ContractType} from "types/CommonTypes.sol";

/// @dev Fuzz tests for implementation whitelist controls.
contract ImplementationWhitelistFuzzTest is ImplementationWhitelistSuiteBase {
    /// @dev Verifies internal whitelist helper wrappers preserve model parity for fuzzed add/remove sequences.
    /// @param addresses The implementation addresses mutated across the sequence.
    /// @param shouldAdd Whether each sequence step adds or removes its corresponding address.
    /// @param useAccountType Whether to mutate the Account or Organization whitelist bucket.
    function testFuzz_internalWhitelistHelpers_matchReferenceModel(
        address[5] calldata addresses,
        bool[5] calldata shouldAdd,
        bool useAccountType
    ) public {
        // Setup: choose the fuzzed whitelist bucket and its untouched counterpart.
        ContractType contractType = useAccountType ? ContractType.Account : ContractType.Organization;
        ContractType otherType = useAccountType ? ContractType.Organization : ContractType.Account;

        // Call: drive the exposed internal add/remove helpers through a fuzzed mutation sequence.
        for (uint256 i = 0; i < 5; i++) {
            if (shouldAdd[i]) {
                whitelistProxy.exposeAddToWhitelist(contractType, _single(addresses[i]));
            } else {
                whitelistProxy.exposeRemoveFromWhitelist(contractType, _single(addresses[i]));
            }
        }

        // Verify: the mutated bucket follows the last-operation model and the untouched bucket stays unchanged.
        for (uint256 i = 0; i < 5; i++) {
            bool expectedWhitelisted = false;
            for (uint256 j = 0; j < 5; j++) {
                if (addresses[j] == addresses[i]) {
                    expectedWhitelisted = shouldAdd[j];
                }
            }
            assertEq(
                whitelistProxy.isImplementationWhitelisted(contractType, addresses[i]),
                expectedWhitelisted,
                "onchain state must match last operation for address"
            );
            assertFalse(
                whitelistProxy.isImplementationWhitelisted(otherType, addresses[i]),
                "other whitelist bucket must remain unchanged"
            );
        }
    }

    /// @dev Verifies Organization and Account whitelist buckets stay independent under fuzzed mixed operations.
    /// @param addr The shared implementation address mutated under both buckets.
    /// @param addToOrg Whether the Organization bucket receives the address.
    /// @param addToAccount Whether the Account bucket receives the address.
    function testFuzz_fuzz_mixedTypeOperations_mappingsRemainIndependent(address addr, bool addToOrg, bool addToAccount)
        public
    {
        // Setup: start from a clean initialized proxy with both buckets unset for the fuzzed address.

        // Call: apply owner-authorized mutations to each bucket independently.
        if (addToOrg) {
            vm.prank(OWNER);
            whitelistProxy.whitelistImplementations(ContractType.Organization, _single(addr), new address[](0));
        }
        if (addToAccount) {
            vm.prank(OWNER);
            whitelistProxy.whitelistImplementations(ContractType.Account, _single(addr), new address[](0));
        }

        // Verify: each type reflects only its own operations.
        assertEq(
            whitelistProxy.isImplementationWhitelisted(ContractType.Organization, addr),
            addToOrg,
            "org whitelist must reflect only org operations"
        );
        assertEq(
            whitelistProxy.isImplementationWhitelisted(ContractType.Account, addr),
            addToAccount,
            "account whitelist must reflect only account operations"
        );
    }

    /// @dev Verifies whitelist validation stays consistent with the stored mapping for fuzzed tuples.
    /// @param randomAddr The fuzzed implementation address being checked.
    /// @param useAccountType Whether to use the Account or Organization whitelist bucket.
    /// @param shouldWhitelist Whether to seed the fuzzed address into the chosen whitelist bucket.
    function testFuzz_validateHelper_matchesWhitelistMapping(
        address randomAddr,
        bool useAccountType,
        bool shouldWhitelist
    ) public {
        // Setup: choose the fuzzed contract-type bucket and optionally seed the candidate address into it.
        ContractType contractType = useAccountType ? ContractType.Account : ContractType.Organization;
        if (shouldWhitelist) {
            vm.prank(OWNER);
            whitelistProxy.whitelistImplementations(contractType, _single(randomAddr), new address[](0));
        }

        // Call: read the stored mapping before exercising the validation helper.
        bool isWhitelisted = whitelistProxy.isImplementationWhitelisted(contractType, randomAddr);

        // Verify: whitelisted entries pass validation and unwhitelisted entries always revert with the exact error.
        assertEq(isWhitelisted, shouldWhitelist, "mapping state must match the seeded fuzz branch");
        if (isWhitelisted) {
            whitelistProxy.validateIsImplementationWhitelistedOrRevert(contractType, randomAddr);
            return;
        }

        vm.expectRevert(
            abi.encodeWithSelector(IImplementationWhitelist.ImplementationNotWhitelisted.selector, randomAddr)
        );
        whitelistProxy.validateIsImplementationWhitelistedOrRevert(contractType, randomAddr);
    }

    /// @dev Verifies whitelist initialization is one-time and preserves the first owner and seed sets after re-entry.
    /// @param initialOwner The owner configured during the first successful initialization.
    /// @param orgSeeds The Organization implementation seeds applied during the first initialization.
    /// @param accountSeeds The Account implementation seeds applied during the first initialization.
    /// @param secondOwner The owner proposed during the rejected second initialization.
    /// @param secondOrgOnly A second Organization implementation unique to the rejected re-entry attempt.
    /// @param secondAccountOnly A second Account implementation unique to the rejected re-entry attempt.
    function testFuzz_initialize_isOneTimeAndPreservesFirstConfiguration(
        address initialOwner,
        address[3] calldata orgSeeds,
        address[3] calldata accountSeeds,
        address secondOwner,
        address secondOrgOnly,
        address secondAccountOnly
    ) public {
        vm.assume(initialOwner != address(0));
        for (uint256 i = 0; i < orgSeeds.length; ++i) {
            vm.assume(secondOrgOnly != orgSeeds[i]);
        }
        for (uint256 i = 0; i < accountSeeds.length; ++i) {
            vm.assume(secondAccountOnly != accountSeeds[i]);
        }

        address[] memory orgSeedArray = new address[](orgSeeds.length);
        address[] memory accountSeedArray = new address[](accountSeeds.length);
        for (uint256 i = 0; i < orgSeeds.length; ++i) {
            orgSeedArray[i] = orgSeeds[i];
        }
        for (uint256 i = 0; i < accountSeeds.length; ++i) {
            accountSeedArray[i] = accountSeeds[i];
        }

        // Setup: deploy an uninitialized proxy instance and prepare first/second initialization payloads.
        ImplementationWhitelistHarness freshProxy = _deployUninitializedProxy();

        // Call: initialize once successfully, then attempt a second initialization with altered owner and seeds.
        freshProxy.initialize(initialOwner, orgSeedArray, accountSeedArray);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        freshProxy.initialize(secondOwner, _single(secondOrgOnly), _single(secondAccountOnly));

        // Verify: initialization sticks to the first owner and seed sets and ignores the rejected second payload.
        assertTrue(freshProxy.isInitialized(), "proxy should report initialized after the first call");
        assertEq(freshProxy.owner(), initialOwner, "owner should remain the first initialized owner");
        for (uint256 i = 0; i < orgSeeds.length; ++i) {
            assertTrue(
                freshProxy.isImplementationWhitelisted(ContractType.Organization, orgSeeds[i]),
                "first organization seed should remain whitelisted"
            );
        }
        for (uint256 i = 0; i < accountSeeds.length; ++i) {
            assertTrue(
                freshProxy.isImplementationWhitelisted(ContractType.Account, accountSeeds[i]),
                "first account seed should remain whitelisted"
            );
        }
        assertFalse(
            freshProxy.isImplementationWhitelisted(ContractType.Organization, secondOrgOnly),
            "second initialization must not apply organization seeds"
        );
        assertFalse(
            freshProxy.isImplementationWhitelisted(ContractType.Account, secondAccountOnly),
            "second initialization must not apply account seeds"
        );
    }

    /// @dev Verifies only the owner can mutate whitelist mappings for fuzzed callers and mutation directions.
    /// @param caller The caller attempting the whitelist mutation.
    /// @param useAccountType Whether to mutate the Account or Organization whitelist bucket.
    /// @param addOperation Whether the mutation is an add or a remove operation.
    /// @param implementationAddress The implementation address targeted by the mutation.
    function testFuzz_whitelistImplementations_onlyOwnerCanMutate(
        address caller,
        bool useAccountType,
        bool addOperation,
        address implementationAddress
    ) public {
        // Setup: choose the fuzzed whitelist bucket and seed the address first when testing the remove path.
        ContractType contractType = useAccountType ? ContractType.Account : ContractType.Organization;
        if (!addOperation) {
            vm.prank(OWNER);
            whitelistProxy.whitelistImplementations(contractType, _single(implementationAddress), new address[](0));
        }

        address[] memory toWhitelist = addOperation ? _single(implementationAddress) : new address[](0);
        address[] memory toUnwhitelist = addOperation ? new address[](0) : _single(implementationAddress);

        // Call: execute the fuzzed mutation as either the owner or a non-owner.
        if (caller == OWNER) {
            vm.prank(caller);
            whitelistProxy.whitelistImplementations(contractType, toWhitelist, toUnwhitelist);

            // Verify: owner calls apply the requested mutation exactly.
            assertEq(
                whitelistProxy.isImplementationWhitelisted(contractType, implementationAddress),
                addOperation,
                "owner mutation should set the whitelist bit to the requested final state"
            );
            return;
        }

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, caller));
        vm.prank(caller);
        whitelistProxy.whitelistImplementations(contractType, toWhitelist, toUnwhitelist);

        // Verify: non-owner callers cannot change add/remove outcomes.
        assertEq(
            whitelistProxy.isImplementationWhitelisted(contractType, implementationAddress),
            !addOperation,
            "non-owner mutation must leave whitelist state unchanged"
        );
    }

    // forgefmt: disable-next-item
    /// @dev Verifies fuzz `(salt, implementation, whitelist)` tuples produce deterministic and
    // sensitivity-preserving outputs from `computeOrganizationAddress` via a locally deployed factory.
    function test_fuzz_computeOrganizationAddress_deterministicAndSensitivityPreserving(
        bytes32 saltA,
        bytes32 saltB,
        address implA,
        address implB,
        address whitelistA,
        address whitelistB
    ) public {
        // Setup: deploy a minimal factory for address computation (view-only, no deployment needed).
        OrganizationFactoryForFuzz localFactory = new OrganizationFactoryForFuzz();

        // Verify: deterministic — same inputs produce same output.
        address computedA1 = localFactory.computeAddress(saltA, implA, whitelistA);
        address computedA2 = localFactory.computeAddress(saltA, implA, whitelistA);
        assertEq(computedA1, computedA2, "same inputs must produce same output");

        // Verify: sensitivity — different salt changes output.
        vm.assume(saltA != saltB);
        address differentSalt = localFactory.computeAddress(saltB, implA, whitelistA);
        assertTrue(computedA1 != differentSalt, "different salt should change computed address");

        // Verify: sensitivity — different implementation changes output.
        vm.assume(implA != implB);
        address differentImpl = localFactory.computeAddress(saltA, implB, whitelistA);
        assertTrue(computedA1 != differentImpl, "different implementation should change computed address");

        // Verify: sensitivity — different whitelist changes output.
        vm.assume(whitelistA != whitelistB);
        address differentWhitelist = localFactory.computeAddress(saltA, implA, whitelistB);
        assertTrue(computedA1 != differentWhitelist, "different whitelist should change computed address");
    }

    /// @dev : Fuzz proxy initialization inputs — malformed init data never leaves partially initialized
    /// proxy.
    function test_fuzz_malformedInitData_neverLeavesPartiallyInitializedProxy(bytes calldata randomInitData) public {
        // Setup: filter out valid initialize selector to ensure data is malformed.
        vm.assume(randomInitData.length > 0);
        // casting to 'bytes4' is safe because the short-circuit guard ensures length >= 4 before the cast
        // forge-lint: disable-next-line(unsafe-typecast)
        vm.assume(randomInitData.length < 4 || bytes4(randomInitData) != implementation.initialize.selector);

        // Call: attempt proxy deployment with malformed init data.
        // ERC1967Proxy delegatecalls initData to implementation; malformed data should revert.
        vm.expectRevert();
        new ERC1967Proxy(address(implementation), randomInitData);
    }
}

/**
 * @dev Lightweight factory harness for fuzz-testing `computeOrganizationAddress` determinism and sensitivity
 *      without requiring full org deployment infrastructure.
 */
contract OrganizationFactoryForFuzz {
    /**
     * @dev Computes a deterministic CREATE2 address for a hypothetical OrganizationProxy deployment.
     * @param salt CREATE2 salt.
     * @param implementationAddress Organization implementation address encoded into proxy bytecode.
     * @param whitelistAddress Whitelist address encoded into proxy bytecode.
     * @return computed Deterministic CREATE2 address.
     */
    function computeAddress(bytes32 salt, address implementationAddress, address whitelistAddress)
        external
        view
        returns (address computed)
    {
        // Mirrors OrganizationFactory._getOrganizationProxyBytecode + computeOrganizationAddress logic.
        bytes memory bytecode =
            abi.encodePacked(type(OrganizationProxy).creationCode, abi.encode(implementationAddress, whitelistAddress));
        bytes32 initCodeHash = keccak256(bytecode);
        computed =
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash)))));
    }
}
