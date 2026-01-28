// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {BatchedTransaction} from "../../src/safe-module/BatchedTransaction.sol";
import {BaseDeployScript} from "script/BaseDeployScript.sol";
import {Create2Utils} from "script/libraries/Create2Utils.sol";
import {Logger} from "script/libraries/Logger.sol";

/**
 * @title DeployBatchedTransaction
 * @notice Deploys the BatchedTransaction contract via CREATE2
 * @dev This script deploys a security-focused batched transaction contract that provides:
 *      - No ETH transfers (value is hardcoded to 0 in encoding)
 *      - address(this) validation (blocks calls to the Safe when delegatecalled, since
 *        address(this) is the Safe's address during delegatecall)
 *      - Efficient transaction encoding (28 bytes header per tx: 20 address + 8 dataLength,
 *        plus N bytes of calldata)
 *
 *      Usage:
 *        forge script script/safe-module/DeployBatchedTransaction.s.sol:DeployBatchedTransaction \
 *          --sig "run(address)" <FACTORY_ADDRESS> \
 *          --rpc-url $RPC_URL \
 *          --broadcast \
 *          -vvvv
 *
 *      Where:
 *        - FACTORY_ADDRESS: The CREATE2 factory to use (Arachnid or Den Singleton Factory)
 *
 *      SAFETY CHECKS:
 *      1. Verifies the provided CREATE2 factory is a known factory from deployment.toml
 *      2. Verifies the provided CREATE2 factory is deployed
 *      3. Verifies the deployer is not the production Den Factory deployer
 *      4. Requires interactive confirmation when broadcasting
 *
 * @author Den Technologies Inc
 */
contract DeployBatchedTransaction is BaseDeployScript {
    /**
     * @notice Main entry point - deploys BatchedTransaction via CREATE2
     * @param factoryAddress Address of the CREATE2 factory to use for deployment
     */
    function run(address factoryAddress) external {
        // Common deployment initialization (factory validation, confirmations, header logging)
        validateAndInitializeDeploymentOrRevert(factoryAddress, "DeployBatchedTransaction");

        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy BatchedTransaction
        address batchedTransactionAddress = _deploy();

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Log the result
        Logger.logBoxHeader(unicode"✅ Deployed Address");
        Logger.logKeyValue("BatchedTransaction", batchedTransactionAddress);
        Logger.logBoxFooter();
    }

    /**
     * @notice Compute and print BatchedTransaction address without deploying
     * @dev Does not require RPC connection.
     * @param factoryAddress Address of the CREATE2 factory to use for address computation
     */
    function computeAddress(address factoryAddress) external pure {
        // Validate the provided CREATE2 factory address
        require(factoryAddress != address(0), "Factory address cannot be zero");

        // Compute the address
        bytes memory initCode = type(BatchedTransaction).creationCode;
        bytes32 salt = BATCHED_TRANSACTION_SALT;
        address expectedAddress = Create2Utils.computeAddress(factoryAddress, salt, initCode);

        // Log the computed address
        Logger.logBoxHeader("Computed BatchedTransaction Address");
        Logger.logKeyValue("CREATE2 Factory", factoryAddress);
        Logger.logEmptyLine();
        Logger.logKeyValue("BatchedTransaction", expectedAddress);
        Logger.logBoxFooter();
    }

    /// @dev Deploys BatchedTransaction via CREATE2
    /// @return batchedTransactionAddress The deployed contract address
    function _deploy() internal returns (address batchedTransactionAddress) {
        bytes32 salt = BATCHED_TRANSACTION_SALT;
        bytes memory initCode = type(BatchedTransaction).creationCode;

        Logger.logSection("BatchedTransaction (CREATE2)");

        (batchedTransactionAddress,) =
            Create2Utils.deployIfNotExists(_factoryAddress, salt, initCode, "BatchedTransaction");

        return batchedTransactionAddress;
    }
}
