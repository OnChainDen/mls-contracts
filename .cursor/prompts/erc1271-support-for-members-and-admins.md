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

Up until now, we always assume that:
- Signatures from Members were only from EOA (65 bytes signatures)
- Signatures from Admins were only from EOA (65 bytes signatures)
- Signatures from the Guardian could be either from an EOA or from a smart contract that supports ERC-1271 signatures
- Signatures from the disaster recovery transaction recovery address could be either from an EOA or from a smart contract that supports ERC-1271 signatures (specifically in the case of ERC-1271 signatures from an Account, when we validate if the message was signed by the recovery address)

We now want to move to a new model, where we support both ERC-1271 AND standard EOA signatures for ALL places where we validate signatures, including anywhere we validate signatures from Members and Admins.

Create a plan to make this change. Update the README.md if needed, too.