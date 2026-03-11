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
    /// @dev Verifies `LibPolicyTokenTransfer._isTokenAllowedByPolicy` enforces `anyToken` and exact token matches.
    /// @param configuredToken The configured ERC-20 token allowed by the exact-token branch.
    /// @param otherToken A different ERC-20 token used for the negative branch.
    /// @param recipient The transfer recipient encoded into calldata.
    /// @param amount The encoded token-transfer amount.
    function testFuzz_FLPT_TOKEN_66_isTokenAllowed_enforcesAnyTokenAndExactConfiguredToken(
        address configuredToken,
        address otherToken,
        address recipient,
        uint256 amount
    ) public view {
        vm.assume(configuredToken != address(0));
        vm.assume(otherToken != address(0));
        vm.assume(configuredToken != otherToken);

        // Setup: prepare one permissive policy and one exact-token policy against two different ERC-20 contracts.
        Policy memory anyTokenPolicy = _buildBasePolicy();
        anyTokenPolicy.config.token.anyToken = true;

        Policy memory exactTokenPolicy = _buildBasePolicy();
        exactTokenPolicy.config.token.anyToken = false;
        exactTokenPolicy.config.token.tokenAddress = configuredToken;

        bytes memory configuredTransfer = _encodeERC20Transfer(recipient, amount);

        // Call: evaluate both policies against the configured token, another token, and native-transfer identity.
        bool anyTokenConfigured =
            harness.isTokenAllowedByPolicyViaPolicyLibrary(anyTokenPolicy, configuredToken, configuredTransfer);
        bool anyTokenOther = harness.isTokenAllowedByPolicyViaPolicyLibrary(anyTokenPolicy, otherToken, configuredTransfer);
        bool exactConfigured =
            harness.isTokenAllowedByPolicyViaPolicyLibrary(exactTokenPolicy, configuredToken, configuredTransfer);
        bool exactOther = harness.isTokenAllowedByPolicyViaPolicyLibrary(exactTokenPolicy, otherToken, configuredTransfer);
        bool exactNative = harness.isTokenAllowedByPolicyViaPolicyLibrary(exactTokenPolicy, recipient, bytes(""));

        // Verify: `anyToken` bypasses token filtering while exact-token mode accepts only the configured token.
        assertTrue(anyTokenConfigured, "anyToken should allow the configured token");
        assertTrue(anyTokenOther, "anyToken should allow other tokens");
        assertTrue(exactConfigured, "configured token should pass exact-token filtering");
        assertFalse(exactOther, "other tokens should fail exact-token filtering");
        assertFalse(exactNative, "native transfers should fail under exact ERC-20 filtering");
    }

    /// @dev Verifies `LibPolicyTokenTransfer._isTokenAllowedByPolicy` treats `address(0)` as the native-token
    /// identity.
    /// @param recipient The native recipient used in the positive branch.
    /// @param token The ERC-20 token contract used in the negative branch.
    /// @param amount The ERC-20 transfer amount used in the negative branch.
    function testFuzz_FLPT_TOKEN_66_isTokenAllowed_nativeIdentityMatchesOnlyNative(
        address recipient,
        address token,
        uint256 amount
    ) public view {
        vm.assume(token != address(0));

        // Setup: configure an exact native-token policy and one ERC-20 transfer fixture.
        Policy memory nativeOnlyPolicy = _buildBasePolicy();
        nativeOnlyPolicy.config.token.anyToken = false;
        nativeOnlyPolicy.config.token.tokenAddress = address(0);

        // Call: evaluate the native branch and an ERC-20 branch against the same policy.
        bool nativeAllowed = harness.isTokenAllowedByPolicyViaPolicyLibrary(nativeOnlyPolicy, recipient, bytes(""));
        bool erc20Allowed =
            harness.isTokenAllowedByPolicyViaPolicyLibrary(nativeOnlyPolicy, token, _encodeERC20Transfer(recipient, amount));

        // Verify: native identity matches only the empty-calldata path.
        assertTrue(nativeAllowed, "native transfers should map to address(0)");
        assertFalse(erc20Allowed, "erc20 transfers should not match native-token identity");
    }

    /// @dev Verifies `LibPolicyTokenTransfer._isTokenAmountAllowedByPolicy` should treat the threshold as inclusive.
    /// @param threshold The configured threshold and tested transfer amount.
    /// @param recipient The ERC-20 recipient used in the token-transfer branch.
    /// @param useNativeTransfer Whether to exercise the native-transfer amount path.
    function testFuzz_FLPT_AMOUNT_67_isTokenAmountAllowed_treatsThresholdAsInclusiveDesiredBehavior(
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

        // Verify: exact-threshold transfers should be accepted under the desired inclusive semantics.
        assertTrue(allowed, "threshold equality should be allowed");
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

        // Setup: configure an exact-token policy with amount checking enabled and craft selector-prefixed short calldata.
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
