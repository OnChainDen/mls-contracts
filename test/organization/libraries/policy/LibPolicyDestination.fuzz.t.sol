// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {PolicyLibrariesFuzzTestBase} from "test/organization/libraries/policy/PolicyLibrariesFuzzTestBase.sol";
import {Policy} from "types/PolicyTypes.sol";

/**
 * @dev Fuzz tests for `LibPolicyDestination`.
 */
contract LibPolicyDestinationFuzzTest is PolicyLibrariesFuzzTestBase {
    /// @dev Verifies `LibPolicyDestination.isDestinationAllowedByPolicy` accepts only exact custom-list membership.
    /// @param token The token contract used when exercising the ERC-20-transfer branch.
    /// @param allowedDestination The destination included in the merkle tree.
    /// @param siblingDestination The second destination included to force a non-empty proof.
    /// @param disallowedDestination A destination not included in the merkle tree.
    /// @param asTokenTransfer Whether to exercise the ERC-20-transfer destination path.
    /// @param amount The transfer amount encoded into the ERC-20 calldata.
    function testFuzz_FLPD_DEST_65_isDestinationAllowed_customListAcceptsOnlyValidMerkleMembership(
        address token,
        address allowedDestination,
        address siblingDestination,
        address disallowedDestination,
        bool asTokenTransfer,
        uint256 amount
    ) public {
        vm.assume(token != address(0));
        vm.assume(allowedDestination != siblingDestination);
        vm.assume(disallowedDestination != allowedDestination);
        vm.assume(disallowedDestination != siblingDestination);

        // Setup: build a two-leaf destination tree so the valid branch requires an actual proof.
        address[] memory destinations = buildArray(allowedDestination, siblingDestination);
        (bytes32 root, bytes32[] memory validProof) = _buildAddressRootAndProof(destinations, 0);
        (, bytes32[] memory wrongProof) = _buildAddressRootAndProof(destinations, 1);
        Policy memory policy = _customDestinationPolicy(root);

        address allowedTo = asTokenTransfer ? token : allowedDestination;
        address disallowedTo = asTokenTransfer ? token : disallowedDestination;
        uint256 allowedValue = asTokenTransfer ? 0 : 1;
        bytes memory allowedData = asTokenTransfer ? _encodeErc20Transfer(allowedDestination, amount) : bytes("");
        bytes memory disallowedData = asTokenTransfer ? _encodeErc20Transfer(disallowedDestination, amount) : bytes("");

        // Call: evaluate the exact valid proof plus two mutation branches that change the proof or destination.
        bool validAllowed = harness.isDestinationAllowedByPolicyViaPolicyLibrary(
            policy, allowedTo, allowedValue, allowedData, validProof
        );
        bool wrongProofAllowed = harness.isDestinationAllowedByPolicyViaPolicyLibrary(
            policy, allowedTo, allowedValue, allowedData, wrongProof
        );
        bool wrongDestinationAllowed = harness.isDestinationAllowedByPolicyViaPolicyLibrary(
            policy, disallowedTo, allowedValue, disallowedData, validProof
        );

        // Verify: only the exact leaf+proof combination is accepted.
        assertTrue(validAllowed, "valid destination proof should be accepted");
        assertFalse(wrongProofAllowed, "proof for a different destination should fail");
        assertFalse(wrongDestinationAllowed, "changing the actual destination should fail");
    }
}
