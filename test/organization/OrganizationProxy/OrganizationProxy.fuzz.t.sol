// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganization} from "interfaces/IOrganization.sol";
import {OrganizationProxy} from "organization/OrganizationProxy.sol";
import {LibOrganizationUpgradeStorage} from "organization/libraries/storage/LibOrganizationUpgradeStorage.sol";
import {InitializationWhitelistMock} from "test/organization/OrganizationFactory/OrganizationFactoryHarnesses.sol";
import {
    InitializationSuiteBase
} from "test/organization/base/OrganizationInitializationBase/OrganizationInitializationBaseSuiteBase.sol";

/**
 * @dev Fuzz tests for `OrganizationProxy`.
 */
contract OrganizationProxyFuzzTest is InitializationSuiteBase {
    /// @dev Verifies the constructor seeds deployer and whitelist storage slots exactly to the constructor inputs.
    /// @param directDeployer Fuzzed direct deployer used for proxy construction.
    /// @param useAlternateWhitelist Fuzzed switch selecting the default whitelist or a second whitelist contract.
    function testFuzz_FOPX_CTOR_29_constructor_seedsDeployerAndWhitelistStorageExactly(
        address directDeployer,
        bool useAlternateWhitelist
    ) public {
        // Setup: choose a non-zero deployer and one of two deployed whitelist contract addresses.
        vm.assume(directDeployer != address(0));
        InitializationWhitelistMock alternateWhitelist = new InitializationWhitelistMock();
        address whitelistAddress = useAlternateWhitelist ? address(alternateWhitelist) : address(whitelist);

        // Call: deploy the proxy directly from the fuzzed deployer and read the constructor-written storage slots.
        vm.prank(directDeployer);
        address proxy = address(new OrganizationProxy(address(implementation), whitelistAddress));
        bytes32 whitelistWord = vm.load(proxy, LibOrganizationUpgradeStorage.STORAGE_LOCATION);
        bytes32 implementationWord = vm.load(proxy, ERC1967_IMPLEMENTATION_SLOT);

        // Verify: the deployer view and whitelist/implementation slots should match the exact constructor inputs.
        assertEq(IOrganization(proxy).getDeployerAddress(), directDeployer, "deployer should match constructor sender");
        assertEq(
            address(uint160(uint256(whitelistWord))),
            whitelistAddress,
            "whitelist slot should match the constructor input"
        );
        assertEq(
            address(uint160(uint256(implementationWord))),
            address(implementation),
            "implementation slot should match the constructor input"
        );
    }
}
