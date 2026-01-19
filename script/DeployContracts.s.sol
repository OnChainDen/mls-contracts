// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Script, console} from "forge-std/Script.sol";

/**
 * @title DeployContracts (DEPRECATED)
 * @notice This script is deprecated. Use DeployPlatform.s.sol instead.
 * @dev The new DeployPlatform.s.sol script provides:
 *      - Deterministic CREATE2 deployments across all chains
 *      - Safe infrastructure and multisig deployment
 *      - Proper dependency ordering
 *      - Already-deployed contract detection
 *      - Support for both Arachnid and Safe Singleton Factory
 *
 *      To deploy the platform, run:
 *      ```
 *      forge script script/DeployPlatform.s.sol:DeployPlatform \
 *        --rpc-url $RPC_URL \
 *        --broadcast \
 *        --verify \
 *        -vvvv
 *      ```
 *
 *      See README.md for full deployment documentation.
 *
 * @author Den Technologies Inc
 */
contract DeployContracts is Script {
    function run() external pure {
        revert(
            "This script is deprecated. Use DeployPlatform.s.sol instead. "
            "Run: forge script script/DeployPlatform.s.sol:DeployPlatform --rpc-url $RPC_URL --broadcast"
        );
    }
}
