// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IImplementationWhitelist} from "interfaces/IImplementationWhitelist.sol";
import {
    ImplementationWhitelistHarness
} from "test/implementation-whitelist/ImplementationWhitelistImplementation/ImplementationWhitelistHarnesses.sol";
import {
    ImplementationWhitelistSuiteBase
} from "test/implementation-whitelist/ImplementationWhitelistImplementation/ImplementationWhitelistSuiteBase.sol";
import {ContractType} from "types/CommonTypes.sol";

/**
 * @dev Internal-helper coverage for `_addToWhitelist` / `_removeFromWhitelist` via harness wrappers.
 */
contract ImplementationWhitelistInternalHelpersTest is ImplementationWhitelistSuiteBase {
    /// @dev Verifies `_addToWhitelist` marks each input as whitelisted for the given contract type.
    ///      Plan 15: IWI-HELP-1, IWI-HELP-2.
    function test_IWI_ATW_1_IWI_HELP_1_IWI_HELP_2_addToWhitelist_marksEachInputWhitelisted() public {
        // Setup: build deterministic input addresses.
        address[] memory inputs = _pair(organizationImplementationA, organizationImplementationB);

        // Call: invoke harness wrapper for `_addToWhitelist`.
        whitelistProxy.exposeAddToWhitelist(ContractType.Organization, inputs);

        // Verify: each input is whitelisted under Organization type.
        assertTrue(whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA));
        assertTrue(whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationB));
    }

    /// @dev Verifies `_addToWhitelist` leaves other contract-type mapping unchanged for the same addresses.
    ///      Plan 15: IWI-HELP-4.
    function test_IWI_ATW_2_IWI_HELP_4_addToWhitelist_otherContractTypeUnchanged() public {
        // Setup: pre-set opposite contract type to known false state.
        assertFalse(whitelistProxy.isImplementationWhitelisted(ContractType.Account, organizationImplementationA));

        // Call: add entry only under Organization type.
        whitelistProxy.exposeAddToWhitelist(ContractType.Organization, _single(organizationImplementationA));

        // Verify: Account-type mapping remains unchanged for same address.
        assertFalse(whitelistProxy.isImplementationWhitelisted(ContractType.Account, organizationImplementationA));
        assertTrue(whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA));
    }

    /// @dev Verifies `_addToWhitelist` emits one `ImplementationWhitelisted` event per input entry.
    ///      Plan 15: IWI-HELP-5.
    function test_IWI_ATW_3_IWI_HELP_5_addToWhitelist_emitsOneEventPerEntry() public {
        // Setup: build two-entry input list.
        address[] memory inputs = _pair(organizationImplementationA, organizationImplementationB);

        // Verify: expect one event per input entry in order.
        vm.expectEmit(true, true, true, true, address(whitelistProxy));
        emit IImplementationWhitelist.ImplementationWhitelisted(ContractType.Organization, organizationImplementationA);
        vm.expectEmit(true, true, true, true, address(whitelistProxy));
        emit IImplementationWhitelist.ImplementationWhitelisted(ContractType.Organization, organizationImplementationB);

        // Call: invoke add helper through harness.
        whitelistProxy.exposeAddToWhitelist(ContractType.Organization, inputs);
    }

    /// @dev Verifies `_addToWhitelist` is a no-op for empty input arrays and does not revert.
    ///      Plan 15: IWI-HELP-3.
    function test_IWI_ATW_4_IWI_HELP_3_addToWhitelist_emptyInput_noopAndNoRevert() public {
        // Setup: capture baseline state before empty call.
        bool beforeState =
            whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA);
        address[] memory empty;

        // Call: invoke add helper with empty array.
        whitelistProxy.exposeAddToWhitelist(ContractType.Organization, empty);

        // Verify: state remains unchanged.
        bool afterState =
            whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA);
        assertEq(afterState, beforeState, "empty add should not mutate state");
    }

    /// @dev Verifies duplicate `_addToWhitelist` entries are idempotent at state level.
    function test_IWI_ATW_6_addToWhitelist_duplicateEntries_idempotentState() public {
        // Setup: duplicate address list.
        address[] memory duplicates = _pair(organizationImplementationA, organizationImplementationA);

        // Call: add duplicate entries in one helper invocation.
        whitelistProxy.exposeAddToWhitelist(ContractType.Organization, duplicates);

        // Verify: final mapping state remains `true`.
        assertTrue(whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA));
    }

    /// @dev Verifies `_removeFromWhitelist` marks each input as not whitelisted for the given contract type.
    ///      Plan 15: IWI-HELP-6.
    function test_IWI_RTW_1_IWI_HELP_6_removeFromWhitelist_marksEachInputUnwhitelisted() public {
        // Setup: seed two whitelisted entries to remove.
        whitelistProxy.exposeAddToWhitelist(
            ContractType.Organization, _pair(organizationImplementationA, organizationImplementationB)
        );

        // Call: remove both entries.
        whitelistProxy.exposeRemoveFromWhitelist(
            ContractType.Organization, _pair(organizationImplementationA, organizationImplementationB)
        );

        // Verify: each entry is now unwhitelisted.
        assertFalse(whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA));
        assertFalse(whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationB));
    }

    /// @dev Verifies `_removeFromWhitelist` leaves other contract-type mapping unchanged for same addresses.
    ///      Plan 15: IWI-HELP-8.
    function test_IWI_RTW_2_IWI_HELP_8_removeFromWhitelist_otherContractTypeUnchanged() public {
        // Setup: seed same address under both types, then remove only Organization entry.
        whitelistProxy.exposeAddToWhitelist(ContractType.Organization, _single(organizationImplementationA));
        whitelistProxy.exposeAddToWhitelist(ContractType.Account, _single(organizationImplementationA));

        // Call: remove Organization-type entry.
        whitelistProxy.exposeRemoveFromWhitelist(ContractType.Organization, _single(organizationImplementationA));

        // Verify: Account-type mapping remains true.
        assertFalse(whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA));
        assertTrue(whitelistProxy.isImplementationWhitelisted(ContractType.Account, organizationImplementationA));
    }

    /// @dev Verifies `_removeFromWhitelist` emits one `ImplementationUnwhitelisted` event per input entry.
    ///      Plan 15: IWI-HELP-10.
    function test_IWI_RTW_3_IWI_HELP_10_removeFromWhitelist_emitsOneEventPerEntry() public {
        // Setup: seed two entries that will be removed.
        whitelistProxy.exposeAddToWhitelist(
            ContractType.Organization, _pair(organizationImplementationA, organizationImplementationB)
        );
        address[] memory inputs = _pair(organizationImplementationA, organizationImplementationB);

        // Verify: expect one unwhitelist event per entry.
        vm.expectEmit(true, true, true, true, address(whitelistProxy));
        emit IImplementationWhitelist.ImplementationUnwhitelisted(
            ContractType.Organization, organizationImplementationA
        );
        vm.expectEmit(true, true, true, true, address(whitelistProxy));
        emit IImplementationWhitelist.ImplementationUnwhitelisted(
            ContractType.Organization, organizationImplementationB
        );

        // Call: remove via helper wrapper.
        whitelistProxy.exposeRemoveFromWhitelist(ContractType.Organization, inputs);
    }

    /// @dev Verifies removing non-whitelisted entries is a no-op and does not revert.
    ///      Plan 15: IWI-HELP-7.
    function test_IWI_RTW_4_IWI_HELP_7_removeFromWhitelist_nonWhitelistedEntries_noopAndNoRevert() public {
        // Setup: ensure entry is currently not whitelisted.
        assertFalse(whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA));

        // Call: remove entry that is already unwhitelisted.
        whitelistProxy.exposeRemoveFromWhitelist(ContractType.Organization, _single(organizationImplementationA));

        // Verify: state remains false and call succeeds.
        assertFalse(whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA));
    }

    /// @dev Verifies empty `_removeFromWhitelist` input is a no-op and does not revert.
    ///      Plan 15: IWI-HELP-9.
    function test_IWI_RTW_5_IWI_HELP_9_removeFromWhitelist_emptyInput_noopAndNoRevert() public {
        // Setup: capture baseline state before empty remove.
        bool beforeState =
            whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA);
        address[] memory empty;

        // Call: remove helper with empty input.
        whitelistProxy.exposeRemoveFromWhitelist(ContractType.Organization, empty);

        // Verify: state remains unchanged.
        bool afterState =
            whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA);
        assertEq(afterState, beforeState, "empty remove should not mutate state");
    }

    /// @dev Verifies duplicate `_removeFromWhitelist` entries are idempotent at state level.
    function test_IWI_RTW_6_removeFromWhitelist_duplicateEntries_idempotentState() public {
        // Setup: seed entry to true, then remove it twice in one call.
        whitelistProxy.exposeAddToWhitelist(ContractType.Organization, _single(organizationImplementationA));
        address[] memory duplicates = _pair(organizationImplementationA, organizationImplementationA);

        // Call: remove duplicate entries in one helper invocation.
        whitelistProxy.exposeRemoveFromWhitelist(ContractType.Organization, duplicates);

        // Verify: final mapping state remains `false`.
        assertFalse(whitelistProxy.isImplementationWhitelisted(ContractType.Organization, organizationImplementationA));
    }
}
