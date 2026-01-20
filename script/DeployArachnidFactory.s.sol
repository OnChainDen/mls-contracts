// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Script, console} from "forge-std/Script.sol";

import {DeploymentConfig} from "script/config/DeploymentConfig.sol";
import {Create2Deployer} from "script/libraries/Create2Deployer.sol";

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
 *      3. Requires explicit CONFIRM_DEPLOYMENT=true environment variable
 *      4. Runs in dry-run mode by default
 *
 *      Reference: https://github.com/Arachnid/deterministic-deployment-proxy
 *
 * @author Den Technologies Inc
 */
contract DeployArachnidFactory is Script {
    /// @dev Expected factory address after deployment (deterministic via keyless CREATE)
    address internal constant _EXPECTED_FACTORY_ADDRESS = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// @dev Deployer address that will deploy the factory (derived from pre-signed tx)
    address internal constant _EXPECTED_DEPLOYER = 0x3fab184622dc19b6109349b94811493bf2a45362;

    /// @dev Gas price used in the pre-signed transaction (100 gwei)
    uint256 internal constant _DEPLOYMENT_GAS_PRICE = 100_000_000_000;

    /// @dev Gas limit used in the pre-signed transaction
    uint256 internal constant _DEPLOYMENT_GAS_LIMIT = 100_000;

    /// @dev Required ETH balance for the deployer (gas price * gas limit with 50% buffer)
    uint256 internal constant _REQUIRED_ETH_BALANCE = (_DEPLOYMENT_GAS_PRICE * _DEPLOYMENT_GAS_LIMIT * 3) / 2;

    /// @dev Custom error for when safety checks fail
    error SafetyChecksFailed();

    /// @dev Custom error for when factory deployment fails
    error FactoryDeploymentFailed();

    /// @dev Custom error for when the raw transaction broadcast fails
    error RawTransactionBroadcastFailed();

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
    bytes internal constant _PRESIGNED_TX = hex"f8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222";

    /**
     * @notice Main entry point for the deployment script
     * @dev Runs comprehensive safety checks before allowing deployment
     */
    function run() external {
        console.log("");
        console.log("================================================================================");
        console.log("  Arachnid Deterministic Deployment Proxy - Factory Deployment");
        console.log("================================================================================");
        console.log("");

        // Check if deployment is confirmed
        bool confirmDeployment = vm.envOr("CONFIRM_DEPLOYMENT", false);

        // Run all safety checks
        bool allChecksPassed = _runSafetyChecks();

        if (!allChecksPassed) {
            console.log("");
            console.log(unicode"  ❌ SAFETY CHECKS FAILED - Deployment aborted");
            console.log("");
            revert SafetyChecksFailed();
        }

        if (!confirmDeployment) {
            console.log("");
            console.log("--------------------------------------------------------------------------------");
            console.log("  DRY RUN MODE");
            console.log("--------------------------------------------------------------------------------");
            console.log("");
            console.log("  All safety checks passed. To deploy, run with:");
            console.log("");
            console.log("    CONFIRM_DEPLOYMENT=true forge script DeployArachnidFactory ...");
            console.log("");
            console.log("  NOTE: This broadcasts a pre-signed transaction. Some chains that enforce");
            console.log("  EIP-155 may reject this transaction. If deployment fails, use");
            console.log("  DeploySafeSingletonFactory.s.sol instead.");
            console.log("");
            return;
        }

        console.log("");
        console.log("--------------------------------------------------------------------------------");
        console.log("  DEPLOYING ARACHNID FACTORY");
        console.log("--------------------------------------------------------------------------------");
        console.log("");

        // Broadcast the pre-signed transaction
        _broadcastPresignedTransaction();

        // Verify deployment
        if (!Create2Deployer.isContractDeployedAtAddress(_EXPECTED_FACTORY_ADDRESS)) {
            console.log(unicode"  ❌ ERROR: Factory deployment failed!");
            console.log("     This chain may enforce EIP-155 replay protection.");
            console.log("     Use DeploySafeSingletonFactory.s.sol instead.");
            revert FactoryDeploymentFailed();
        }

        console.log("");
        console.log(unicode"  ✅ Arachnid Factory deployed successfully!");
        console.log("     Address: %s", _EXPECTED_FACTORY_ADDRESS);
        console.log("");
        console.log("  Next step: Set the factory address in your environment:");
        console.log("    export CREATE2_FACTORY_ADDRESS=%s", _EXPECTED_FACTORY_ADDRESS);
        console.log("");
    }

    /// @notice Funds the Arachnid factory deployer address with ETH
    /// @dev Can be called separately to fund the deployer before running the main script.
    ///      Requires PRIVATE_KEY environment variable to be set for the funding account.
    function fundDeployer() external {
        uint256 fundingPrivateKey = vm.envUint("PRIVATE_KEY");

        console.log("");
        console.log("  Funding Arachnid factory deployer...");
        console.log("  Target: %s", _EXPECTED_DEPLOYER);
        console.log("  Amount: %s wei (~%s ETH)", _REQUIRED_ETH_BALANCE, _REQUIRED_ETH_BALANCE / 1 ether);
        console.log("");

        vm.startBroadcast(fundingPrivateKey);
        payable(_EXPECTED_DEPLOYER).transfer(_REQUIRED_ETH_BALANCE);
        vm.stopBroadcast();

        console.log(unicode"  ✅ Deployer funded successfully");
    }

    /// @dev Broadcasts the pre-signed transaction to deploy the factory
    function _broadcastPresignedTransaction() internal {
        console.log("  Broadcasting pre-signed transaction...");
        console.log("  Deployer: %s", _EXPECTED_DEPLOYER);
        console.log("  Expected factory address: %s", _EXPECTED_FACTORY_ADDRESS);
        console.log("");

        // Use Foundry's vm.broadcastRawTransaction to broadcast the pre-signed tx
        vm.broadcastRawTransaction(_PRESIGNED_TX);
    }

    /// @dev Runs all safety checks before deployment
    ///      Checks: factory not deployed, deployer has sufficient ETH
    /// @return passed True if all critical checks pass
    function _runSafetyChecks() internal view returns (bool passed) {
        console.log("  Running safety checks...");
        console.log("");

        bool allPassed = true;

        // Check 1: Factory not already deployed
        console.log("  [1/2] Checking if factory already deployed...");
        if (Create2Deployer.isContractDeployedAtAddress(_EXPECTED_FACTORY_ADDRESS)) {
            console.log(unicode"       ⏭️  INFO: Factory already deployed at %s", _EXPECTED_FACTORY_ADDRESS);
            console.log("              No deployment needed. Set CREATE2_FACTORY_ADDRESS to use it.");
            // This is not a failure - the factory exists, which is the goal
            // Return early with success since there's nothing to deploy
            return true;
        } else {
            console.log(unicode"       ✅ PASS: Factory not yet deployed");
        }

        // Check 2: Deployer has sufficient ETH
        console.log("  [2/2] Checking deployer ETH balance...");
        uint256 balance = _EXPECTED_DEPLOYER.balance;
        if (balance >= _REQUIRED_ETH_BALANCE) {
            console.log(unicode"       ✅ PASS: Deployer has sufficient ETH (%s wei)", balance);
        } else {
            console.log(unicode"       ❌ FAIL: Deployer needs more ETH");
            console.log("              Current: %s wei", balance);
            console.log("              Required: %s wei (~0.015 ETH)", _REQUIRED_ETH_BALANCE);
            console.log("");
            console.log("              Fund the deployer by running:");
            console.log("                forge script DeployArachnidFactory --sig \"fundDeployer()\" \\");
            console.log("                  --rpc-url $RPC_URL --broadcast");
            allPassed = false;
        }

        return allPassed;
    }
}
