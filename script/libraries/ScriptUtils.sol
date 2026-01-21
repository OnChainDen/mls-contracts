// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Vm, VmSafe} from "forge-std/Vm.sol";

import {DeploymentConfig} from "script/config/DeploymentConfig.sol";
import {Logger} from "script/libraries/Logger.sol";

/**
 * @title ScriptUtils
 * @dev Helpers for Foundry deployment scripts.
 */
library ScriptUtils {
    /**
     * @dev Prompts the user for confirmation and reverts if they don't type "yes".
     * @param vm The Foundry Vm cheatcode instance
     */
    function promptForConfirmationOrRevert(Vm vm) internal {
        string memory response = vm.prompt("Type 'yes' to continue: ");
        string memory trimmedResponse = vm.trim(response);
        require(Strings.equal(trimmedResponse, "yes"), "Confirmation not received");
    }

    /**
     * @dev Logs the execution mode (broadcast or dry run) and prompts the user for confirmation
     *      when broadcasting.
     * @param vm The Foundry Vm cheatcode instance
     * @param scriptName Human-readable script name for logging
     */
    function confirmBroadcastOrDryRun(Vm vm, string memory scriptName) internal {
        // Case: the script is being run with the --broadcast flag
        // Log the broadcast mode and prompt for confirmation
        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            // Log the broadcast mode
            Logger.logWarn("BROADCAST MODE DETECTED");

            // Log the script name
            Logger.logIndented(string.concat("Script: ", scriptName));

            // Log the transaction will be sent to the network
            Logger.logIndented("Transactions WILL be sent to the network.");
            Logger.logEmptyLine();

            // Prompt the user for confirmation
            promptForConfirmationOrRevert(vm);

            Logger.logEmptyLine();
        } else {
            // Case: the script is being run with the --dry-run flag
            // Log that we're in dry run mode
            Logger.logInfo("DRY RUN MODE - No transactions will be broadcast");
            Logger.logEmptyLine();
        }
    }

    /**
     * @dev Logs whether a production chain is detected and prompts for confirmation if so.
     * @param vm The Foundry Vm cheatcode instance
     * @param scriptName Human-readable script name for logging
     */
    function warnAndConfirmIfProductionChain(Vm vm, string memory scriptName) internal {
        // Determine if the chain is a production chain
        bool isProductionChain = DeploymentConfig.isProductionChain(block.chainid);

        // Warn the user if the chain is a production chain
        if (isProductionChain) {
            Logger.logWarn("PRODUCTION CHAIN DETECTED");
        } else {
            Logger.logInfo("NON-PRODUCTION CHAIN DETECTED");
        }

        // Log the script name and chain ID
        Logger.logKeyValue("Script", scriptName);
        Logger.logKeyUint("Chain ID", block.chainid);
        Logger.logEmptyLine();

        // Case: the chain is a production chain
        // Prompt for confirmation if the chain is a production chain
        if (isProductionChain) {
            promptForConfirmationOrRevert(vm);
            Logger.logEmptyLine();
        }
    }
}
