// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {TokenTransferUtils} from "libraries/TokenTransferUtils.sol";
import {PolicyLibrariesFuzzTestBase} from "test/organization/libraries/policy/PolicyLibrariesFuzzTestBase.sol";
import {DestinationType, Policy} from "types/PolicyTypes.sol";

/**
 * @dev Fuzz tests for `LibPolicyTokenTransfer`.
 */
contract LibPolicyTokenTransferFuzzTest is PolicyLibrariesFuzzTestBase {
    /// @dev Verifies `LibPolicyTokenTransfer._isTokenAmountAllowedByPolicy` treats the threshold as an inclusive cap.
    /// @param threshold The configured threshold and tested transfer amount.
    /// @param recipient The ERC-20 recipient used in the token-transfer branch.
    /// @param useNativeTransfer Whether to exercise the native-transfer amount path.
    function testFuzz_FLPT_AMOUNT_67_isTokenAmountAllowed_treatsThresholdAsInclusiveUpperBound(
        uint256 threshold,
        address recipient,
        bool useNativeTransfer
    ) public view {
        // Setup: configure an amount-threshold policy and set the tested transfer amount exactly at the threshold.
        Policy memory policy = _buildBasePolicy();
        policy.config.token.hasAmountThreshold = true;
        policy.config.token.amountThreshold = threshold;

        bytes memory data = useNativeTransfer ? bytes("") : _encodeERC20Transfer(recipient, threshold);
        uint256 value = useNativeTransfer ? threshold : 0;

        // Call: evaluate the exact-threshold transfer amount.
        bool allowed = harness.isTokenAmountAllowedByPolicyViaPolicyLibrary(policy, data, value);

        // Verify: exact-threshold transfers should be accepted under inclusive-threshold semantics.
        assertTrue(allowed, "threshold equality should be accepted");
    }

    /// @dev Verifies `LibPolicyTokenTransfer.isTokenTransferAllowedByPolicy` never lets malformed short transfer
    /// calldata bypass token checks.
    /// @param token The configured token contract used by the exact-token policy.
    /// @param rawShortLength The malformed calldata length, bounded below the 68-byte ERC-20 transfer minimum.
    function testFuzz_FLPT_ALLOW_68_isTokenTransferAllowed_malformedTokenCalldataCannotBypassChecks(
        address token,
        uint8 rawShortLength
    ) public {
        vm.assume(token != address(0));
        uint256 shortLength = bound(uint256(rawShortLength), 4, 67);

        // Setup: configure an exact-token policy with amount checking enabled and craft selector-prefixed short
        // calldata.
        Policy memory policy = _buildBasePolicy();
        policy.config.token.anyToken = false;
        policy.config.token.tokenAddress = token;
        policy.config.token.hasAmountThreshold = true;
        policy.config.token.amountThreshold = 1;
        policy.config.destinationType = DestinationType.Any;

        bytes memory malformedData = bytes.concat(IERC20.transfer.selector, new bytes(shortLength - 4));

        // Call: evaluate the malformed transfer payload, expecting the token parser to fail closed.
        vm.expectRevert(TokenTransferUtils.MalformedTokenTransfer.selector);
        harness.isTokenTransferAllowedByPolicyViaPolicyLibrary(policy, token, 0, malformedData, new bytes32[](0));
    }
}
