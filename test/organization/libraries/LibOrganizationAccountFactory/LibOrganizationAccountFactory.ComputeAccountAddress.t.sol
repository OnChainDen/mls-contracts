// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

import {
    LibOrganizationAccountFactorySuiteBase
} from "test/organization/libraries/LibOrganizationAccountFactory/LibOrganizationAccountFactorySuiteBase.sol";

/**
 * @dev Unit tests for `LibOrganizationAccountFactory.computeAccountAddress` behavior.
 */
contract LibOrganizationAccountFactoryComputeAccountAddressTest is LibOrganizationAccountFactorySuiteBase {
    /// @dev Verifies same salt always computes the same address.
    function test_ACCF_INV_1_LOAF_CAA_1_computeAccountAddress_sameSalt_isDeterministic() public view {
        bytes32 salt = bytes32(uint256(9030));

        // Setup: choose one deterministic salt for repeated computation checks.
        // Call: compute address twice for identical salt.
        address first = harness.computeAccountAddressViaLibrary(salt);
        address second = harness.computeAccountAddressViaLibrary(salt);

        // Verify: repeated computation with same salt is deterministic.
        assertEq(first, second, "same salt should produce deterministic address");
    }

    /// @dev Verifies different salts produce different computed addresses.
    function test_LOAF_CAA_2_computeAccountAddress_differentSalts_produceDifferentAddresses() public view {
        bytes32 saltA = bytes32(uint256(9031));
        bytes32 saltB = bytes32(uint256(9032));

        // Setup: choose two distinct deterministic salts.
        // Call: compute addresses for two different salts.
        address computedA = harness.computeAccountAddressViaLibrary(saltA);
        address computedB = harness.computeAccountAddressViaLibrary(saltB);

        // Verify: CREATE2 destination changes when salt changes.
        assertTrue(computedA != computedB, "different salts should produce different addresses");
    }

    /// @dev Verifies address derivation uses `keccak256(_getAccountProxyBytecode())` as init code hash.
    function test_LOAF_CAA_3_computeAccountAddress_usesAccountProxyBytecodeHash() public view {
        bytes32 salt = bytes32(uint256(9032));

        // Setup: fetch library-produced proxy creation bytecode.
        bytes memory bytecode = harness.getAccountProxyBytecodeViaLibrary();
        bytes32 bytecodeHash = keccak256(bytecode);

        // Call: compute using library wrapper and manual Create2 derivation.
        address viaLibrary = harness.computeAccountAddressViaLibrary(salt);
        address viaManual = Create2.computeAddress(salt, bytecodeHash, address(harness));

        // Verify: library output must use bytecode hash derivation.
        assertEq(viaLibrary, viaManual, "computeAccountAddress should use proxy-bytecode hash");
    }

    /// @dev Verifies deployer address in CREATE2 derivation is the organization (`address(this)` in harness context).
    function test_LOAF_CAA_4_computeAccountAddress_deployerIsOrganizationAddress() public view {
        bytes32 salt = bytes32(uint256(9033));

        // Setup: derive expected address for organization-deployer and non-organization-deployer.
        bytes32 bytecodeHash = keccak256(harness.getAccountProxyBytecodeViaLibrary());
        address expectedForOrganization = Create2.computeAddress(salt, bytecodeHash, address(harness));
        address expectedForTestContract = Create2.computeAddress(salt, bytecodeHash, address(this));

        // Call: compute via library wrapper.
        address computed = harness.computeAccountAddressViaLibrary(salt);

        // Verify: library uses organization address as deployer in CREATE2 formula.
        assertEq(computed, expectedForOrganization, "deployer should be organization address");
        assertTrue(computed != expectedForTestContract, "deployer should not be the test contract address");
    }

    /// @dev Verifies computed address matches actual deployed address.
    function test_LOAF_CAA_5_computeAccountAddress_matchesActualDeploymentAddress() public {
        bytes32 salt = bytes32(uint256(9034));

        // Setup: seed valid implementation for deployment.
        harness.setAccountImplementationStorage(accountImplementationV1);
        address computed = harness.computeAccountAddressViaLibrary(salt);

        // Call: deploy account with same salt.
        address deployed = harness.deployAccountViaLibrary(salt);

        // Verify: precomputed address equals runtime deployment address.
        assertEq(deployed, computed, "computed address should match deployment result");
    }

    /// @dev Verifies computed address does not depend on current account implementation version.
    function test_LOAF_CAA_6_computeAccountAddress_independentOfAccountImplementationVersion() public {
        bytes32 salt = bytes32(uint256(9071));

        // Setup: set first implementation and compute address.
        harness.setAccountImplementationStorage(accountImplementationV1);
        address before = harness.computeAccountAddressViaLibrary(salt);

        // Call: switch implementation and recompute.
        harness.setAccountImplementationStorage(accountImplementationV2);
        address afterUpgrade = harness.computeAccountAddressViaLibrary(salt);

        // Verify: CREATE2 address derivation is independent of implementation storage value.
        assertEq(before, afterUpgrade, "computeAccountAddress should not depend on implementation version");
    }

    /// @dev Verifies chain ID changes do not affect CREATE2 computed address derivation.
    function test_LOAF_CAA_7_computeAccountAddress_chainIdChanges_doNotAffectResult() public {
        bytes32 salt = bytes32(uint256(9072));

        // Setup: capture computed address on current chain id.
        uint256 originalChainId = block.chainid;
        address original = harness.computeAccountAddressViaLibrary(salt);

        vm.chainId(originalChainId + 1);

        // Call: recompute under a different chain id.
        address mutated = harness.computeAccountAddressViaLibrary(salt);

        // Verify: CREATE2 derivation excludes chain id and should remain unchanged.
        assertEq(mutated, original, "chain id should not affect computeAccountAddress");

        // Setup: restore original chain id for downstream tests.
        vm.chainId(originalChainId);
    }
}
