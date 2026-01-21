// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Script} from "forge-std/Script.sol";

import {DeploymentConfig} from "script/config/DeploymentConfig.sol";
import {Create2Utils} from "script/libraries/Create2Utils.sol";
import {Logger} from "script/libraries/Logger.sol";
import {ScriptUtils} from "script/libraries/ScriptUtils.sol";

/**
 * @title DeployArachnidFactory
 * @notice Script to deploy the Arachnid Deterministic Deployment Proxy on chains where it doesn't exist
 * @dev This script broadcasts a pre-signed transaction that deploys the Arachnid factory.
 *
 *      The Arachnid factory uses a keyless deployment mechanism - a pre-signed transaction
 *      without EIP-155 replay protection. This allows the same transaction to be broadcast
 *      on any EVM chain, resulting in the factory being deployed at the same address.
 *
 *      IMPORTANT: Some chains enforce EIP-155 and will reject this transaction. In those cases,
 *      use DeploySafeSingletonFactory.s.sol instead.
 *
 *      SAFETY CHECKS:
 *      1. Verifies factory is not already deployed
 *      2. Verifies deployer address has sufficient ETH
 *      3. Requires interactive confirmation when broadcasting
 *      4. Logs dry-run mode when not broadcasting
 *
 *      Reference: https://github.com/Arachnid/deterministic-deployment-proxy
 *
 * @author Den Technologies Inc
 */
contract DeployArachnidFactory is Script {
    /// @dev Expected factory address after deployment (deterministic via keyless CREATE)
    address internal constant _EXPECTED_FACTORY_ADDRESS = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// @dev Deployer address that will deploy the factory (derived from pre-signed tx)
    address internal constant _EXPECTED_DEPLOYER_ADDRESS = 0x3fAB184622Dc19b6109349B94811493BF2a45362;

    /// @dev Gas price used in the pre-signed transaction (100 gwei)
    uint256 internal constant _DEPLOYMENT_GAS_PRICE = 100_000_000_000;

    /// @dev Gas limit used in the pre-signed transaction
    uint256 internal constant _DEPLOYMENT_GAS_LIMIT = 100_000;

    /// @dev Required ETH balance for the deployer (gas price * gas limit with 50% buffer)
    uint256 internal constant _REQUIRED_ETH_BALANCE = (_DEPLOYMENT_GAS_PRICE * _DEPLOYMENT_GAS_LIMIT * 3) / 2;

    /**
     * @notice Pre-signed transaction for deploying the Arachnid factory
     * @dev This transaction is signed without EIP-155 replay protection, allowing it to be
     *      broadcast on any EVM-compatible chain. The signature uses v=27 and r=s=0x2222...
     *
     *      Transaction details:
     *      - nonce: 0
     *      - gasPrice: 100 gwei (0x174876e800)
     *      - gasLimit: 100000 (0x0186a0)
     *      - to: (empty - contract creation)
     *      - value: 0
     *      - data: Factory bytecode
     *
     *      Source: https://github.com/Arachnid/deterministic-deployment-proxy
     */
    // forgefmt: disable-next-item
    // solhint-disable-next-line max-line-length
    bytes internal constant _PRESIGNED_TX = hex"f8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222";

    /**
     * @notice Main entry point for the deployment script
     * @dev Runs comprehensive safety checks before allowing deployment
     */
    function run() external {
        // Prompt for confirmation when running with --broadcast
        ScriptUtils.confirmBroadcastOrDryRun(vm, "DeployArachnidFactory");

        // Log the deployment header
        Logger.logBoxHeader("Arachnid Deterministic Deployment Proxy - Factory Deployment");

        // Validate that the Arachnid factory is not already deployed
        Create2Utils.validateFactoryNotDeployedOrRevert(
            DeploymentConfig.ARACHNID_CREATE2_FACTORY_ADDRESS, "Arachnid factory"
        );

        // Validate that the deployer has sufficient ETH balance
        Create2Utils.validateDeployerHasSufficientEthOrRevert(
            _EXPECTED_DEPLOYER_ADDRESS, _REQUIRED_ETH_BALANCE, "DeployArachnidFactory"
        );

        // Log section header
        Logger.logSection("DEPLOYING ARACHNID FACTORY");

        // Broadcast the pre-signed transaction that deploys the factory
        _broadcastPresignedTransaction();

        // Verify deployment
        if (!Create2Utils.isContractDeployedAtAddress(_EXPECTED_FACTORY_ADDRESS)) {
            Logger.logFail("ERROR: Factory deployment failed!");
            Logger.logIndented("This chain may enforce EIP-155 replay protection.");
            Logger.logIndented("Use DeploySafeSingletonFactory.s.sol instead.");
            revert("Factory deployment failed");
        }

        // Log success
        Logger.logDeploymentSuccess("Arachnid Factory", _EXPECTED_FACTORY_ADDRESS, "CREATE2_FACTORY_ADDRESS");
    }

    /// @notice Funds the Arachnid factory deployer address with ETH
    /// @dev Can be called separately to fund the deployer before running the main script.
    ///      Requires PRIVATE_KEY environment variable to be set for the funding account.
    function fundDeployer() external {
        // Log the funding details
        Logger.logEmptyLine();
        Logger.logIndented("Funding Arachnid factory deployer...");
        Logger.logKeyAddress("Target", _EXPECTED_DEPLOYER_ADDRESS);
        Logger.logKeyUint("Amount (wei)", _REQUIRED_ETH_BALANCE);
        Logger.logEmptyLine();

        // Get the private key for the account that will fund the deployer
        uint256 fundingPrivateKey = vm.envUint("PRIVATE_KEY");

        // Fund the deployer
        vm.startBroadcast(fundingPrivateKey);
        payable(_EXPECTED_DEPLOYER_ADDRESS).transfer(_REQUIRED_ETH_BALANCE);
        vm.stopBroadcast();

        // Log success
        Logger.logPass("Deployer funded successfully");
    }

    /// @dev Broadcasts the pre-signed transaction to deploy the factory
    function _broadcastPresignedTransaction() internal {
        // Log the broadcasting details
        Logger.logIndented("Broadcasting pre-signed transaction...");
        Logger.logKeyAddress("Deployer", _EXPECTED_DEPLOYER_ADDRESS);
        Logger.logKeyAddress("Expected factory address", _EXPECTED_FACTORY_ADDRESS);
        Logger.logEmptyLine();

        // Broadcast the pre-signed transaction that deploys the factory
        vm.broadcastRawTransaction(_PRESIGNED_TX);
    }
}
