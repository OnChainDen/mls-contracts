// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAccountFactory} from "interfaces/organization/IOrganizationAccountFactory.sol";
import {
    LibOrganizationAccountFactoryHarness
} from "test/organization/libraries/LibOrganizationAccountFactory/LibOrganizationAccountFactoryHarness.sol";
import {
    LibOrganizationAccountFactorySuiteBase
} from "test/organization/libraries/LibOrganizationAccountFactory/LibOrganizationAccountFactorySuiteBase.sol";

/**
 * @dev Unit tests for account-deployment tracking helpers in `LibOrganizationAccountFactory`.
 */
contract LibOrganizationAccountFactoryAccountTrackingTest is LibOrganizationAccountFactorySuiteBase {
    /// @dev Verifies deployed accounts return true from `isAccountDeployedByOrganization`.
    function test_isAccountDeployedByOrganization_deployedAccount_returnsTrue() public {
        bytes32 salt = bytes32(uint256(9135));

        // Setup: seed valid implementation and deploy deterministic account.
        harness.setAccountImplementationStorage(accountImplementationV1);
        address deployed = harness.deployAccountViaLibrary(salt);

        // Call: read deployment-tracking status for deployed account.
        bool isDeployed = harness.isAccountDeployedByOrganizationViaLibrary(deployed);

        // Verify: deployed account should be tracked as organization-deployed.
        assertTrue(isDeployed, "deployed account should return true");
    }

    /// @dev Verifies unknown addresses return false from `isAccountDeployedByOrganization`.
    function test_isAccountDeployedByOrganization_unknownAddress_returnsFalse() public view {
        address unknown = address(0x9136);

        // Setup: pick a deterministic address with no deployment fixture.
        // Call: read deployment-tracking status for unknown address.
        bool isDeployed = harness.isAccountDeployedByOrganizationViaLibrary(unknown);

        // Verify: unknown address should not be tracked as deployed.
        assertFalse(isDeployed, "unknown address should return false");
    }

    /// @dev Verifies zero address returns false from `isAccountDeployedByOrganization`.
    function test_isAccountDeployedByOrganization_zeroAddress_returnsFalse() public view {
        // Setup: use `address(0)` as canonical non-deployed sentinel.
        // Call: read deployment-tracking status for `address(0)`.
        bool isDeployed = harness.isAccountDeployedByOrganizationViaLibrary(address(0));

        // Verify: zero address should never be tracked as deployed account.
        assertFalse(isDeployed, "zero address should return false");
    }

    /// @dev Verifies accounts deployed by another organization return false.
    function test_isAccountDeployedByOrganization_accountDeployedByDifferentOrganization_returnsFalse()
        public
    {
        bytes32 salt = bytes32(uint256(9138));

        // Setup: deploy account from another organization harness.
        LibOrganizationAccountFactoryHarness otherHarness = new LibOrganizationAccountFactoryHarness();
        otherHarness.setAccountImplementationStorage(accountImplementationV1);
        address deployedByOther = otherHarness.deployAccountViaLibrary(salt);

        // Call: query deployment status from this organization harness.
        bool trackedByThisOrg = harness.isAccountDeployedByOrganizationViaLibrary(deployedByOther);

        // Verify: cross-organization account should not be treated as deployed by this org.
        assertFalse(trackedByThisOrg, "account from another organization should return false");
    }

    /// @dev Verifies `validateIsAccountDeployedByOrgOrRevert` rejects accounts deployed by a different organization.
    function test_validateIsAccountDeployedByOrgOrRevert_foreignOrganizationAccount_reverts() public {
        bytes32 salt = bytes32(uint256(9139));

        // Setup: deploy an account through a distinct organization harness so this harness never marks it as local.
        LibOrganizationAccountFactoryHarness otherHarness = new LibOrganizationAccountFactoryHarness();
        otherHarness.setAccountImplementationStorage(accountImplementationV1);
        address deployedByOther = otherHarness.deployAccountViaLibrary(salt);

        // Verify: cross-organization validation must fail with the canonical deployed-account error.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAccountFactory.AccountNotDeployedByOrganization.selector, deployedByOther
            )
        );

        // Call: validate the foreign organization's deployed account from this harness.
        harness.validateIsAccountDeployedByOrgOrRevertViaLibrary(deployedByOther);
    }

    /// @dev Verifies computed address transitions from false to true only after successful deployment.
    function test_isAccountDeployedByOrganization_computedAddress_falseBeforeAndTrueAfterDeployment()
        public
    {
        bytes32 salt = bytes32(uint256(9173));

        // Setup: compute deterministic destination before deployment.
        harness.setAccountImplementationStorage(accountImplementationV1);
        address computed = harness.computeAccountAddressViaLibrary(salt);

        // Call: query status before deployment then deploy and query again.
        bool before = harness.isAccountDeployedByOrganizationViaLibrary(computed);
        harness.deployAccountViaLibrary(salt);
        bool afterDeployment = harness.isAccountDeployedByOrganizationViaLibrary(computed);

        // Verify: computed destination is untracked before deploy and tracked after successful deploy.
        assertFalse(before, "computed address should be false before deployment");
        assertTrue(afterDeployment, "computed address should be true after deployment");
    }

    /// @dev Verifies `validateIsAccountDeployedByOrgOrRevert` succeeds for deployed accounts.
    function test_validateIsAccountDeployedByOrgOrRevert_deployedAccount_succeeds() public {
        bytes32 salt = bytes32(uint256(9139));

        // Setup: seed valid implementation and deploy deterministic account.
        harness.setAccountImplementationStorage(accountImplementationV1);
        address deployed = harness.deployAccountViaLibrary(salt);

        // Call: validate deployed-account status via revert-on-failure helper.
        harness.validateIsAccountDeployedByOrgOrRevertViaLibrary(deployed);

        // Verify: call should complete without reverting.
        assertTrue(true, "validation should succeed for deployed account");
    }

    /// @dev Verifies `validateIsAccountDeployedByOrgOrRevert` reverts for non-deployed accounts.
    function test_validateIsAccountDeployedByOrgOrRevert_nonOrgAccount_reverts() public {
        address nonOrgAccount = address(0x9140);

        // Setup: choose a deterministic address not marked as deployed.
        // Verify: non-deployed account should revert with canonical account-factory error.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAccountFactory.AccountNotDeployedByOrganization.selector, nonOrgAccount)
        );
        // Call: validate non-deployed account address.
        harness.validateIsAccountDeployedByOrgOrRevertViaLibrary(nonOrgAccount);
    }

    /// @dev Verifies `validateIsAccountDeployedByOrgOrRevert` reverts for `address(0)`.
    function test_validateIsAccountDeployedByOrgOrRevert_zeroAddress_reverts() public {
        // Setup: use `address(0)` as canonical undeployed account address.
        // Verify: zero address should revert with canonical account-factory error.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAccountFactory.AccountNotDeployedByOrganization.selector, address(0))
        );
        // Call: validate zero address.
        harness.validateIsAccountDeployedByOrgOrRevertViaLibrary(address(0));
    }
}
