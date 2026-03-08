// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {LibOrganizationEIP712} from "organization/libraries/LibOrganizationEIP712.sol";

/**
 * @dev Library-focused harness exposing `LibOrganizationEIP712` helpers.
 */
contract LibOrganizationEIP712Harness {
    /**
     * @dev Exposes `LibOrganizationEIP712.getDomainSeparator`.
     * @return domainSeparator The current EIP-712 domain separator for this harness.
     */
    function getDomainSeparatorViaLibrary() external view returns (bytes32 domainSeparator) {
        return LibOrganizationEIP712.getDomainSeparator();
    }

    /**
     * @dev Exposes `LibOrganizationEIP712.computeTypedDataHash`.
     * @param structHash The EIP-712 struct hash to wrap.
     * @return typedDataHash The final typed-data hash.
     */
    function computeTypedDataHashViaLibrary(bytes32 structHash) external view returns (bytes32 typedDataHash) {
        return LibOrganizationEIP712.computeTypedDataHash(structHash);
    }
}
