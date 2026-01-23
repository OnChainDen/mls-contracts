// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ISafe} from "@safe/interfaces/ISafe.sol";
import {SafeProxyFactory} from "@safe/proxies/SafeProxyFactory.sol";

import {Create2Utils} from "script/libraries/Create2Utils.sol";
import {Logger} from "script/libraries/Logger.sol";
import {SafeInfrastructure} from "script/libraries/Types.sol";

/**
 * @title SafeMultisigUtils
 * @notice Helper library for Safe multisig deployment and configuration in deployment scripts
 * @dev Contains utilities for deploying and validating Safe multisig wallets
 * @author Den Technologies Inc
 */
library SafeMultisigUtils {
    /// @dev Deploys a Safe multisig wallet using SafeProxyFactory
    /// @param safeInfra Safe infrastructure addresses needed for Safe deployment
    /// @param ownerAddresses Array of owner addresses for the Safe
    /// @param threshold Required number of signatures for transactions
    /// @param salt Salt used for deterministic address computation
    /// @param name Human-readable name for logging purposes
    /// @return safeAddress Address of the deployed Safe proxy
    function deploySafeMultisig(
        SafeInfrastructure memory safeInfra,
        address[] memory ownerAddresses,
        uint256 threshold,
        bytes32 salt,
        string memory name
    ) internal returns (address safeAddress) {
        // Encode the initializer for Safe.setup()
        bytes memory initializer = abi.encodeCall(
            ISafe.setup,
            (
                // owners
                ownerAddresses,
                // threshold
                threshold,
                // to - no delegate call
                address(0),
                // data - no delegate call data
                "",
                // fallbackHandler
                safeInfra.fallbackHandlerAddress,
                // paymentToken - ETH
                address(0),
                // payment - no payment
                0,
                // paymentReceiver
                payable(address(0))
            )
        );

        // Compute the salt nonce
        uint256 saltNonce = uint256(salt);

        // Compute expected address using SafeProxyFactory's CREATE2 formula
        safeAddress = _computeSafeProxyAddress(safeInfra, initializer, saltNonce);

        // Check if already deployed
        if (Create2Utils.isContractDeployedAtAddress(safeAddress)) {
            Logger.logDeploymentSkipped(name, safeAddress);
            return safeAddress;
        }

        // Deploy the Safe
        address deployedAtAddress = address(
            SafeProxyFactory(safeInfra.proxyFactoryAddress)
                .createProxyWithNonce(safeInfra.singletonAddress, initializer, saltNonce)
        );
        Logger.logDeployed(name, deployedAtAddress);

        // Verify deployment matches expected address
        require(deployedAtAddress == safeAddress, "Safe deployed at unexpected address");
    }

    /// @dev Computes the deterministic address of a Safe proxy before deployment
    /// @param safeInfra Safe infrastructure addresses needed for address computation
    /// @param initializer Encoded Safe.setup() call data
    /// @param saltNonce Nonce used for salt computation
    /// @return The predicted Safe proxy address
    function _computeSafeProxyAddress(SafeInfrastructure memory safeInfra, bytes memory initializer, uint256 saltNonce)
        private
        view
        returns (address)
    {
        // SafeProxyFactory computes salt as: keccak256(abi.encodePacked(keccak256(initializer), saltNonce))
        bytes32 salt = keccak256(abi.encodePacked(keccak256(initializer), saltNonce));

        // Compute init code hash: proxyCreationCode + singleton address (as uint256)
        // This matches SafeProxyFactory.deployProxy() which does:
        // bytes memory deploymentData = abi.encodePacked(type(SafeProxy).creationCode, uint256(uint160(_singleton)));
        bytes memory proxyCreationCode = SafeProxyFactory(safeInfra.proxyFactoryAddress).proxyCreationCode();
        bytes32 initCodeHash =
            keccak256(abi.encodePacked(proxyCreationCode, uint256(uint160(safeInfra.singletonAddress))));

        // Use OpenZeppelin's Create2 utility for address computation
        return Create2.computeAddress(salt, initCodeHash, safeInfra.proxyFactoryAddress);
    }
}
