// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IImplementationWhitelist} from "interfaces/IImplementationWhitelist.sol";
import {
    LibOrganizationAccountFactoryHarness
} from "test/organization/libraries/LibOrganizationAccountFactory/LibOrganizationAccountFactoryHarness.sol";
import {
    LibOrganizationAccountFactorySuiteBase
} from "test/organization/libraries/LibOrganizationAccountFactory/LibOrganizationAccountFactorySuiteBase.sol";
import {ContractType} from "types/CommonTypes.sol";

/**
 * @dev Fuzz tests for account-factory behavior.
 */
contract LibOrganizationAccountFactoryFuzzTest is LibOrganizationAccountFactorySuiteBase {
    /// @dev Verifies random distinct salts compute to unique addresses.
    function testFuzz_AF_FT_1_computeAccountAddress_randomDistinctSalts_produceUniqueAddresses(
        bytes32 saltA,
        bytes32 saltB
    ) public view {
        // Setup: constrain fuzz inputs to distinct salts.
        vm.assume(saltA != saltB);

        // Call: compute account destinations for two distinct salts.
        address accountA = harness.computeAccountAddressViaLibrary(saltA);
        address accountB = harness.computeAccountAddressViaLibrary(saltB);

        // Verify: distinct salts should resolve to distinct addresses.
        assertTrue(accountA != accountB, "distinct salts should produce unique addresses");
    }

    /// @dev Verifies random salts produce deployable account proxies.
    function testFuzz_AF_FT_2_deployAccount_randomSalt_alwaysDeploysAccount(bytes32 salt) public {
        // Setup: seed valid implementation with runtime code.
        harness.setAccountImplementationStorage(accountImplementationV1);

        // Call: deploy account for fuzzed salt.
        address deployed = harness.deployAccountViaLibrary(salt);

        // Verify: deployment succeeds, runtime code exists, and mapping is tracked.
        assertGt(deployed.code.length, 0, "deployed account should have runtime code");
        assertTrue(harness.isDeployedAccount(deployed), "deployed account should be tracked");
    }

    /// @dev Verifies random non-whitelisted implementations are rejected.
    function testFuzz_AF_FT_3_setAccountImplementation_randomNonWhitelistedAddress_reverts(address candidate) public {
        // Setup: whitelist one known implementation and ensure candidate differs.
        whitelist.setImplementationWhitelisted(ContractType.Account, accountImplementationV1, true);
        vm.assume(candidate != accountImplementationV1);

        // Verify: non-whitelisted candidate should be rejected.
        vm.expectRevert(
            abi.encodeWithSelector(IImplementationWhitelist.ImplementationNotWhitelisted.selector, candidate)
        );
        // Call: attempt library-level implementation update.
        harness.setAccountImplementationViaLibrary(candidate);
    }

    /// @dev Verifies computed address matches deployed address for any valid salt.
    function testFuzz_AF_FT_4_computeAndDeploy_randomSalt_deployedMatchesComputed(bytes32 salt) public {
        // Setup: seed valid implementation with runtime code.
        harness.setAccountImplementationStorage(accountImplementationV1);

        address computed = harness.computeAccountAddressViaLibrary(salt);

        // Call: deploy account for same salt.
        address deployed = harness.deployAccountViaLibrary(salt);

        // Verify: computed and deployed addresses must match.
        assertEq(deployed, computed, "deployed address should match computed address");
    }

    /// @dev Verifies known-deployed accounts are tracked and random non-deployed addresses are not.
    function testFuzz_AF_FT_5_isAccountDeployedByOrganization_randomAddressNotDeployed_returnsFalse(address candidate)
        public
    {
        // Setup: seed implementation and deploy two accounts with fixed salts.
        harness.setAccountImplementationStorage(accountImplementationV1);
        address deployedA = harness.deployAccountViaLibrary(bytes32(uint256(1)));
        address deployedB = harness.deployAccountViaLibrary(bytes32(uint256(2)));

        vm.assume(candidate != deployedA && candidate != deployedB);

        // Verify: known-deployed accounts should be tracked.
        assertTrue(harness.isAccountDeployedByOrganizationViaLibrary(deployedA), "deployed A should be tracked");
        assertTrue(harness.isAccountDeployedByOrganizationViaLibrary(deployedB), "deployed B should be tracked");

        // Call: query deployment-tracking mapping for arbitrary non-deployed candidate.
        bool isTracked = harness.isAccountDeployedByOrganizationViaLibrary(candidate);

        // Verify: non-deployed addresses should not be tracked.
        assertFalse(isTracked, "non-deployed address should return false");
    }

    /// @dev Verifies same salt across different organizations computes different addresses.
    function testFuzz_AF_FT_6_sameSaltAcrossDifferentOrganizations_producesDifferentAddresses(bytes32 salt) public {
        // Setup: instantiate a second organization harness.
        LibOrganizationAccountFactoryHarness otherHarness = new LibOrganizationAccountFactoryHarness();

        // Call: compute same-salt destination for each organization.
        address thisOrgAddress = harness.computeAccountAddressViaLibrary(salt);
        address otherOrgAddress = otherHarness.computeAccountAddressViaLibrary(salt);

        // Verify: different organization deployers should derive different CREATE2 addresses.
        assertTrue(thisOrgAddress != otherOrgAddress, "same salt across organizations should differ");
    }
}
