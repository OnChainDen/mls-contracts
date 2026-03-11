// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Errors} from "@openzeppelin/contracts/utils/Errors.sol";

import {AccountProxy} from "account/AccountProxy.sol";
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

    /// @dev Verifies deployed-account tracking flips from `false` to `true` exactly once for a successful deploy.
    function testFuzz_AF_FT_2__FLOAF_DEPLOY_125_deployAccount_randomSalt_alwaysDeploysAccount(bytes32 salt) public {
        // Setup: seed valid implementation with runtime code.
        harness.setAccountImplementationStorage(accountImplementationV1);
        address computed = harness.computeAccountAddressViaLibrary(salt);
        assertFalse(harness.isDeployedAccount(computed), "mapping should start false before deployment");

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

    /// @dev Verifies CREATE2 address computation is deterministic and matches the deployed address for valid salts.
    function testFuzz_AF_FT_4__FLOAF_DEPLOY_124_computeAndDeploy_randomSalt_deployedMatchesComputed(bytes32 salt)
        public
    {
        // Setup: seed valid implementation with runtime code.
        harness.setAccountImplementationStorage(accountImplementationV1);

        address computed = harness.computeAccountAddressViaLibrary(salt);
        address computedAgain = harness.computeAccountAddressViaLibrary(salt);

        // Call: deploy account for same salt.
        address deployed = harness.deployAccountViaLibrary(salt);

        // Verify: computation should be deterministic and match the deployed address exactly.
        assertEq(computed, computedAgain, "computeAccountAddress should be deterministic");
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

    /// @dev Verifies the same salt across different organizations computes different account addresses.
    function testFuzz_AF_FT_6__FLOAF_ADDRESS_126_sameSaltAcrossDifferentOrganizations_producesDifferentAddresses(
        bytes32 salt
    ) public {
        // Setup: instantiate a second organization harness.
        LibOrganizationAccountFactoryHarness otherHarness = new LibOrganizationAccountFactoryHarness();

        // Call: compute same-salt destination for each organization.
        address thisOrgAddress = harness.computeAccountAddressViaLibrary(salt);
        address otherOrgAddress = otherHarness.computeAccountAddressViaLibrary(salt);

        // Verify: different organization deployers should derive different CREATE2 addresses.
        assertTrue(thisOrgAddress != otherOrgAddress, "same salt across organizations should differ");
    }

    /// @dev Verifies reusing the same salt always reverts and preserves deployed-account tracking after the first
    /// successful deployment.
    /// @param salt Fuzzed CREATE2 salt reused across both deployment attempts.
    function testFuzz_FLOAF_DEPLOY_127_reusingSameSaltAlwaysRevertsAndPreservesTracking(bytes32 salt) public {
        // Setup: seed a valid implementation and deploy once to occupy the CREATE2 slot.
        harness.setAccountImplementationStorage(accountImplementationV1);
        address firstDeployment = harness.deployAccountViaLibrary(salt);
        assertTrue(harness.isDeployedAccount(firstDeployment), "first deployment should mark the account as tracked");

        // Call: attempt to deploy a second time with the same salt.
        vm.expectRevert(Errors.FailedDeployment.selector);
        harness.deployAccountViaLibrary(salt);

        // Verify: the original deployment remains tracked and no rollback occurs on the collision revert path.
        assertTrue(harness.isDeployedAccount(firstDeployment), "collision revert should preserve deployed tracking");
    }

    /// @dev Verifies account-proxy bytecode generation is deterministic within one organization and changes across
    /// organization addresses.
    /// @param foreignOrganization Fuzzed non-zero organization address used for the field-sensitivity comparison.
    function testFuzz_FLOAF_BYTECODE_128_getAccountProxyBytecode_isDeterministicAndOrganizationSensitive(
        address foreignOrganization
    ) public view {
        // Setup: constrain the comparison organization away from this harness address and precompute a reference
        // bytecode blob for it.
        vm.assume(foreignOrganization != address(0));
        vm.assume(foreignOrganization != address(harness));
        bytes memory expectedBytecode =
            abi.encodePacked(type(AccountProxy).creationCode, abi.encode(address(harness), ""));
        bytes memory foreignBytecode =
            abi.encodePacked(type(AccountProxy).creationCode, abi.encode(foreignOrganization, ""));

        // Call: read account-proxy bytecode repeatedly for this harness.
        bytes memory bytecode = harness.getAccountProxyBytecodeViaLibrary();
        bytes memory repeatedBytecode = harness.getAccountProxyBytecodeViaLibrary();

        // Verify: one organization should produce deterministic bytecode, match the reference model, and change when
        // the organization address changes.
        assertEq(keccak256(bytecode), keccak256(repeatedBytecode), "bytecode should be deterministic per org");
        assertEq(keccak256(bytecode), keccak256(expectedBytecode), "bytecode should encode this organization address");
        assertTrue(
            keccak256(bytecode) != keccak256(foreignBytecode),
            "bytecode should change when the organization address changes"
        );
    }
}
