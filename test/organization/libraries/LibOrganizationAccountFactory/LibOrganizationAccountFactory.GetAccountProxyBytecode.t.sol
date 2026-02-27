// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {AccountProxy} from "account/AccountProxy.sol";
import {
    LibOrganizationAccountFactoryHarness
} from "test/organization/libraries/LibOrganizationAccountFactory/LibOrganizationAccountFactoryHarness.sol";
import {
    LibOrganizationAccountFactorySuiteBase
} from "test/organization/libraries/LibOrganizationAccountFactory/LibOrganizationAccountFactorySuiteBase.sol";

/**
 * @dev Unit tests for `LibOrganizationAccountFactory._getAccountProxyBytecode` behavior.
 */
contract LibOrganizationAccountFactoryGetAccountProxyBytecodeTest is LibOrganizationAccountFactorySuiteBase {
    /// @dev Verifies returned creation bytecode is valid and deployable.
    function test_getAccountProxyBytecode_returnsValidAccountProxyCreationBytecode() public {
        // Setup: seed valid implementation so constructor beacon validation succeeds.
        harness.setAccountImplementationStorage(accountImplementationV1);

        // Call: fetch proxy creation bytecode from library wrapper.
        bytes memory bytecode = harness.getAccountProxyBytecodeViaLibrary();

        // Verify: returned bytecode is non-empty and includes constructor args after creation code.
        assertGt(bytecode.length, type(AccountProxy).creationCode.length, "bytecode should include constructor args");

        address deployed;
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        // Verify: bytecode can deploy a runtime proxy contract.
        assertTrue(deployed != address(0), "creation bytecode should deploy successfully");
        assertGt(deployed.code.length, 0, "deployed proxy should have runtime code");
    }

    /// @dev Verifies bytecode includes organization address as beacon constructor parameter.
    function test_getAccountProxyBytecode_includesOrganizationAddressAsBeaconParameter() public view {
        // Setup: precompute expected creation bytecode and constructor args.
        // Call: fetch proxy creation bytecode from library wrapper.
        bytes memory actual = harness.getAccountProxyBytecodeViaLibrary();
        bytes memory expected = abi.encodePacked(type(AccountProxy).creationCode, abi.encode(address(harness), ""));

        // Verify: constructor args include harness address as beacon.
        assertEq(actual, expected, "bytecode should embed organization address as beacon parameter");
    }

    /// @dev Verifies bytecode includes empty bytes as initialization data constructor parameter.
    function test_getAccountProxyBytecode_includesEmptyInitializationData() public view {
        // Call: fetch proxy creation bytecode from library wrapper.
        bytes memory actual = harness.getAccountProxyBytecodeViaLibrary();

        bytes memory expectedArgs = abi.encode(address(harness), "");
        bytes memory actualArgs = new bytes(expectedArgs.length);

        // Setup: copy trailing constructor-args suffix from full creation bytecode.
        uint256 offset = actual.length - expectedArgs.length;
        for (uint256 i = 0; i < expectedArgs.length; ++i) {
            actualArgs[i] = actual[offset + i];
        }

        // Verify: encoded constructor args use empty init data.
        assertEq(actualArgs, expectedArgs, "constructor args should encode empty init data");
    }

    /// @dev Verifies different organizations produce different bytecode due different beacon addresses.
    function test_getAccountProxyBytecode_differentOrganizations_produceDifferentBytecode() public {
        // Setup: deploy a second organization harness with a different address.
        LibOrganizationAccountFactoryHarness otherHarness = new LibOrganizationAccountFactoryHarness();

        // Call: fetch bytecode from both organizations.
        bytes memory thisOrgBytecode = harness.getAccountProxyBytecodeViaLibrary();
        bytes memory otherOrgBytecode = otherHarness.getAccountProxyBytecodeViaLibrary();

        // Verify: beacon-address difference changes bytecode.
        assertTrue(keccak256(thisOrgBytecode) != keccak256(otherOrgBytecode), "bytecode should differ by org address");
    }

    /// @dev Verifies bytecode is deterministic for repeated calls in the same organization.
    function test_getAccountProxyBytecode_sameOrganization_repeatedCallsAreDeterministic() public view {
        // Setup: use the same organization harness for repeated calls.
        // Call: fetch bytecode twice from the same harness.
        bytes memory first = harness.getAccountProxyBytecodeViaLibrary();
        bytes memory second = harness.getAccountProxyBytecodeViaLibrary();

        // Verify: repeated calls should produce identical bytecode.
        assertEq(first, second, "bytecode should be deterministic for same organization");
    }

    /// @dev Verifies bytecode is independent from current account implementation storage value.
    function test_getAccountProxyBytecode_independentOfAccountImplementationValue() public {
        // Setup: compute bytecode before and after changing account implementation storage.
        harness.setAccountImplementationStorage(accountImplementationV1);
        bytes memory before = harness.getAccountProxyBytecodeViaLibrary();

        // Call: switch implementation storage and fetch bytecode again.
        harness.setAccountImplementationStorage(accountImplementationV2);
        bytes memory afterUpdate = harness.getAccountProxyBytecodeViaLibrary();

        // Verify: proxy init code should not depend on implementation storage value.
        assertEq(before, afterUpdate, "proxy bytecode should not depend on account implementation");
    }
}
