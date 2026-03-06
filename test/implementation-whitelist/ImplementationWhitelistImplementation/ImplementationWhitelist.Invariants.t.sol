// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {ImplementationWhitelistHarness}
    from "test/implementation-whitelist/ImplementationWhitelistImplementation/ImplementationWhitelistHarnesses.sol";
import {ImplementationWhitelistSuiteBase}
    from "test/implementation-whitelist/ImplementationWhitelistImplementation/ImplementationWhitelistSuiteBase.sol";
import {ContractType} from "types/CommonTypes.sol";

/// @dev Invariant tests for implementation whitelist controls.
contract ImplementationWhitelistInvariantsTest is ImplementationWhitelistSuiteBase {
    /// @dev IWC-INV-7: Initialization permanence — once initialized, cannot revert to uninitialized.
    function test_IWC_INV_7_initializationPermanence_onceInitializedCannotRevert() public {
        // Setup: deploy a fresh uninitialized proxy.
        ImplementationWhitelistHarness proxy = _deployUninitializedProxy();
        address[] memory empty = new address[](0);

        // Verify: proxy starts uninitialized.
        assertFalse(proxy.isInitialized(), "should start uninitialized");

        // Call: initialize the proxy.
        proxy.initialize(OWNER, empty, empty);

        // Verify: proxy is now initialized.
        assertTrue(proxy.isInitialized(), "should be initialized after init");

        // Call: attempt re-initialization — should revert.
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        proxy.initialize(OWNER, empty, empty);

        // Verify: isInitialized remains true after failed re-init attempt.
        assertTrue(proxy.isInitialized(), "must remain initialized after failed re-init");

        // Verify: ownership transfer does not affect initialization state.
        vm.prank(OWNER);
        proxy.transferOwnership(NEW_OWNER);
        vm.prank(NEW_OWNER);
        proxy.acceptOwnership();
        assertTrue(proxy.isInitialized(), "must remain initialized after ownership transfer");
    }
}
