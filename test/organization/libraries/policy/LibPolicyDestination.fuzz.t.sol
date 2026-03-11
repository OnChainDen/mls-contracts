// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {PolicyLibrariesFuzzTestBase} from "test/organization/libraries/policy/PolicyLibrariesFuzzTestBase.sol";
import {Policy} from "types/PolicyTypes.sol";

/**
 * @dev Fuzz tests for `LibPolicyDestination`.
 */
contract LibPolicyDestinationFuzzTest is PolicyLibrariesFuzzTestBase {
    /// @dev Verifies `LibPolicyDestination.getActualDestination` uses transfer recipients for ERC-20 transfers and
    /// `to` for non-transfer calls.
    /// @param token The ERC-20 token contract address used for the transfer branch.
    /// @param recipient The transfer recipient encoded into ERC-20 calldata.
    /// @param target The `to` address used for non-transfer branches.
    /// @param amount The transfer amount encoded into the ERC-20 calldata.
    /// @param value The native value used for the non-transfer branch.
    function testFuzz_FLPD_DEST_64_getActualDestination_erc20TransfersUseRecipientAndNonTransfersUseTo(
        address token,
        address recipient,
        address target,
        uint256 amount,
        uint256 value
    ) public view {
        vm.assume(token != address(0));
        vm.assume(target != address(0));

        // Setup: prepare one ERC-20 transfer payload plus native-transfer and contract-interaction fixtures.
        bytes memory transferData = _encodeERC20Transfer(recipient, amount);
        bytes memory approveData = _encodeERC20Approve(recipient, amount);

        // Call: resolve actual destinations for ERC-20 transfer, native transfer, and non-transfer calldata paths.
        address transferDestination = harness.getActualDestinationViaPolicyLibrary(token, transferData, 0);
        address nativeDestination = harness.getActualDestinationViaPolicyLibrary(target, bytes(""), value);
        address contractDestination = harness.getActualDestinationViaPolicyLibrary(target, approveData, 0);

        // Verify: ERC-20 transfer resolves to the recipient while both non-transfer paths resolve to `to`.
        assertEq(transferDestination, recipient, "erc20 transfer should resolve to encoded recipient");
        assertEq(nativeDestination, target, "native transfer should resolve to to-address");
        assertEq(contractDestination, target, "non-transfer calldata should resolve to to-address");
    }

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
        bytes memory allowedData = asTokenTransfer ? _encodeERC20Transfer(allowedDestination, amount) : bytes("");
        bytes memory disallowedData = asTokenTransfer ? _encodeERC20Transfer(disallowedDestination, amount) : bytes("");

        // Call: evaluate the exact valid proof plus two mutation branches that change the proof or destination.
        bool validAllowed =
            harness.isDestinationAllowedByPolicyViaPolicyLibrary(policy, allowedTo, allowedValue, allowedData, validProof);
        bool wrongProofAllowed =
            harness.isDestinationAllowedByPolicyViaPolicyLibrary(policy, allowedTo, allowedValue, allowedData, wrongProof);
        bool wrongDestinationAllowed = harness.isDestinationAllowedByPolicyViaPolicyLibrary(
            policy, disallowedTo, allowedValue, disallowedData, validProof
        );

        // Verify: only the exact leaf+proof combination is accepted.
        assertTrue(validAllowed, "valid destination proof should be accepted");
        assertFalse(wrongProofAllowed, "proof for a different destination should fail");
        assertFalse(wrongDestinationAllowed, "changing the actual destination should fail");
    }
}
