// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";

import {
    OrganizationSignaturesBaseHarness
} from "test/organization/base/OrganizationSignaturesBase/OrganizationSignaturesBaseHarness.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Unit tests for the external nonce view surface in `OrganizationSignaturesBase`.
 */
contract OrganizationSignaturesBaseTest is Test {
    /// @dev Concrete harness exposing the real `OrganizationSignaturesBase` external functions.
    OrganizationSignaturesBaseHarness internal harness;

    /**
     * @dev Deploys a fresh base-contract harness before each test.
     */
    function setUp() public {
        harness = new OrganizationSignaturesBaseHarness();
    }

    /// @dev Verifies `OrganizationSignaturesBase.computeNonce` matches the direct library formula.
    function test_NMSB_CN_1_computeNonce_matchesDirectLibraryComputation() public view {
        // Setup: define one nonce tuple and the formula-equivalent expected value.
        bytes memory operationData = abi.encode(address(0xA11CE), uint256(31));
        uint256 expected =
            uint256(keccak256(abi.encode(address(harness), OperationType.ModifyAdmins, keccak256(operationData), 31)));

        // Call: compute the nonce through the external base-contract view.
        uint256 actual = harness.computeNonce(OperationType.ModifyAdmins, operationData, 31);

        // Verify: the base-contract wrapper matches the underlying library computation exactly.
        assertEq(actual, expected, "base computeNonce should match direct library formula");
    }

    /// @dev Verifies `OrganizationSignaturesBase.computeNonce` is callable by arbitrary callers.
    function test_NMSB_CN_2_computeNonce_isCallableByAnyCaller() public {
        // Setup: use a non-guardian, non-admin caller and a deterministic payload.
        address arbitraryCaller = address(0xCAFE);
        bytes memory operationData = abi.encode(address(0xBEEF), uint256(32));

        // Call: read the nonce from an arbitrary caller context.
        vm.prank(arbitraryCaller);
        uint256 nonce = harness.computeNonce(OperationType.ModifyMembers, operationData, 32);

        // Verify: arbitrary callers can access the pure/view nonce surface without authorization gates.
        assertEq(
            nonce,
            uint256(keccak256(abi.encode(address(harness), OperationType.ModifyMembers, keccak256(operationData), 32))),
            "arbitrary caller should receive computed nonce"
        );
    }

    /// @dev Verifies `OrganizationSignaturesBase.isNonceUsed` reflects nonce consumption from another flow.
    function test_NMSB_INU_1_isNonceUsed_tracksNonceConsumptionFromAnotherFlow() public {
        // Setup: derive a nonce and confirm it starts unused before another flow consumes it.
        bytes memory operationData = abi.encode(address(0xD00D), uint256(33));
        uint256 nonce = harness.computeNonce(OperationType.ModifyPolicies, operationData, 33);
        assertFalse(harness.isNonceUsed(nonce), "fresh nonce should start unused");

        // Call: consume the nonce through a separate harness entry point that uses the library directly.
        harness.consumeNonceViaLibrary(nonce);

        // Verify: the external view surface reflects the consumed nonce state.
        assertTrue(harness.isNonceUsed(nonce), "used nonce view should observe external consumption");
    }

    /// @dev Verifies `OrganizationSignaturesBase.isNonceUsed` is callable by arbitrary callers.
    function test_NMSB_INU_2_isNonceUsed_isCallableByAnyCaller() public {
        // Setup: seed one nonce as used and query it from a caller with no special role.
        uint256 nonce = 34;
        address arbitraryCaller = address(0xFACE);
        harness.setUsedNonce(nonce, true);

        // Call: read the used flag from an arbitrary caller context.
        vm.prank(arbitraryCaller);
        bool isUsed = harness.isNonceUsed(nonce);

        // Verify: arbitrary callers can access the nonce-status view surface.
        assertTrue(isUsed, "arbitrary caller should observe used nonce status");
    }
}
