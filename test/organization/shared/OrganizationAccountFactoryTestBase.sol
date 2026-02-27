// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {AccountImplementation} from "account/AccountImplementation.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";
import {
    OrganizationAccountFactoryStateHarness
} from "test/organization/shared/OrganizationAccountFactoryStateHarness.sol";
import {
    ImplementationWhitelistMock
} from "test/organization/shared/OrganizationAccountFactoryMocks.sol";
import {OrganizationAdminTestBase} from "test/organization/shared/OrganizationAdminTestBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {ContractType, OperationType} from "types/CommonTypes.sol";

/**
 * @dev Shared setup/builders for account-factory-focused tests.
 */
abstract contract OrganizationAccountFactoryTestBase is OrganizationAdminTestBase {
    /// @dev Typed state harness with account-factory namespace helpers.
    OrganizationAccountFactoryStateHarness internal accountFactoryStateHarness;

    /// @dev Mock whitelist used by account-implementation validation paths.
    ImplementationWhitelistMock internal whitelist;

    /// @dev Deterministic account implementation fixtures with runtime code.
    address internal accountImplementationV1;
    address internal accountImplementationV2;

    /**
     * @dev Initializes account-factory fixtures after core admin setup.
     */
    function setUp() public virtual override {
        super.setUp();

        accountFactoryStateHarness = OrganizationAccountFactoryStateHarness(address(stateHarness));

        whitelist = new ImplementationWhitelistMock();
        accountFactoryStateHarness.setUpgradeState(address(whitelist), false);

        accountImplementationV1 = address(new AccountImplementation());
        accountImplementationV2 = address(new AccountImplementation());
    }

    /**
     * @dev Seeds one-admin threshold-one baseline used by most positive auth-path tests.
     */
    function _setSingleAdminThresholdOne() internal {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
    }

    /**
     * @dev Whitelists (or un-whitelists) an account implementation in the test whitelist.
     */
    function _setAccountImplementationWhitelisted(address implementation, bool isWhitelisted) internal {
        whitelist.setImplementationWhitelisted(ContractType.Account, implementation, isWhitelisted);
    }

    /**
     * @dev Builds auth for `deployAccount` using base-contract operation-data encoding.
     */
    function _buildDeployAccountAuth(
        bytes32 create2Salt,
        uint256 salt,
        uint256 expiration,
        bool isApproval,
        uint256[] memory privateKeys
    ) internal view returns (AdminAuthParams memory auth, bytes memory operationData) {
        operationData = _encodeOperationDataForDeployAccount(create2Salt);
        auth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.DeployAccount,
            operationData: operationData,
            isApproval: isApproval,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: privateKeys
        });
    }

    /**
     * @dev Builds auth for `setAccountImplementation` using base-contract operation-data encoding.
     */
    function _buildSetAccountImplementationAuth(
        address newImplementation,
        uint256 salt,
        uint256 expiration,
        bool isApproval,
        uint256[] memory privateKeys
    ) internal view returns (AdminAuthParams memory auth, bytes memory operationData) {
        operationData = _encodeOperationDataForSetAccountImplementation(newImplementation);
        auth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.UpgradeAccount,
            operationData: operationData,
            isApproval: isApproval,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: privateKeys
        });
    }

    /**
     * @dev Encodes operation data exactly as `OrganizationAccountFactoryBase.deployAccount`.
     */
    function _encodeOperationDataForDeployAccount(bytes32 create2Salt) internal pure returns (bytes memory) {
        return abi.encode(create2Salt);
    }

    /**
     * @dev Encodes operation data exactly as `OrganizationAccountFactoryBase.setAccountImplementation`.
     */
    function _encodeOperationDataForSetAccountImplementation(address newImplementation)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(newImplementation);
    }

    /**
     * @dev Computes nonce for a `deployAccount` operation.
     */
    function _computeDeployAccountNonce(bytes memory operationData, uint256 salt) internal view returns (uint256) {
        return accountFactoryStateHarness.computeNonce(OperationType.DeployAccount, operationData, salt);
    }

    /**
     * @dev Computes nonce for a `setAccountImplementation` operation.
     */
    function _computeSetAccountImplementationNonce(bytes memory operationData, uint256 salt)
        internal
        view
        returns (uint256)
    {
        return accountFactoryStateHarness.computeNonce(OperationType.UpgradeAccount, operationData, salt);
    }

    /**
     * @dev Deploys the concrete harness for the current account-factory-focused suite.
     */
    function _deployHarness() internal virtual override returns (OrganizationAdminStateHarness);
}
