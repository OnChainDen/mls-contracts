// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Vm, VmSafe} from "forge-std/Vm.sol";

import {Logger} from "script/libraries/Logger.sol";

/**
 * @title ScriptUtils
 * @dev Helpers for Foundry deployment scripts.
 */
library ScriptUtils {
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
            string memory response = vm.prompt("Type 'yes' to continue with deployment: ");

            // Trim the response to remove any whitespace
            string memory trimmedResponse = vm.trim(response);

            // Check if the response is "yes"
            require(Strings.equal(trimmedResponse, "yes"), "Deployment cancelled");

            Logger.logEmptyLine();
        } else {
            // Case: the script is being run with the --dry-run flag
            // Log that we're in dry run mode
            Logger.logInfo("DRY RUN MODE - No transactions will be broadcast");
            Logger.logEmptyLine();
        }
    }
}
