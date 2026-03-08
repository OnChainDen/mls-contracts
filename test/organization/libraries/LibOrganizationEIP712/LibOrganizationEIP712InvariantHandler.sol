// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibOrganizationEIP712Harness
} from "test/organization/libraries/LibOrganizationEIP712/LibOrganizationEIP712Harness.sol";

/**
 * @dev Lightweight invariant handler that exercises the `LibOrganizationEIP712` harness surface.
 */
contract LibOrganizationEIP712InvariantHandler {
    /// @dev Harness whose EIP-712 helper surface is exercised during invariant runs.
    LibOrganizationEIP712Harness internal immutable harness;

    /**
     * @dev Stores the harness under test.
     * @param harness_ The harness whose helper methods the handler will call.
     */
    constructor(LibOrganizationEIP712Harness harness_) {
        harness = harness_;
    }

    /**
     * @dev Calls the domain-separator helper with the current domain.
     */
    function callGetDomainSeparator() external {
        harness.getDomainSeparatorViaLibrary();
    }

    /**
     * @dev Calls the typed-data helper with an arbitrary struct hash.
     * @param structHash The fuzzed struct hash to wrap.
     */
    function callComputeTypedDataHash(bytes32 structHash) external {
        harness.computeTypedDataHashViaLibrary(structHash);
    }
}
