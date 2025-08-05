// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library Policies {
    enum PolicyType {
        AutoApprove,
        AutoReject,
        RequireManualApproval
    }

    enum ApproverType {
        Group,
        Member
    }

    enum TransactionType {
        Any,
        TokenTransfers,
        ContractInteractions
    }

    enum DestinationType {
        Any,
        WhitelistedOnly,
        NonWhitelistedOnly,
        CustomList
    }

    enum PolicyLimitation {
        None,
        SingleTransaction,
        TimeInterval
    }

    enum TimeIntervalScope {
        AcrossAll,
        PerEntity
    }

    struct FunctionSelector {
        bytes4 selector;
        bytes parameterConstraints; // ABI-encoded parameter matching rules
    }

    struct Policy {
        // Core policy behavior
        PolicyType policyType;
        // Approver configuration (only used when policyType == RequireManualApproval)
        ApproverType approverType;
        uint8 approverId; // ID of the group or member who can approve
        uint256 approvalThreshold; // Number of approvals needed (only used when approverType == Group)
        // Transaction source filtering
        bool anySourceAccount; // If true, applies to transactions from any account
        address[] sourceAccountAddresses; // Specific account addresses (only used when anySourceAccount == false)
        // Transaction initiator filtering
        bool anyInitiator; // If true, applies to transactions initiated by anyone
        ApproverType initiatorType; // Whether initiator filter is by Group or Member
        uint8 initiatorId; // ID of the specific group or member (only used when anyInitiator == false)
        // Transaction type filtering
        TransactionType transactionType;
        // Token filtering (only used when transactionType == TokenTransfers)
        bool anyToken; // If true, applies to transfers of any token
        address tokenAddress; // Specific token address (use address(0) for native token)
        // Amount threshold filtering (only used when transactionType == TokenTransfers)
        bool hasAmountThreshold; // If true, policy only applies when amount < amountThreshold
        uint256 amountThreshold; // Maximum amount for policy to apply
        // Transaction destination filtering
        DestinationType destinationType;
        address[] customDestinations; // Custom list of addresses (only used when destinationType == CustomList)
        // Function filtering (only used when transactionType == ContractInteractions)
        bool anyFunction; // If true, applies to calls to any function
        FunctionSelector[] allowedFunctions; // Specific functions that can be called
        // Policy usage limitations
        PolicyLimitation limitation;
        uint256 timeIntervalHours; // Hours in time interval (only used when limitation == TimeInterval)
        TimeIntervalScope timeIntervalInitiatorScope; // Whether time limits are per-initiator or global
        TimeIntervalScope timeIntervalSourceScope; // Whether time limits are per-source-account or global
        TimeIntervalScope timeIntervalDestinationScope; // Whether time limits are per-destination or global
    }
}
