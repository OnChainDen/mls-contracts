// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";
import {OrganizationImplementationHarness} from "test/organization/shared/OrganizationUpgradeHarnesses.sol";
import {
    OrganizationImplementationSuiteBase
} from "test/organization/OrganizationImplementation/OrganizationImplementationSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

interface IUUPSOrgEntrypoints {
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;
}

interface IVersionedAccount {
    function version() external view returns (uint256);
}

contract AccountImplementationVersion1 {
    function version() external pure returns (uint256) {
        return 1;
    }
}

contract AccountImplementationVersion2 {
    function version() external pure returns (uint256) {
        return 2;
    }
}

/**
 * @dev Shared setup/helpers for cross-file organization upgrade integration suites.
 */
abstract contract OrganizationUpgradesCrossFileSuiteBase is OrganizationImplementationSuiteBase {
    function _deployAndConfigureSecondOrganizationProxy() internal returns (OrganizationImplementationHarness proxyB) {
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementationV1), bytes(""));
        proxyB = OrganizationImplementationHarness(payable(address(proxy)));

        proxyB.setGuardian(GUARDIAN);
        proxyB.setUpgradeState(address(whitelist), address(0));
        proxyB.setMemberStatus(admin1, true);
        proxyB.setAdminStatus(admin1, true);
        proxyB.setAdminCount(1);
        proxyB.setVotingThreshold(1);
    }

    function _buildAuthForOrganization(
        address organization,
        OperationType operationType,
        bytes memory operationData,
        bool isApproval,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256[] memory privateKeys
    ) internal view returns (AdminAuthParams memory auth, bytes memory builtOperationData) {
        builtOperationData = operationData;
        bytes32 operationHash = OrganizationAdminStateHarness(organization).getAdminOperationHash(
            operationType, operationData, salt, expirationTimestamp, isApproval
        );
        bytes memory signatures = _buildSortedEOASignatures(operationHash, privateKeys);
        auth = AdminAuthParams({salt: salt, expirationTimestamp: expirationTimestamp, signatures: signatures});
    }
}
