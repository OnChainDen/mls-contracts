// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    OrganizationPolicyBaseSuiteBase
} from "test/organization/base/OrganizationPolicyBase/OrganizationPolicyBaseSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";

/**
 * @dev Unit tests for `OrganizationPolicyBase.policiesRoot` view behavior.
 */
contract OrganizationPolicyBaseViewsTest is OrganizationPolicyBaseSuiteBase {
    /// @dev Configures a baseline one-admin organization used by positive auth-path tests.
    function _setSingleAdminConfig() internal {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
    }

    /// @dev Sets policies root via authenticated guardian flow.
    function _setPoliciesAsGuardian(bytes32 newPoliciesRoot, string memory ipfsCid, uint256 salt) internal {
        (AdminAuthParams memory auth,) = _buildSetPoliciesAuth({
            newPoliciesRoot: newPoliciesRoot,
            ipfsCid: ipfsCid,
            salt: salt,
            expirationTimestamp: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        harness.setPolicies(newPoliciesRoot, ipfsCid, auth);
    }

    /// @dev Verifies `policiesRoot()` returns zero before any successful `setPolicies` call.
    function test_policiesRoot_beforeAnySuccessfulSetPolicies_returnsZero() public view {
        assertEq(harness.policiesRoot(), bytes32(0), "initial policies root should be zero");
    }

    /// @dev Verifies `policiesRoot()` returns the latest root after one and multiple updates.
    function test_policiesRoot_afterOneAndMultipleUpdates_returnsLatestRoot() public {
        _setSingleAdminConfig();

        bytes32 root1 = keccak256("views-root-1");
        bytes32 root2 = keccak256("views-root-2");

        _setPoliciesAsGuardian(root1, "ipfs://views-1", 2001);
        assertEq(harness.policiesRoot(), root1, "policies root should equal first update");

        _setPoliciesAsGuardian(root2, "ipfs://views-2", 2002);
        assertEq(harness.policiesRoot(), root2, "policies root should equal latest update");
    }
}
