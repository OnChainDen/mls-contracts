// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IImplementationWhitelist} from "interfaces/IImplementationWhitelist.sol";
import {BaseDeployScript} from "script/base/BaseDeployScript.sol";
import {Create2Utils} from "script/libraries/Create2Utils.sol";
import {ISafe} from "script/libraries/ISafe.sol";
import {Logger} from "script/libraries/Logger.sol";
import {SafeTransactionUtils} from "script/libraries/SafeTransactionUtils.sol";
import {StringUtils} from "script/libraries/StringUtils.sol";
import {ContractType} from "types/CommonTypes.sol";

/// @notice Minimal interface for the Safe MultiSendCallOnly v1.4.1 contract
/// @dev Used to batch multiple whitelist calls into a single atomic Admin Safe transaction.
///      MultiSendCallOnly only permits Call sub-transactions (no DELEGATECALL), which is exactly
///      what we need (each sub-transaction is a plain call to the whitelist proxy).
interface IMultiSendCallOnly {
    function multiSend(bytes memory transactions) external payable;
}

/**
 * @title ManageImplementationWhitelist
 * @notice Script for Admin Safe owners to approve and execute implementation whitelist changes
 * @dev The ImplementationWhitelist proxy is owned by the Admin Safe, so adding or removing
 *      whitelisted implementations requires an Admin Safe transaction. This script uses onchain
 *      approvals (approveHash) instead of offchain signatures, mirroring ManageGuardianSafeModule.
 *
 *      Multiple implementations can be changed in a single Admin Safe transaction. Because the
 *      ImplementationWhitelist's `whitelistImplementations` function operates on one ContractType at
 *      a time, changing both Organization and Account implementations together is batched into one
 *      atomic transaction via the Safe's MultiSendCallOnly contract. When only one ContractType is
 *      provided, a single direct call to the whitelist proxy is used instead.
 *
 *      Each Admin Safe owner runs the relevant function to approve. When the approval threshold is
 *      met and EXECUTE_IF_READY is true, the transaction is executed.
 *
 *      Whitelisting Organization + Account implementations in one transaction:
 *        forge script script/ManageImplementationWhitelist.s.sol:ManageImplementationWhitelist \
 *          --sig "whitelistImplementations(address,address[],address[],bool)" \
 *          <FACTORY_ADDRESS> "[<ORG_IMPL>,...]" "[<ACCOUNT_IMPL>,...]" <EXECUTE_IF_READY> \
 *          --rpc-url $RPC_URL \
 *          --broadcast \
 *          -vvvv
 *
 *      Removing implementations from the whitelist (same array shape):
 *        forge script script/ManageImplementationWhitelist.s.sol:ManageImplementationWhitelist \
 *          --sig "unwhitelistImplementations(address,address[],address[],bool)" \
 *          <FACTORY_ADDRESS> "[<ORG_IMPL>,...]" "[<ACCOUNT_IMPL>,...]" <EXECUTE_IF_READY> \
 *          ...
 *
 *      Where:
 *        - FACTORY_ADDRESS: The CREATE2 factory used for deployment (to lookup addresses)
 *        - The first array is Organization implementations, the second is Account implementations
 *          (either may be empty, e.g. "[]", but at least one must be non-empty)
 *        - EXECUTE_IF_READY: true to execute if threshold is met after approval
 *
 * @author Den Technologies Inc
 */
contract ManageImplementationWhitelist is BaseDeployScript {
    /**
     * @notice Approve and optionally execute whitelisting one or more implementations
     * @param factoryAddress The CREATE2 factory address (to lookup Admin Safe/whitelist addresses)
     * @param organizationImplementations Organization implementations to whitelist (may be empty)
     * @param accountImplementations Account implementations to whitelist (may be empty)
     * @param executeIfReady If true, execute the transaction if threshold is met after approval
     */
    function whitelistImplementations(
        address factoryAddress,
        address[] calldata organizationImplementations,
        address[] calldata accountImplementations,
        bool executeIfReady
    ) external {
        _manageImplementations({
            factoryAddress: factoryAddress,
            organizationImplementations: organizationImplementations,
            accountImplementations: accountImplementations,
            add: true,
            executeIfReady: executeIfReady
        });
    }

    /**
     * @notice Approve and optionally execute removing one or more implementations from the whitelist
     * @param factoryAddress The CREATE2 factory address (to lookup Admin Safe/whitelist addresses)
     * @param organizationImplementations Organization implementations to remove (may be empty)
     * @param accountImplementations Account implementations to remove (may be empty)
     * @param executeIfReady If true, execute the transaction if threshold is met after approval
     */
    function unwhitelistImplementations(
        address factoryAddress,
        address[] calldata organizationImplementations,
        address[] calldata accountImplementations,
        bool executeIfReady
    ) external {
        _manageImplementations({
            factoryAddress: factoryAddress,
            organizationImplementations: organizationImplementations,
            accountImplementations: accountImplementations,
            add: false,
            executeIfReady: executeIfReady
        });
    }

    /**
     * @notice Check the approval status for an implementation whitelist transaction
     * @param factoryAddress The CREATE2 factory address
     * @param organizationImplementations Organization implementations in the transaction (may be empty)
     * @param accountImplementations Account implementations in the transaction (may be empty)
     * @param isWhitelist True to check a whitelist (add) transaction, false for an unwhitelist (remove)
     */
    function checkStatus(
        address factoryAddress,
        address[] calldata organizationImplementations,
        address[] calldata accountImplementations,
        bool isWhitelist
    ) external {
        // Initialize and validate the factory
        validateAndInitializeFactoryOrRevert(factoryAddress);

        // Resolve addresses and build the Safe transaction
        (address safeAddress, address whitelistAddress) = _getAddresses();
        (address to, bytes memory data, uint8 operation) =
            _buildSafeTransaction(whitelistAddress, organizationImplementations, accountImplementations, isWhitelist);

        // Get the transaction hash
        bytes32 txHash = SafeTransactionUtils.getTransactionHash(ISafe(safeAddress), to, data, operation);

        // Get approval info
        uint256 threshold = ISafe(safeAddress).getThreshold();
        address[] memory owners = ISafe(safeAddress).getOwners();
        uint256 approvalCount = SafeTransactionUtils.countApprovals(ISafe(safeAddress), txHash, owners);

        // Log status
        Logger.logBoxHeader("ImplementationWhitelist Transaction Status");
        Logger.logKeyValue("Admin Safe", safeAddress);
        Logger.logKeyValue("ImplementationWhitelist", whitelistAddress);
        Logger.logKeyValue("Action", isWhitelist ? "whitelist" : "unwhitelist");
        Logger.logKeyValue("Organization implementations", organizationImplementations.length);
        Logger.logKeyValue("Account implementations", accountImplementations.length);
        Logger.logKeyValue("Threshold", threshold);
        Logger.logKeyValue("Approvals", approvalCount);
        Logger.logEmptyLine();

        if (approvalCount >= threshold) {
            Logger.logIndented("Status: READY TO EXECUTE");
        } else {
            Logger.logIndented(
                string(
                    abi.encodePacked(
                        "Status: NEEDS ", StringUtils.toString(threshold - approvalCount), " MORE APPROVAL(S)"
                    )
                )
            );
        }

        Logger.logEmptyLine();
        Logger.logIndented("Owners who have approved:");
        for (uint256 i = 0; i < owners.length; ++i) {
            // slither-disable-next-line calls-loop
            if (ISafe(safeAddress).approvedHashes(owners[i], txHash) == 1) {
                Logger.logKeyValue("  ", owners[i]);
            }
        }
        Logger.logBoxFooter();
    }

    /// @dev Shared flow for whitelisting/unwhitelisting one or more implementations: validate inputs,
    ///      build the Safe transaction, log context, then approve and optionally execute via the Safe.
    ///      The shared approve-and-execute logic lives in SafeTransactionUtils.approveAndExecuteIfReady.
    ///      The Safe transaction is either a direct Call to the whitelist proxy or a MultiSendCallOnly batch.
    function _manageImplementations(
        address factoryAddress,
        address[] calldata organizationImplementations,
        address[] calldata accountImplementations,
        bool add,
        bool executeIfReady
    ) internal {
        // Initialize and validate the factory
        validateAndInitializeFactoryOrRevert(factoryAddress);

        // Require at least one implementation across both types
        require(
            organizationImplementations.length > 0 || accountImplementations.length > 0, "No implementations provided"
        );

        // Resolve addresses
        (address safeAddress, address whitelistAddress) = _getAddresses();
        require(Create2Utils.isContractDeployedAtAddress(safeAddress), "Admin Safe not deployed");
        require(Create2Utils.isContractDeployedAtAddress(whitelistAddress), "ImplementationWhitelist not deployed");

        // Validate the implementations against their current whitelist state
        _validateImplementations(whitelistAddress, ContractType.Organization, organizationImplementations, add);
        _validateImplementations(whitelistAddress, ContractType.Account, accountImplementations, add);

        // Build the Safe transaction (single direct call, or a MultiSend batch for both types)
        (address to, bytes memory data, uint8 operation) =
            _buildSafeTransaction(whitelistAddress, organizationImplementations, accountImplementations, add);

        // Prompt for confirmation when running with --broadcast
        confirmBroadcastOrDryRun("ManageImplementationWhitelist");

        // Log header
        Logger.logBoxHeader(
            string(abi.encodePacked("ImplementationWhitelist Transaction - ", add ? "WHITELIST" : "UNWHITELIST"))
        );
        Logger.logKeyValue("Admin Safe", safeAddress);
        Logger.logKeyValue("ImplementationWhitelist", whitelistAddress);
        Logger.logKeyValue("Organization implementations", organizationImplementations.length);
        Logger.logKeyValue("Account implementations", accountImplementations.length);
        Logger.logKeyValue("Batched (MultiSend)", operation == 1 ? "yes" : "no");
        Logger.logKeyValue("Threshold", ISafe(safeAddress).getThreshold());
        Logger.logEmptyLine();

        // Approve (and optionally execute) the Safe transaction
        vm.startBroadcast();
        SafeTransactionUtils.approveAndExecuteIfReady({
            safe: ISafe(safeAddress), to: to, data: data, operation: operation, executeIfReady: executeIfReady
        });
        vm.stopBroadcast();

        Logger.logBoxFooter();
    }

    /// @dev Get Admin Safe and ImplementationWhitelist proxy addresses from deployment.toml
    function _getAddresses() internal returns (address safeAddress, address whitelistAddress) {
        safeAddress = getExpectedAdminSafeAddress();
        whitelistAddress = getExpectedWhitelistProxyAddress();
    }

    /// @dev Builds the Safe transaction (target, calldata, operation) for the requested whitelist change.
    ///      A single ContractType produces a direct Call to the whitelist proxy; both ContractTypes
    ///      are batched into one MultiSendCallOnly DelegateCall so they apply atomically.
    /// @param whitelistAddress The ImplementationWhitelist proxy address
    /// @param organizationImplementations Organization implementations to change (may be empty)
    /// @param accountImplementations Account implementations to change (may be empty)
    /// @param add True to whitelist, false to unwhitelist
    /// @return to The Safe transaction target
    /// @return data The Safe transaction calldata
    /// @return operation The Safe operation type (0 = Call, 1 = DelegateCall)
    function _buildSafeTransaction(
        address whitelistAddress,
        address[] calldata organizationImplementations,
        address[] calldata accountImplementations,
        bool add
    ) internal returns (address to, bytes memory data, uint8 operation) {
        bool hasOrg = organizationImplementations.length > 0;
        bool hasAccount = accountImplementations.length > 0;

        if (hasOrg && hasAccount) {
            // Batch both calls into a single atomic MultiSendCallOnly DelegateCall
            bytes memory orgCall = _encodeWhitelistCall(ContractType.Organization, organizationImplementations, add);
            bytes memory accountCall = _encodeWhitelistCall(ContractType.Account, accountImplementations, add);

            // Each sub-transaction is already length-prefixed (see _encodeMultiSendTransaction), so a
            // plain concatenation is unambiguous. Use bytes.concat rather than abi.encodePacked with
            // multiple dynamic arguments.
            bytes memory transactions = bytes.concat(
                _encodeMultiSendTransaction(whitelistAddress, orgCall),
                _encodeMultiSendTransaction(whitelistAddress, accountCall)
            );

            to = getExpectedSafeInfrastructureAddresses().multiSendCallOnlyAddress;
            require(Create2Utils.isContractDeployedAtAddress(to), "MultiSendCallOnly not deployed");
            data = abi.encodeCall(IMultiSendCallOnly.multiSend, (transactions));
            operation = 1; // DelegateCall (required for MultiSend)
        } else {
            // Single ContractType: a direct call to the whitelist proxy
            to = whitelistAddress;
            if (hasOrg) {
                data = _encodeWhitelistCall(ContractType.Organization, organizationImplementations, add);
            } else {
                data = _encodeWhitelistCall(ContractType.Account, accountImplementations, add);
            }
            operation = 0; // Call
        }
    }

    /// @dev Validates a set of implementations for a ContractType against the current whitelist state
    /// @param whitelistAddress The ImplementationWhitelist proxy address
    /// @param contractType The contract type (Organization or Account)
    /// @param implementations The implementations being changed
    /// @param add True when whitelisting (implementations must be deployed and not already whitelisted),
    ///        false when unwhitelisting (implementations must currently be whitelisted)
    function _validateImplementations(
        address whitelistAddress,
        ContractType contractType,
        address[] calldata implementations,
        bool add
    ) internal view {
        for (uint256 i = 0; i < implementations.length; ++i) {
            address implementation = implementations[i];
            require(implementation != address(0), "Implementation address cannot be zero");

            // slither-disable-next-line calls-loop
            bool isWhitelisted =
                IImplementationWhitelist(whitelistAddress).isImplementationWhitelisted(contractType, implementation);

            if (add) {
                require(Create2Utils.isContractDeployedAtAddress(implementation), "Implementation not deployed");
                require(!isWhitelisted, "Implementation already whitelisted");
            } else {
                require(isWhitelisted, "Implementation not whitelisted");
            }
        }
    }

    /// @dev Encodes a call to whitelistImplementations adding or removing implementations for one type
    /// @param contractType The contract type (Organization or Account)
    /// @param implementations The implementation addresses
    /// @param add True to whitelist (add), false to unwhitelist (remove)
    /// @return The encoded call to whitelistImplementations
    function _encodeWhitelistCall(ContractType contractType, address[] calldata implementations, bool add)
        internal
        pure
        returns (bytes memory)
    {
        address[] memory empty = new address[](0);
        address[] memory toWhitelist = add ? _toMemory(implementations) : empty;
        address[] memory toUnwhitelist = add ? empty : _toMemory(implementations);

        return
            abi.encodeCall(
                IImplementationWhitelist.whitelistImplementations, (contractType, toWhitelist, toUnwhitelist)
            );
    }

    /// @dev Encodes a single sub-transaction in the Safe MultiSend packed format
    ///      Layout: operation (1 byte, 0 = Call) ++ to (20 bytes) ++ value (32 bytes) ++
    ///              dataLength (32 bytes) ++ data
    /// @param to The sub-transaction target
    /// @param data The sub-transaction calldata
    /// @return The packed sub-transaction
    function _encodeMultiSendTransaction(address to, bytes memory data) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(0), to, uint256(0), data.length, data);
    }

    /// @dev Copies a calldata address array into memory
    /// @param input The calldata array
    /// @return output The memory copy
    function _toMemory(address[] calldata input) internal pure returns (address[] memory output) {
        output = new address[](input.length);
        for (uint256 i = 0; i < input.length; ++i) {
            output[i] = input[i];
        }
    }
}
