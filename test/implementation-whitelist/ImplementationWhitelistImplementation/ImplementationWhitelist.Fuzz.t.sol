// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ImplementationWhitelistHarness}
    from "test/implementation-whitelist/ImplementationWhitelistImplementation/ImplementationWhitelistHarnesses.sol";
import {ImplementationWhitelistSuiteBase}
    from "test/implementation-whitelist/ImplementationWhitelistImplementation/ImplementationWhitelistSuiteBase.sol";
import {ContractType} from "types/CommonTypes.sol";

/// @dev Fuzz tests for implementation whitelist controls.
contract ImplementationWhitelistFuzzTest is ImplementationWhitelistSuiteBase {
    /// @dev IWC-FUZZ-2: Fuzz add/remove sequences per ContractType — onchain state matches reference model.
    function test_IWC_FUZZ_2_fuzz_addRemoveSequencesMatchReferenceModel(
        address[5] calldata addresses,
        bool[5] calldata shouldAdd
    ) public {
        // Setup + Call: execute a fuzzed sequence of add/remove operations for Organization type.
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(OWNER);
            if (shouldAdd[i]) {
                whitelistProxy.whitelistImplementations(
                    ContractType.Organization, _single(addresses[i]), new address[](0)
                );
            } else {
                whitelistProxy.whitelistImplementations(
                    ContractType.Organization, new address[](0), _single(addresses[i])
                );
            }
        }

        // Verify: each address matches the expected final state based on last operation for that address.
        for (uint256 i = 0; i < 5; i++) {
            bool expectedWhitelisted = false;
            for (uint256 j = 0; j < 5; j++) {
                if (addresses[j] == addresses[i]) {
                    expectedWhitelisted = shouldAdd[j];
                }
            }
            assertEq(
                whitelistProxy.isImplementationWhitelisted(ContractType.Organization, addresses[i]),
                expectedWhitelisted,
                "onchain state must match last operation for address"
            );
        }
    }

    /// @dev IWC-FUZZ-3: Fuzz mixed Account/Organization operations — mappings remain independent.
    function test_IWC_FUZZ_3_fuzz_mixedTypeOperations_mappingsRemainIndependent(
        address addr,
        bool addToOrg,
        bool addToAccount
    ) public {
        // Setup + Call: apply operations for each contract type independently.
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

    /// @dev IWC-FUZZ-6: Fuzz proxy initialization inputs — malformed init data never leaves partially initialized proxy.
    function test_IWC_FUZZ_6_fuzz_malformedInitData_neverLeavesPartiallyInitializedProxy(
        bytes calldata randomInitData
    ) public {
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
