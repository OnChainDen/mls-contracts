**Deployment Scripts**
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

When upgrading Organization or Account contracts, the new implementation address for the proxy needs to be whitelisted by our "ImplementationWhitelist" contract, which is itself also a proxy (@ImplementationWhitelistProxy.sol and @ImplementationWhitelistImplementation.sol).

Accounts are actually really simple contracts that contain very little logic and very little state.

To execute a transaction through an Account, the executor actually needs to call a function on the Organization contract with the transaction data and with the address of the account they want to execute the transaction from. The Organization contract then forwards the transaction to the Account, and only then does the Account execute the transaction. That means that the Organization contract does all the validation logic (makes sure that the policy that the transaction is being created with matches the transaction and that valid approval signatures are provided).


**Your job**
Our goal now is to write/update our contract deployment scripts to deploy our entire platform/system onto a network from scratch.
It's very important for all of our contracts to be deployed deterministically at the same addresses across the various chains/networks where we'll deploy them.


Here is some relevant information that you should know:
- The @OrganizationProxy.sol contract is deployed by the @OrganizationFactory.sol CREATE 2 factory contract. As a result, the deployment script just needs to deploy the @OrganizationFactory.sol, not the Proxy contract itself
- The @AccountProxy.sol contract is deployed by the Organization contract, which also acts as a CREATE2 factory contract. As a result, the deployment script doesn't need to deploy the @AccountProxy.sol contract itself, since deploying the @OrganizationFactory.sol contract will be enough, since it can then be used to deploy new Organization contracts when we onboard new customers to our platform, which can then be used to deploy new accounts.
- The @ImplementationWhitelistProxy.sol contract is deployed by the @ImplementationWhitelistFactory.sol CREATE2 factory contract. In this case, the deployment script SHOULD both deploy the factory, then use it to deploy the ImplementationWhitelistProxy.sol. This is because the ImplementationWhitelist is not a per-customer contract that is only deployed when we onboard a new customer, but is a global contract for all customers.
- While most of our proxy contracts don't need to be deployed in the deployment script (with exception of the ImplementationWhitelist proxy), implementation contracts for our various proxy contracts do need to be deployed by the deployment script. They also need to be deployed before the factory contracts are deployed.
- Some of our contracts, specifically @OrganizationImplementation.sol use public/external libraries under-the-hood that need to be deployed on their own independently before the contract itself is deployed, and needs to be linked.
- Some of our contracts give special priviledges to permissioned address, specifically the "guardian" which is used by the Organization contracts, and the "deployer" used by the factory contracts. For these special addresses, we actually want to use Safe multisigs instead of EOAs. The deployment script should deploy these two Safes, too, so that they can then be used by these other contracts as those priveledged addresses. The safe contracts should therefore be deployed earlier on in the process, too. Also make sure that the other "Safe" contracts, like the Multisend contrats/libraries/factories/etc. are deployed too.


Since it's very important for all our contracts to be deployed deterministically at the same address across the various chains/networks where we'll deploy them, we want to use the "archnid" create2 factory whenever possible. However, sometimes it's not available. We want to deploy using a totally separate EOA that deploys the safe singleton factory, which we'll then use instead of the Arachnid factory. That EOA should be a separate private key from the other deployment "flows" that's heavily guarded, because we want to avoid accidentally "burning the nonce" when trying to deploy on a new chain, so we can keep some determinism.

You will likely want to create multiple scripts for the different "flows":
1. Deploying using the arachnid factory
2. Deploying the Safe Singleton factory ourselves
3. Deploying using the Safe Singleton factory we deployed.

It might be possible to combine scripts 1 & 3 into one script that takes in the address of the create2 factory, if the interfaces for the Arachnic and Safe Singleton Factory contracts are the same.
The scripts should also check to see if any contract it's trying to deploy has already been deployed, and if it has been, skip it. If it hasn't been, then try to deploy it. Make sure to console log so we know if something's being skipped or deployed. 

For script #2 (deploying the Safe Singleton Factory ourselves), it's very imporant we don't accidentally "burn the nonce" of the special EOA that's deploying the factory. Make sure to add every check possible to prevent this from happenig.

Follow best practices for writing scripts and follow or styleguide at @STYLEGUIDE.md. 