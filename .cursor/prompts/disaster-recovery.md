**Disaster Recovery**
This project is for a new type of onchain self-custody.

Specifically, it's meant for organizations (not individuals) and uses smart contracts to store assets.
What's unique about it, as opposed to something like a standard Safe multisignature wallet, is that it's Policy-based.
Policies are essentially "if-then" rules for what sorts of transactions are allowed to be executed via the smart accounts in an organization.

In this system, there are two primary types of smart contacts:
1. The Organization contract
2. The Account contract

The Organization contract represents the real-world organization. It contains all the state in storage:
- Who the Members of the organization are
- What the "Groups" of Members are
- Who the Admin(s) of the organization are
- What the Policies are

The Account contract is essentially the "smart account" -- it's the contract that stores the assets.

An Organization can have multiple Accounts. An Account can be tied to only one Organization.

Both Organizations and Accounts are actually Proxies.
- Organization's are UUPS proxy @OrganizationProxy.sol implemented by @OrganizationImplementation.sol
- Account's are Beacon proxies @AccountProxy.sol implemented by @AccountImplementation.sol and their beacon is actually the Organization itself

Accounts are actually really simple contracts that contain very little logic and very little state.

To execute a transaction through an Account, the executor actually needs to call a function on the Organization contract with the transaction data and with the address of the account they want to execute the transaction from. The Organization contract then forwards the transaction to the Account, and only then does the Account execute the transaction. That means that the Organization contract does all the validation logic (makes sure that the policy that the transaction is being created with matches the transaction and that valid approval signatures are provided).

We are now implementing disaster recovery. Right now, all operations require the "guardian" (an address we control) to execute/co-sign along with users. If our company no longer exists and the "guardian" is no longer available to execute/co-sign operations, our customers can no longer withdraw their funds. Obviously, this is bad. The goal of disaster recovery is to allow our users to withdraw their funds and/or continue operations even if the guardian is no longer operating.

We want to add disaster recovery functionality to our contracts such that:

- There are new storage variables:
  -  ``: 
      indicates whether or not recovery is even **supported** for recovery account transactions and recovery ERC1271 signatures, both of which bypass our guardian and policy checks.
  - `isRecoveryEnabledForTransactionsAndERC1271`:
      indicates whether or not recovery is **enabled** for recovery account transactions and recovery ERC1271 signatures. This should only ever be allowed to be set to `true` if and only if `isRecoverySupportedForTransactionsAndERC1271` is `true` (otherwise the feature should be considered not supported and impossible to enable)
  - `transactionAndERC1271RecoveryAddress`:
      the priveledged address that's allowed to call our "recovery" function for executing account transactions while bypass guardian and policy/review signature checks.
  - `isRecoveryEnabledForGuardianUpdate`:
     indicates whether or not recovery is **enabled** for the recovery function that updates the guardian address. This is used if the guardian is down and a user just wants to change the guardian.
  - `guardianRecoveryAddress`:
      the priveledged address that's allowed to call our "recovery" function for updating the guardian address while bypassing typic guardian/admin checks

- The `initialize` function that's called when deploying/initializing an Organization contract sets the following storage variables:
  - `isRecoverySupportedForTransactionsAndERC1271`
  - `transactionAndERC1271RecoveryAddress` (must be set, i.e. not the zero address, if `isRecoverySupportedForTransactionsAndERC1271` is `true`. Cannot be set if it is `false`)
  - `guardianRecoveryAddress` (must be set always, can't be zero address)

- There is a new function `setRecoveryStateForTransactionsAndERC1271` on OrganizationImplementation:
  - It is the setter function for setting `isRecoveryEnabledForTransactionsAndERC1271`
  - This function should only be callable by `transactionAndERC1271RecoveryAddress`
  - This function should only be callable if `isRecoverySupportedForTransactionsAndERC1271` is `true`. 
  - This function should also timelocked (so you may need another function to "lock it in" after a period of time)
- There is a new function `executeRecoveryAccountTransaction` on OrganizationImplementation:
  - This function executes an "Account Transaction" while bypassing guardian and policy checks
  - This function should forward the call to the Account contract, similar to `executeAccountTransaction`
  - This function should only be callable by `transactionAndERC1271RecoveryAddress` 
  - This function should only be callable if `isRecoveryEnabledForTransactionsAndERC1271` and `isRecoverySupportedForTransactionsAndERC1271` are `true`
- The existing `isValidAccountSignature` for ERC1271 signatures is updated such that:
    - if `isRecoveryEnabledForTransactionsAndERC1271` and `isRecoverySupportedForTransactionsAndERC1271` are both `true`, then:
      - it should first check if the signature provided is from the `transactionAndERC1271RecoveryAddress`
        - if it is, then it should not do any of our normal guardian/policy checks (the signature from the recovery address is sufficient)
        - if it not, then it should fallback to the existing validation logic where guardian and policy checks occur
        - Note that both standard EOA signatures and ERC1271 smart contract signatures should both be support for the recovery address (maybe the recovery address is a smart contract)
- There is a new function `setRecoveryStateForGuardianUpdate`
  - It is the setter function for setting `isRecoveryEnabledForGuardianUpdate`
  - This function should only be callable by `guardianRecoveryAddress`
  - This function should also timelocked (so you may need another function to "lock it in" after a period of time)
- There is a new `executeRecoveryGuardianUpdate`:
  - This function should allow users to change the guardian address
  - This function should only be callable by the `guardianRecoveryAddress`
  - This function should only be callable if `isRecoveryEnabledForGuardianUpdate` is `true`
  - This function should be a 2-step function (so you may need to add another function) where the new guardian address will need to "confirm" that it's accepting the role of guardian -- this is to prevent the situation where the user accidentally changes the guardian to an address they don't control. Note: as part of this, we should also change our existing (non-recovery) function for updating the guardian to similarly be a 2-step process where the guardian new need to "confirm".


NOTE: Follow all of our current codebase conventions, including creating a new library for this disaster recovery functionality, using a ERC7201 namespaced storage library for the storage variables, etc.
