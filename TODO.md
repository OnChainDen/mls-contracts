- [x] Delete AccountInit.sol and OrganizationInit.sol (they're unused)
- [x] Delete OnchainCustodyOrganizationFactory.sol (it's unused)
- [x] In all the LibOrganization*.sol files in `organizations/libraries/` there are non-`view` functions (functions that modify storage) that call `enforceOnlyGuardian` and `validateAdminAuthorization`. Move those function calls out of the internal Library functions and into the `external` functions in `OrganizationImplementation.sol` that wrap those functions.  For the `enforceOnlyGuardian` calls, create a new modifier called `onlyGuardian` and use that instead of a normal function.
- [x] Make sure that only the `guardian` address can call the `deploy` function in `LibOrganizationAccountFactory`
- [x] In all the LibAccount*.sol files in `accounts/libraries/` there are non-`view` functions (functions that modify storage) that call `enforceOnlyGuardian` and `validateAdminAuthorization`. Move those function calls out of the internal Library functions and into the `external` functions in `AccountImplementation.sol` that wrap those functions.  For the `enforceOnlyGuardian` calls, create a new modifier called `onlyGuardian` and use that instead of a normal function.
- [x] In `LibOrganizationMembers.sol`, we define `computeAdminNonce`, but `computeAdminNonce` is already defined elsewhere in this project. Delete the function in `LibOrganizationMember.sol` and use the same `computeAdminNonce` function that's used everywhere else. **NOTE: WE MAY HAVE ALREADY DELETED THIS FUNCTION WHEN MOVING VALIDATION LOGIC TO `OrganizationImplementation.sol`** 
- [DELAY] In `LibOrganizationMembers.sol` in the `removeMembers` function, there's a step that removes a member from all groups that they belong to. It does this by iterating through all the groups in the organization, checking if the member is in the group, and then removing the member if they were in it. This is incredibly gas inefficient. To improve gas efficiency, start keeping track of all the groups a member is in, so that when we remove a member from an organization we only need to iterate over the groups that they're in, instead of all groups that are in the organization. **NOTE: THIS MAKES OTHER OPERATIONS MORE EXPENSIVE, LIKE MODIFYING A GROUP, AS WE HAVE TO UPDATE THE ARRAY EVERYWHERE**
- [x] In `LibOrganizationMembers.sol` in the `removeMembers` function, delete the `memberAddresses` array that's used for the `MembersRemoved` event and delete the parameter from the event. It's not needed and just wasted more gas.
---
- [x] Right now, deploying a new OrganizationProxy.sol contract via the OrganizationFactory.sol and initializing it is a one-step process (the constructor of `OrganizationProxy.sol` calls the `initialize` function in `OrganizationImplementation`). Instead, it should be a two-step process, where the factory first deploys the `OrganizationProxy.sol` contract, without initializing, and then another external transaction is needed to call the `initialize` function. The constructor of the `OrganizationProxy.sol` contract should not accept any parameters besides deployer address and maybe the implementation contract address. Only the deployerAddress should be able to call the `initialize` function, and it should only be able to call it once. 

Note: Deploying the Organization proxy actually _used_ to be a two-step process, like i describe, back when we used a Diamond proxy pattern instead of a UUPS proxy patten. But, when we migrated from using the Diamond proxy pattern to the UUPS proxy pattern, the two-step process was changed to the undesired one-step process. 

To help you see what I mean, check out three old files that I've kept for reference in the `references` directory:
1. `OrganizationInitializationFacet.old.sol`
2. `OrganizationDiamondFactory.old.sol`. 
3. `OnchainCustodyOrganizationDiamond.old.sol`

In the old paradigm, `OnchainCustodyOrganizationDiamond.old.sol` was the diamond proxy (analogous to our current `OrganizationProxy.sol`) that was deployed by the old factory contract `OrganizationDiamondFactory.old.sol` (analogous to our current `OrganizationFactory.sol`). It was deployed to automatically have the facet cut from `OrganizationInitializationFacet.old.sol` which contained the `initialize` function. In our case, we want our UUPS proxy to be deployed with an implementation address.

Only refer to how they make it a two-step process, and ignore anything else unrelated to the two-step "deploy" then "initialize" process (e.g. the way we check the whitelist is different now and we don't want to match how we do whitelist checks in the old reference files.)

Note: all UUPS proxy implementation address are whitelisted by an external whitelist contract. In our project, when a proxy is being upgraded, we check that external whitelist contract to make sure that the implementation is whitelisted, to avoid accidentally using an unauthorized/malicious/broken implementation contract for the proxy. Our factory contract should similarly check to make sure that the implementation contract for the `OrganizationProxy.sol` is whitelisted.

Write a plan to make this happen and ask me any question you may have.
---
- [x] Right now, on `OrganizationImplementation.sol`, the `validateAdminAuthorization` function is `external` and can be called by anyone. I think it's used by an external contract, `AccountImplementation.sol` (via some internal libraries that it calls), to validate admin signatures, but double-check me on that. If it is used like i think it is, then it should only be called by `AccountProxy.sol` contracts that were deployed by the `OrganizationImplementation.sol` via an internal library (`LibOrganizationAccountFactory.sol`). Make it so that when an `AccountProxy.sol` is deployed, `LibOrganizationAccountFactory.sol` keeps track of which accounts were deployed through a simple mapping (address => bool) and make it so that `validateAdminAuthorization` can only be called by `AccountProxy.sol` contracts that were deployed by that Organization contract.
- [x] In `UpgradeAuthorizationStorage.sol`, `useUpgradeNonces` is defined but is never used in the project as far as I can tell. Confirm if this is the case. If it is indeed the case that it is never used, then delete.
- [x] Our two core contracts: `AccountProxy.sol` and `OrganizationProxy.sol` are UUPS proxies. In order to upgrade them, 3 conditions need to be met: the upgrade function(s) must only have been called by the "guardian", admin signatures must be provided and validated, AND the new implementation address must be whitelisted by an external whitelist contract. Right now, the logic for the whitelist has a concept of a `whitelistSetId`, but this isn't useful and doesn't make sense to have. Instead, change the way that the implementation address whitelist is checked, such that it only cares if it's looking at "Account Proxy" or "Organization Proxy" and then checks if the implementation address is whitelists for accounts or whitelisted for organizations. In otherwords, there should technically be two separate whitelists (managed by one external whitelist contract): one for Account Implementations, one for Organization Whitelists, and there should be not concept of a `whitelistSetId`. Write a plan to make this change. Ask me any questions you have.
- [x] In `LibAccountTransactionStorage.sol`, an enum `Operation` is defined, but it doesn't appear to actually be _functionally_ used anywhere in the project (it may be passed through in some functions, but doesn't appear to actually be used after that). Confirm if that's the case, and if it is the case that it's not _functionally_ used anywhere, remove it and any references to it.

**For PR:**
- [x] Delete or fix deployment script(s) (https://github.com/OnChainDen/onchain-custody-contracts/pull/2/files#r2556966379) and change the name of othe script(s) - `DeployUUPS.s.sol`
- [x] Remove `LibAccountAdmin.getOrganizationAddress()` function and modify `AccountImplementation.getOrganizationAddress()` to get the organization address directly
- [x] Delete files in `/references/`
- [x] Look into the function `__BaseUUPSImplementation_init` in `BaseUUPSImplementation.sol` and determine if we need it or can modify things to not need it or somehow better protect against it.

**For migrating to organization as entrypoint for Account Transactions PR**
- [x] Move all checks (guardian check, signatures checks, deployed account checks, etc. to `OrganizationImplementation.sol`, to match the similar pattern we have with other external functions in `OrganizationImplementation.sol` and the internal libraries that they call).
- [x] Migrate the entrypoint for upgrading the AccountProxy to the Organization contract (call a function on organization contract to then call function on Account contract to upgrade contract. Keep all checks in the organization contract.). Then delete the `validateAdminAuthorization` function and the internal library function that calls it. Delete the `validateAdminAuthorization` external function in `OrganizationImplementation.sol` after this too, since it shouldn't need to be called externally anymore, just internally via the internal library function.
- [x] (POSSIBLY DEPENDENT ON ITEM ABOVE) Check if `IAdminFacet.sol` is needed anymore, since it only has the `validateAdminAuthorization` function interface. If it's not used anywhere, delete the entire file.




**Beacon Account Proxy Prompt**

Right now, we have two main contracts:
1. The "Organization" contract
2. The "Account" contract.

The "Account" contract is a smart account that stores user funds. The "Organization" contract is used for managing the business's organization, things like managing Members, Admins, Policies, etc. One Organization can have multiple Accounts. One Account only has one Organization.

Currently, both the Organization and Account contracts are UUPS proxies. The Organization contract is primarily implemented in @OrganizationProxy.sol and @OrganizationImplementation.sol. The Account contract is primarily implemented in @AccountProxy.sol and @AccountImplementation.sol.

To deploy an AccountProxy or upgrade an AccountProxy's implementation, you need to call functions on the Organization contract (implemented in @OrganizationImplementation.sol). 

AccountProxies are deployed via CREATE2 to ensure that they have the same addresses across chains.

Now, we want to change the AccountProxy to no longer be a UUPS proxy and instead be a Beacon Proxy, where the Organization contract acts as the beacon (says where the implementation contract address is). The reason why is that some Organizations may have 1,000s of accounts, so we need to make it easy to upgrade them.

Note that Account's already keep track of their associated Organization's (i.e. their new "beacon"'s ) address.

Use OpenZeppelin contracts if possible.

One thing to be aware of as well: we NEED AccountProxy contracts to be deterministically deployable at the same address accross chains. That means when you're modifying the logic to deploy AccountProxy contracts, you need to be careful to not accidentally break our ability to deploy them at the same address in the event that the implementation address changes.


**Stateful-time based policies**

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

Right now, the Policies are not time-based, meaning you can create a Policy that says something "send no more than 1,000 USDC per transaction from an account (or a custom list of accounts or all accounts) to a destination (or a custom list of destinations or any destination)" (this is just an example).

However, we want to introduce the option of also making Policies time-based, meaning you can create a Policy that says something like "send no more than 1,000 USDC per 30 days from an account (or a custom list of accounts or all accounts) to a destination (or a custom list of destinations or any destinations)". Again this is just another example.

For token transfers, the policy should specify that the amount can be sent per time interval:
- across all accounts in aggregate, or per account
- across all destinations in aggregate, or per destination
- across all initiators in aggregate, or per initiator

For contract interactions, the time limitation, if set, should simply specify how many times per time interval the function can be called, with similar additional specifications:
- across all accounts in aggregate, or per account
- across all destinations in aggregate, or per destination (destination in this case is the contract being called)
- across all initiators in aggregate, or per initiator

For ERC-1271 signatures, the time limitations, if set, sould specify how many time per time interval the function can be called:
- across all accounts in aggregate, or per account
- across all initiators in aggregate, or per initiator

Keep this as gas efficient as possible. If you have to totally overhaul how we store policies in storage, that's fair game.
**Contract policies that match function parameters PR**
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

Right now, the contracts allow for policies for contract interactions that match transactions based on the contract address and function selector, but not the function parameters.

Now, we want to add the ability to specify function parameters as well.

Policies can allow a user to specific function parameters for contract interaction policies

If the parameter is a boolean, the policy can should specify that it must be an exact value or any value (wildcard)

If the parameter is a number (treat enums as numbers too), the policy should specify that value is either in a range (includsive), an exact value, or any value (wildcard)

If the parameter is bytes or string, the policy should specify that is must be an exact value of any value (wildcard)

If the parameter is an array or struct, the policy can only specify that it must be set to "any value" (wildcard)

If the parameter is an address, the policy must specify that it is set to a specifc value, any value in a custom list of values, or is any value (wildcard)

Note that this is could be very gas intensive, so place extra care in making sure that policies are not too expensive to store onchain or evaluate onchain when executing a transaction.

If your solution to making it not that gas intensive involves any offchain operations (like hashing a policy or creating a proof or something offchain and passing it in or storing it somwhere) that is allowed, just make sure I'm aware so I can then later implement those things in another repo/project.


**ERC-1271 Signatures**
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

Right now, the contracts allow for policies for token transfers and contract interactions.

Now, we want to add a new type of policy for signatures (smart contract signatures following the ERC-1271 standard).

If a policy is for a signature, it should be allowed to define:
- whether or not the signature is auto-approved or requires a manual review.
- Member or Group who needs to sign the signature if it requires manual review. If it's a Group, then a threshold should also be set (similar to policies for token transfers and contract interactions).
- The Account (or accounts) that the signatures are on behalf of

The `isValidSignature` function should be defined on the Account contract, but a lot of the logic will have to happen in the Organization contract, so you'll need to do a call from the Account to the Organization contract.

The validation logic should be sure to check that:
1. the signatures are for the right account and chain id
2. the signatures are for the right policy (the policy id may need to be assumed to be appened to the `signatures` argument to `isValidSignature`, as well as be inside the signed message), meaning that the "reviewers" are the correct ones according to the policy attached
3. the signatures also include a signature from the guardian address

**ERC-1271 Signature TODO**
- [x] Should ERC-1271 signatures also expire? If yes, then add expiration

**For Future PRS:**
- [x] Fix whatever's going with the `upgradeToWithAuthorization` and `upgradeToAndCallWithAuthorization` functions in `BaseUUPSImplementation`, sepcifically with the guardian/admin checks that occur in `LibUpgradeAuthorization.validateUpgradeAuthorization` because they still use old code that references facets
- Use `ERC7201NameSpace` library/contract from OpenZeppelin for all storage libraries to compute storage slot
- [ ] Remove all interface files for facets
- [ ] Move a bunch of stuff into a new `common` directory
- [ ] FIX INITIATOR VALIDATION IN POLICIES: WE DO NOT HANDLE TRANSACTION/ERC-1271 INITIATORS CORRECTLY.
- [ ] FIX AUTO APPROVAL POLICIES: WE DO NOT CHECK THAT AT LEAST ONE SIGNATURE FROM THE INITIATORS IS PROVIDED.
- [ ] Implement better policy validation when creating a policy
- [ ] Prevent the creation of "Auto approval policies"

**Questions**
- **SHOULD WE DROP THE CONECPT OF GROUPS ALTOGETHER IN THE CONTRACTS?**
- In OrganizationFactory.sol, should `deployerAddress` be immutable?
- Do we need `memberId` at all for Organization Members in `LibOrganizationMembers.sol` and other places?
- In `LibOrganizationMember.sol` in the `removeMembers` function, there's a step that removes a member from all groups that they belong to. It does this by iterating through all the groups in the organization, checking if the member is in the group, and then removing the member if they were in it. This is incredibly gas inefficient. For gas efficiency, would it better to start keeping track of all the groups a member is in, or can avoid removing them altogether from groups since we check if the user is in the organization anyway when doing any signature checks.
- Should we move the `Policies` Struct in `src/libraries/Policies.sol` to `LibOrganizationPolicies.sol`?
- Do we really need a `policyExists` mapping in `LibOrganizationPolicyStorage.sol`? Is there another way to check if a policy exists that would be more gas efficient?
- Should we have an ability to remove an account from an organization?
- Do we need a `removeAccount` function on `OrganizationImplementation.sol` to remove an account from an organization?
- Should contract call policies allow multiple functions to be allowed, or just one? Well, really it would be "any function" or "one specific function + optionally param constraints" rather than "any function" or a "possible list of allowed functions + optional param contracts per function"

**Fix initiator prompt**
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

Users can define policies so that it only applies to a specific initiator (or group of inititators). E.g. "this policy can only be used if the transaction is initiated by this Member or any member in this group (initiator can be set to a Member or Group. If its a group, then the policy can be used for any transaction initiated by any member in that group)". Right now, our logic for validating the transaction initiator when evaluating a policy when executing a transaction is completely broken and makes no sense, so we need to totally re-rewrite.

Implement the policy checks for the right transction initiator. Note that your solution may require you to do the following:
1. Expect a separate "initiator" signature that's separate from the "review" signatures. Instead of making it a new function parameter to functions like `executeAccountTransaction` or `isValidTransaction`, expect that the part of the signatures bytes function parameter is the initiator's signature, and the rest are the review signatures.
2. Expect that the review signatures are also a function of the hash of the initiator's signature. This makes it verifiable that the initiator's signature actually came first. 

**PROMPT: Policy optimization -- using structs instead of bitmap**
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

Right now, policies are represented as nested merkle trees, and some of the policy data is stored as a bitmap. However, using a bitmap is SO complicated, hard to maintain, and bug-prone. Instead, we want to just use a struct (or structs) to represent the data that's currently being represented as a bitmap to simplify everything, and we're okay with the increase gas cost from the increased usage of calldata to pass the information. The big issue you'll need to overcome is stack-too-deep errors, but we don't want to use a bitmap to overcome it.

If you have any questions, whether its about our codebase or about the implementation approach, ask me.

**PROMPT: Policy optimization -- using merkle trees for address list function params**
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

Right now, policies are represented as nested merkle trees. Some fields within a policy are scalars, some are represented as merkle trees, and some are still represented as plain old arrays. 

The fields that are represented as plain old arrays should also be represented as merkle trees. Make the change to represent them as nested merkle trees.

If you have any questions, whether its about our codebase or about the implementation approach, ask me.

**ERC-7201 Prompt**
Our project uses storage libraries throughout. 

However, we mostly use a custom implementation to calculate the storage slot position. 

Instead, I want us to be ERC-7201 compatibile. 

Change all of our custom storage slot position calculations in all of our storage libraries to do it according to ERC-7201 and DON'T implement ERC-7201 yourself. Instead, use OpenZeppen to compute it so that you don't reinvent the wheel.

The only exception to this is @src/account/libraries/storage/LibAccountOrganizationAddressStorage.sol . That one storage library already correctly does something different and shouldn't be changed.

Note: you may need to precompute these storage slots.


**Optimize Members and Groups storage using Merkle Trees**
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

Right now, policies are represented as Merkle Trees. This gave us huge gas savings. 

Now, we want to similarly represent Groups and Members within an Organization as Merkle Trees to optimize storage use and reduce gas.

All Members in an organization should be represented by a single Merkle Tree. All groups should be represented as a single nested-merkle tree.

Note that this may allow you to drop the concept of a "Member ID" and allow you to represent a Member solely by their address. If this is the case, then please drop the "Member ID" concept if simplifies the code and concepts. 

Ask me any questions you have about the implementation or about our existing codebase.

Additional TODOS:
- [x] In LibOrganizationMembers.sol, modify `modifyMembers` to check that the organization admins are still members in the organization with the new MembersRoot to make sure we don't accidentally birck the organization. If the org admin is a group make sure that all the members of that group are still in the org.
- [x] In LibOrganizationGroups.sol, modify `modifyGroups` function to check that the organization Admin Group (if the admin is a group) is still in the organization after updating the groups merkle root to make sure we don't accidentally brick the organization. UPDATE: NO LONGER NEEDED THAT ADMINS CAN NO LONGER BE GROUPS.
- [x] In LibOrganizationAdmin.sol, modify `updateAdmin` function to check that the organization Admin Group (if the admin is a group) is still in the organization or the Admin Member (if the admin is a member) is still in the organization. If it's a group, make sure that all admin members are still in the organization as well. We want to make sure we don't accidentally "brick" the organization with a bad update. UPDATE: NO LONGER NEED TO CHECK THAT ADMIN GROUP IS IN GROUPS SINCE ADMIN CAN NO LONGER BE A GROUP.
- [x] In LibOrganizationInitialization.sol, modify `initialize` to also check that the Admin Group, and all Admin Members (whether admin is a group or just one member) are in the organization to make sure we don't brick the organization. UPDATE: NO LONGER NEED TO CHECK THAT ADMIN GROUP IS IN GROUPS SINCE ADMIN CAN NO LONGER BE A GROUP.

- [x] In LibOrganizationMembers.sol, rename `verifyMembership` to `isMemberInOrg` and `verifyMembershipOrRevert` to `verifyMemberInOrgOrRevert`
- [x] In LibOrganizationGroups.sol, rename `verifyGroupExists` to `isGroupInOrg`, `verifyMemberInGroup` to `isMemberInGroup`, and `verifyGroupMembership` to `isMemberInGroupAndGroupInOrg`. If any functions in OrganizationImplementation.sol wrap any of these functions, rename them as well.

- [x] In LibOrganizationMembers.sol, LibOrganizationGroups.sol, LibOrganizationAdmin.sol and possibly some other files, we duplicate the function to compute address leaves. Refactor so we use just one function and don't repeat ourselves. 

- [x] In LibOrganizationInitialization.sol, why is `_emitInitializedEvent` its own separate function? If there's no good reason for it, remove the function and just inline it. ANSWER: to prevent stack-too-deep errors. Should not inline it.

- [x] In LibOrganizationPolicy.sol, can `getValidApprovals` function be simplified such that we only need to check if the admin group exists in the organization once, rather than O(N) times where N is the number of approval signatures? If yes, please simplify it.

- [x] In LibOrganizationAccountSignatures.sol and LibOrganizationAccountTransaction.sol, we create a new `_isAuthorizedInitiator` function in each file, whereas before both files called the `_doesMatchInitiator` function from LibOrganizationPolicy.sol. Is this now duplicate code? If so, remove the new `_isAuthorizedInitiator` functions and just use the function from LibORganizationPolicy.sol like we used to (modify that old function if needed). Note that I actually think `_isAuthorizedInitiator` is a better name for the function in LibOrganizationPolicy.sol, so rename `_doesMatchInitiator` to that as part of the refactor.

**Initialize function prompt**
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

Right now, when deploying an Organization contract, we need to first deploy the contract via the factory contact, and then we need to call the `initialize` function. 

The initialize function currently just sets the:
- admin (adminType, adminAddresses, votingThreshold)
- guardian address

Now, we actually want it to also initialize all the Groups and Members in the organization too. 

Update the initialize function to also initialize all the groups and members in the organization too. 

Note that previously, since you could only intiailize the Admin (or Admin Group) and guardian, the initialize function would automatically create the Members/Group for the organization.

Now that the initialize function will initialize all members/groups in the organization as well, the logic for initializing the admin/admin-group can probably be simplified, as the members and groups will already be created.



**Merkle Root brick check prompt**
One of my big concerns with using Merkle roots for Groups and Members is that it's easy to "brick" the organization by accidentally updating Members, Groups, or the Admin such that the admins of the org are no longer valid (the Admin Member(s) or Admin Group are not in the org after an update).

In order to make that situation impossible, I want you to:
- [x] Make it no longer possible for the Organization Admin to be a Group. Instead, the Organization Admin can only be a custom list of Members, which should also be represented as a Merkle Tree. Note that you should also keep track of the number of admins in the list onchain too, because we'll need that later on. Note that this will also allow you to drastically simplify A LOT of things in the organization, because an individual Admin can still be represented as a Merkle Tree with one leaf, and a voting threshold of one.
- [x] In LibOrganizationMembers.sol, modify `modifyMembers` to check that ALL the organization admins are still members in the organization with the new MembersRoot to make sure we don't accidentally brick the organization. Note that you'll need to use that new storage variable that keeps track of the number of admins to be able to check for COMPLETENESS (that ALL the admins are still members in the organization, not just some)
- [x] In LibOrganizationAdmin.sol, modify `updateAdmin` function to check that ALL the new organizations Admins are still Members in the organization , so that we can't accidentally update the admin merkle tree to contain admins that are not Members of the organization
- [x] In LibOrganizationInitialization.sol, modify `initialize` to also check that ALL the Admin Members are Members in the organization to make sure we don't brick the organization.

Note: if there are any other things that need to be done to prevent "bricking" the organization, please also do them.

Additional TODOS:
- [x] In LibOrganizationAdmin.sol, rename the function `_verifyMembership` to `isMemberInTree`. Additionally, I think this function might be duplicating code that exists in LibOrganizationMembers.sol. Can you consolidate the code if possible to have less duplicate code? I prefer the final function to live in LibORganizationMember.sol and to have the name `isMemberInTree`. Same with 
- [x] Does SigningAdminsInOrgProofs struct also contain admin tree validation stuff? e.g. when checking admin auth for org operation, do we check that admin address is valid admin? ANSWER: Yes it does and yes we do.
- [x] In LibOrganizationInitialization.sol, the logic in the `_validateAdminConfiguration` function appears to be repeated elsewhere. Can we move that function to LibOrganizationAdmin.sol and replace other code with a call to this function? Specifically, I think we repeat the logic in that function in LibOrganizationAdmin.sol in the `updateAdmin` function. There might be other places where that logic is repeated, btw. If there is, consolidate from those other places too.

**FINAL MERKLE TREE GROUPS AND MEMBERS PR TODO**
- [x] Right now, Group IDs are bytes32. Can Group IDs be a uint256? Is so, change them to uint256.
- [x] Check if function LibOrganizationGroups.isMemberInGroupAndGroupInOrg is actually used. Even if it is, see if we can get rid of it or at least optimize it. Same with `isGroupInOrg`.
- [x] In LibOrganizationInitialization.sol, in the function `initialize`, move the call to `validateAllAdminsAreMembersOrRevert` to be before (above) where we set the storage variables for the members and groups roots. When done, all the storage variable will be set together in one place in the code of this function.
- [x] Update OperationType enum for Members and Groups. Before, we needed `CreateGroup`, `ModifyGroup`, `RemoveGroup`, `AddMembers`, `ModifyMember`, `RemoveMembers`. But now, we just need a new `ModifyGroups` and `ModifyMembers`. Use the new enum values for the `updateGroups` and `updateMembers` functions.
- [x] Remove old and used facet interface files (IGuardianFacet.sol, IOrganizationGuardianFacet.sol, IOrganizationMembersFacet.sol, IOrganizationGroupsFacet.sol)

- [x] In our project, we use merkle proofs in a lot of places. The issue is, the code is hard to read and maintain. I believe a big reason for that is due to our variables names. 

To improve readability, I want to rename fields in our various proof structs to make it more clear what the merkle proofs are for.

Here are the renamings I want to do:
  - In IOrganization.sol, in `InitializationParams`, rename:
    - `adminTreeProofs` to `adminInAdminTreeProofs`
    - `adminMemberProofs` to `adminInMembersTreeProofs`
  - In Policies.sol, in `InitiatorProofs`, rename:
    - `memberProof` to `initiatorInOrgMembersTreeProof`
    - `groupExistenceProof` to `groupInOrgGroupsTreeProof`
  - In Policies.sol, in `ApproverProofs`, rename:
    - `memberProofs` to `approverInOrgMembersTreeProofs`
    - `groupExistenceProof` to `groupInOrgGroupsTreeProof`
  - In LibOrganizationAdmin.sol, in `AllAdminsInOrgProofs` (formerly `AdminMembershipValidation`), rename:
    - `adminTreeProofs` to `adminInOrgAdminTreeProofs`
    - `memberTreeProofs` to `adminInOrgMembersTreeProofs`
  - In LibOrganizationAdmin.sol, in `SigningAdminsInOrgProofs` (formerly `AdminProofs`), rename:
    - `adminTreeProofs` to `adminInOrgAdminTreeProofs`
    - `memberProofs` to `adminInOrgMembersTreeProofs`

Do all the new names I want to use for fields make semantic sense given the context that they're used in? Are there any mistakes in my renamings where the new name is actually misleading or doesn't make sense?


**REFACTOR TODOS**
- [x] In LibOrganizationPolicy.sol, rename:
  - doesPolicyApplyToTransaction to isTransactionAllowedByPolicy
  - _doesMatchSourceAccount to _isSourceAccountAllowedByPolicy
  - _doesMatchDestination to _isDestinationAllowedByPolicy
  - _doesMathFunction to _isFunctionAllowedByPolicy 
- [x] In LibOrganizationPolicy.sol, inline the functionality of _doesMatchTransactionType in isTransactionAllowedByPolicy it makes more sense and is easier to read if it's inlined rather than being a separate function.
- [x] In LibOrganizationPolicy.sol, in the function `isTransactionAllowedByPolicy` extract logic for checking if the token is allowed for a token transfer to a new function called `_isTokenAllowedByPolicy` and the check for the token amount into a new function called `_isTokenAmountAllowedByPolicy`.
- [x] In LibOrganizationPolicy.sol, in the function `isTransactionAllowedByPolicy`    can we remove the outter conditional     `if (txType != Policies.TransactionType.Any) {` and just keep the conditionals inside? Would that still function the way we want? If yes, remove it.
- [x] Change `_isDestinationAllowedByPolicy` to `pure`

- [x] Make all functions that are not used by other files private if they're currently internal. Make sure to build to make sure we didn't screw anything up.
- [x] Standardize the use of the "_" prefix for all internal/private function names. Use a "_" prefix for all private functions. If a Library function is "internal" and used by other files, then don't add a "_" prefix. If it is "internal" and is not used by other files, then add the "_" prefix. External or public functions should never have a _ prefix. 
- [x] Standardize function names for boolean checks (they should be prefixed with "is" or "has"). Checks that revert on failure should have the format "verify*OrRevert()"
- [x] Create a function `validateImplementationIsWhitelisteOrRevert` in the ImplementationWhitelist contract and call that in OrganizationFactory.sol instead of just calling `isImplementationWhitelisted` and manually reverting in OrganizationFactory.sol. Similarly, use the new `validateImplementationIsWhitelisteOrRevert` in OrganizationImplementation.sol to remove the duplicated revert code.
- [x] Rename `isPolicyInTree` to `isPolicyInOrg`. It should also use the _computePolicyLeaf function instead of duplicating the code.
- [x] Get rid of the duplicate _getDomainSeparator() function, which is duplicated identically in three places. Create a shared LibOrganizationEIP712.sol library for it. (see agent conversation)
- [x] The token transfer detection logic in LibOrganizationPolicy.sol (isTransactionTokenTransfer, extractTokenRecipient, etc.) in LibOrganizationPolicy.sol is ERC-20 specific and could be moved to a dedicated LibTokenTransferUtils.sol for reusability and testing.
- [x] Rename token transfer functions in LibTokenTransferUtils.sol to be clear they're ERC20 specific (e.g. extractTransferRecipient should be more ERC20 specific)
- [x] In LibTokenTransferUtils, refactor out logic in `isTransactionTokenTransfer` to two functions to check if it's a native transfer or if its an ERC20 transfer.
- [x] Refactor LibOrganizationPolicy so that when a tx is a contract interaction, in isTransactionAllowedByPolicy, we call _isFunctionAllowedByPolicy and then areParametersAllowedByConstraints, instead of calling just _isFunctionAllowedByPolicy and it calls areParametersAllowedByConstraints under the hood.
- [x] Create a LibContractInteractionUtils.sol library and create an "extract function signature" function (unless openzeppein already has one) and use it everywhere we extract function signatures from transaction data. 
- [x] Rename @src/libraries/LibContractInteractionUtils.sol and @src/libraries/LibTokenTransferUtils.sol to not have the "Lib" prefixes to be consistent with other util libraries.
- [x] Update  LibTokenTransferUtils.sol to not check `transferFrom` (not supported). Also, make it revert instead of returning address(0).
- [x] Rename _validateParameter in LibOrganizationPolicy.sol to _isParameterAllowedByConstraint
- [x] Refactor _processContraints in LibOrganizationPolicy.sol because its an unreadable mess.
- [ ] Refactor time based constraints
- [x] In LibOrganizationAccountTransaction.sol, `_validateAndUpdateManualApproval` calls `_updateTimeLimitForAutoApprove(params, data, initiator, proofs.policy);` this makes no semantic sense. could `_updateTimeLimitForAutoApprove` be renamed, and then the call to it be moved from _validateAndUpdateManualApproval to _processApproval ? Do we need the _processAproval function at all or can we inline it into `validateTransactionApprovalOrRevert`? Also `validateAndUpdateManualApproval` should be renamed to end with "OrRevert"

**Files to refactor**
- [x] LibOrganizationPolicy.sol (except for time-based constraints)
- [x] LibOrganizationAccountTransaction.sol
- [x] LibOrganizationAccountSignature.sol
- [x] LibOrganizationAccountFactory.sol
- [x] LibOrganizationAdmin.sol
- [x] LibOrganizationEIP712.sol
- [x] LibOrganizationGroups.sol
- [x] LibOrganizationGuardian.sol
- [x] LibOrganizationInitialization.sol
- [x] LibOrganizationMembers.sol
- [x] LibOrganizationSignatures.sol
- [x] OrganizationFactory.sol
- [ ] OrganizationImplementation.sol

- [x] OrganizationProxy.sol
- [ ] AccountImplementation.sol
- [ ] AccountProxy.sol
- [ ] ImplementationWhitelist.sol
- [ ] ImplementationWhitelistProxy.sol

- [x] Create a reusable `validateDeployedByOrgOrRevert` function in LibOrganizationFactory.sol and reuse it in OrganizationImplementation.sol or wherever else we check if the account was deployed by the organization and revert.
- [x] UPDATE: NOT WORTH IT. NOT DOING. CODE IS MORE DIFFERENT THAN I ORIGINALLY THOUGHT UPON A CLOSER LOOK. Centralize Rejection Logic in LibOrganizationAccountTransaction: The rejection logic for AutoApprove policies in LibOrganizationAccountTransaction.sol could be more modular. Recommendation: Instead of specific _validateAutoApproveRejectionOrRevert, consider a more generalized _validateInitiatorAuthorization that can be reused for both approvals and rejections across different policy types.
- [x] Unify (and clearly specify) your signature encoding format
      Right now multiple modules assume “signer address can be extracted from the signature bytes”, but your SignatureUtils defines signatures as plain 65-byte ECDSA blobs.
      Example: LibOrganizationSignatures.extractSignerAddress() claims “first 20 bytes contain the signer address” and uses raw assembly:
      ```
          function extractSignerAddress(bytes memory signature) internal pure returns (address) {
        if (signature.length < 20) {
            return address(0);
        }

        address signer;
        /* solhint-disable no-inline-assembly */
        assembly {
            signer := mload(add(signature, 20))
        }
        return signer;
    }
    ```
    That extraction is then used in approval counting, admin signature counting, etc.:
    ```
            for (uint8 i = 0; i < signatureCount; ++i) {
            bytes memory signature = SignatureUtils.extractSignature(signatures, i);

            // Extract signer address from signature
            address signer = LibOrganizationSignatures.extractSignerAddress(signature);

            // Skip if signer is invalid
            if (signer == address(0)) continue;

            // ...
            if (!SignatureChecker.isValidSignatureNow(signer, messageHash, signature)) {
                continue;
            }
    ```
      Refactor recommendation: define one canonical “signature bundle” format (e.g., Safe-style with signer + signature type, or pure 65-byte ECDSA only), document it in one place, and have a single parsing/validation library that everything calls. This reduces the biggest audit burden: “what exactly is being signed, and how are signers derived?” 
- [x] Multiple files use the same signature length constant and extraction logic:
        // Each signature is 65 bytes (r: 32, s: 32, v: 1)
        uint8 signatureCount = uint8(signatures.length / SignatureUtils.SIGNATURE_LENGTH);
      Consider adding a SignatureUtils.getSignatureCount(bytes memory signatures) helper.
- [x] Centralize EIP-712 constants/typehashes. 
      You already centralized the domain separator (LibOrganizationEIP712), but you still inline long type strings in multiple libraries. Centralizing them as bytes32 constant TYPEHASH = keccak256("...") improves readability and prevents subtle mismatches between offchain signing and onchain verification. Similar EIP-712 Hash Computation Patterns
Files affected: LibOrganizationAdmin.sol, LibOrganizationAccountTransaction.sol, LibOrganizationAccountSignature.sol
Each file has similar hash computation patterns. Consider creating a shared helper in LibOrganizationEIP712.sol: function computeTypedDataHash(bytes32 structHash) internal view returns (bytes32) {
    return MessageHashUtils.toTypedDataHash(getDomainSeparator(), structHash);
}. This is partially addressed but could be more DRY.
- [x] Several functions have 8+ parameters:
      ```
      function setAdmins(
          bytes32 newAdminsRoot,
          uint256 newAdminCount,
          uint256 newVotingThreshold,
          uint256 salt,
          uint256 expirationTimestamp,
          bytes calldata signatures,
          LibOrganizationAdmin.SigningAdminsInOrgProofs calldata signingAdminsInOrgProofs,
          LibOrganizationAdmin.AllAdminsInOrgProofs calldata allAdminsInOrgProofs
      ) external onlyGuardian {
      ```
      Recommendation: Consider grouping common parameters into structs:
      ```
      struct AdminAuthParams {
        uint256 salt;
        uint256 expirationTimestamp;
        bytes signatures;
        SigningAdminsInOrgProofs signingAdminsInOrgProofs;
      }
      ```
      This would reduce cognitive load and stack depth issues.

- [x] Factor out CREATE2 address computation / deployment boilerplate
You have very similar CREATE2 patterns in OrganizationFactory and LibOrganizationAccountFactory. A shared LibCreate2-style helper (compute hash, deploy, verify mismatch) reduces duplication and makes address determinism easier to audit.
- [x] Fix comment/behavior drift
Example: TokenTransferUtils claims it detects both transfer and transferFrom, but the implementation only checks transfer(address,uint256). Refactor recommendation: either implement transferFrom support or update comments; drift like this is a common audit “red flag” even when harmless.
- [x] Typos / naming consistency. Example: _hasSufficentValidApprovalSignatures typo (“Sufficent”) in LibOrganizationAccountSignature (searchable around line 181 in that file). Renaming improves readability and reduces future copy/paste propagation.
- [x] Create a reusable `validateIsAccountDeployedByOrgOrRevert` function in LibOrganizationFactory.sol and reuse it in OrganizationImplementation.sol or wherever else we check if the account was deployed by the organization and revert.
- [x] UPDATE: Renamed `adminValidation` function param to `allAdminsInOrgProofs` and renamed struct `AdminMembershipValidation` to `AllAdminsInOrgProofs`. Also renamed `AdminProofs` to `SigningAdminsInOrgProofs` and `adminProofs` param to `signingAdminsInOrgProofs` for clarity.
- [ ] Ask AI agents (multiple models, each one twice) about opportunities to refactor again:
    We're getting closer to freezing our solidity smart contracts and preparing for an audit. Before that, we want to make sure the contracts are as readable and maintainable.
    
    Go through each one of our solidity files. Recommend opportunities (if any) to refactor or modify our code to make it more readable, maintainable, and easier to audit. 
    
    NOTE: Do NOT read my TODO.md file, as it will mislead you (many things have already been implemented or are no longer relevant). Just read our solidity files. 
    
    Also, i'm aware that we don't have good test coverage yet. I'm going to do that later, so don't think about that in your recommendation.
    
    I'm also aware that i need to precompute storage slots using ERC-7201, so don't think about or recommend that, as i'm going to do that shortly.
- [ ] Ask AI agents (multiple models, each one twice) about opportunities to use OpenZeppelin utils/helpers/libraries instead of our own code.
    We're getting closer to freezing our solidity smart contracts and preparing for an audit. Before that, we want to make sure the contracts aren't reinventing the wheel when they don't have to. In otherwords, we want to check to see if there are any opportunities to use standard OpenZeppelin helper/library/util functions/constants/events/etc instead of our own hand-rolled solutions. We prefer to use their battletested and trusted code over our own any where we can.

    Go through all of our solidity contracts and identify specific opportunities to use OpenZeppelin helpers/libraries/utils instead of our own code.

    NOTE: Do NOT read my TODO.md file, as it will mislead you (many things have already been implemented or are no longer relevant). Just read our solidity files. 
- [x] OZ opportunity: import OZ IERC20 and compare against IERC20.transfer.selector instead. This is more standard, avoids string-hash selectors, and is harder to accidentally mismatch.
- [x] Your contracts use several manual assembly blocks and precomputed constants to interact with EIP-1967 storage slots. OZ's ERC1967Utils and StorageSlot libraries provide safe, named alternatives.
LibAccountOrganizationAddressStorage.sol:
Change: Replace the manual BEACON_SLOT constant and sload assembly (lines 12-24) with ERC1967Utils.getBeacon().
Benefit: Reduces the risk of using an incorrect slot hash and uses the official OZ implementation for beacon retrieval.
Reference: src/account/libraries/storage/LibAccountOrganizationAddressStorage.sol
- [x] Potential Use of SafeCast
Your codebase frequently casts uint256 lengths and counts to uint8 or uint16 (e.g., uint8(signatures.length / SIGNATURE_LENGTH)).
Recommendation: Use SafeCast.toUint8() or SafeCast.toUint16() where appropriate.
Benefit: Although your current inputs (number of signatures) are unlikely to overflow these types, using SafeCast provides explicit protection against narrowing overflows, which is a common audit finding.
Reference: src/libraries/SignatureUtils.sol:35 and src/organization/libraries/policy/LibPolicyTimeBasedLimits.sol:75
- [x] You define typehash constants in LibOrganizationEIP712, but in LibOrganizationAccountSignature you re-derive the typehash from the literal string instead of using the existing constant. Example:
- [x] Replace hand-rolled constants/selectors with OZ-defined constants
ERC-1271 “magic value” constant
In LibOrganizationAccountSignature you hardcode 0x1626ba7e. OZ opportunity: use OpenZeppelin’s IERC1271.isValidSignature.selector for the success value (it equals 0x1626ba7e). This removes a “magic constant” and ties it to the canonical interface.
Note: OZ does not expose a standard constant for the invalid value; keeping 0xffffffff is fine.
- [x] Issue: Magic number 65 used for signature length
Throughout the code, 65 is used directly.  You already have SignatureUtils.SIGNATURE_LENGTH.
- [x]  ImplementationWhitelistImplementation.sol - Use Ownable2Step instead of Ownable ⭐⭐ Highly Recommended
- [x] Critical Fix: Memory Corruption in LibOrganizationSignatures.sol
I identified a significant memory corruption risk in the extractReviewSignatures function. The assembly loop copies data in 32-byte chunks (mload/mstore). Since signatures are 65 bytes long, reviewLength will be a multiple of 65 (e.g., 65, 130, 195). In the last iteration of the loop (where i is 64 for a 65-byte length), mstore will write 32 bytes starting at byte 64, effectively writing 31 bytes past the end of the reviewSignatures memory allocation. This can corrupt the "free memory pointer" or other variables allocated immediately after.

- [x] Rename validateAdminAuthAndConsumeNonceOrRevert to `validateAdminAuthAndConsumeNonceOrRevert`
- [x] Remove mentions to "Safe" from comment
- [x] Update comment in line 19 of src/organization/libraries/policy/LibPolicyDestination.sol to say native tokens
- [x] Do we need IUpgradeable? Should it just be consolidated into IOrganization?
- [x] LibOrganizationPolicyConstraints, you renamed constraintType to constraintType_. Undo that.
- [x] Rerun `make check` and fix changes
- [x] InLibOrganizationAdmin.sol you changed how we store the previous admin. Change it back to the one-liner. Similarly, change `getAdminPermission` back to the one-liner.
- [x] Rename "UnauthorizedCaller" error to "UnauthorizedGuardian"
- [x] The error thrown when running `setGuardian` is wrong when its the zero address
- [x] Should InititalizeParams be in types/Common.sol? UPDATE: YES
- [x] Should IOrganizationSignatureValidator be moved out of IOrganizationImplementation.sol?
- [x] Fix function orderings
- [x] Rename struct AdminPermission to AdminConfig.
- [x] Use AdminConfig struct in functions params like in the `initialize` function. Also you `AllAdminsInOrgProofs` for `initialize`
- [x] Remap foundry imports using "root" style, e.g:
  ```
  @openzeppelin/=lib/openzeppelin-contracts/
  forge-std/=lib/forge-std/src/
  interfaces/=src/interfaces/
  libraries/=src/libraries/
  types/=src/types/
  ```

**Gas Optimizations**
- [ ] Several internal library helpers take memory arrays/structs, even though upstream inputs are calldata, forcing implicit copies during validation. Refactor recommendation: convert internal helpers to accept calldata where possible (bytes32[] calldata, Policies.Policy calldata, Policies.ValidationProofs calldata). This both improves gas and reduces “what is copied where” mental overhead for auditors.
- [ ] Cache domain separator similar to how OZ's contracts do for gas efficiency.
- [ ] Gan we bitmap policy constraints and functions so we don't have to use nested merkle tree validation for them?


- [x] The _isBytesParameterAllowedByConstraint and _isStringParameterAllowedByConstraint functions are nearly identical. Extract a common helper to extract dynamic data and compute its hash. OR COULD WE JUST the bytes function for the string but cast it to bytes first???
- [x] Refactor @OrganizationImplementation.sol to reorder functions/variables/events/etc to group them based on their functionalities WHILE RESPECTING the required function ordering based on state mutations and visibility according to our linter.
- [x] Ask Cursor to fix all linter errors.
- [x] Rename ImplementationWhitelist.sol to ImplementationWhitelistImplementation.sol to be named conistently with respect to the rest of our proxy implementation contracts.
- [x] In @OrganizationImplementation.sol, update the executeAccountTransaction to have a comment that says that the validateAndConsumeNonceOrRevert adds replay protection for the auditors ("// REPLAY PROTECTION: Nonce is consumed BEFORE the external call to prevent reentrancy.")
- [ ] Can policyId just be rolled up into the Policy struct, so we don't need an extra function parameter everywhere?
- [x] Reorder all functions based on best practice (e.g. non-view pure functions first)
- [x] You inherit UUPSUpgradeable, which exposes upgradeTo and upgradeToAndCall as external functions. These functions rely on _authorizeUpgrade to control access. Currently, your _authorizeUpgrade is empty. Move the control access logic to _authorizeUpgrade.
- [x] Make sure we have 100% NatSpec coverage of public/external methods that have @notice and @param. You can run the `forge doc` command to help with this. We also want 100% NatSpec coverage of internal and private functions, but note that 
- [x] Ask Cursor how it would refactor @OrganizationImplementation.sol (if it needs to be refactored at all)
- [x] Add interfaces for OrganizationImplementation.sol and AccountImplementation.sol
- [x] UPDATE: NOT DOING BECAUSE WE USE V5 OF OZ CONTRACTS WHICH DON'T RECOMMEND THIS ANYMORE AND AN AUDITOR WILL LIKELY FLAG THIS. In @OrganizationImplementation.sol and @AccountImplementation.sol, Add a storage gap at the end of the contract (really at the end of storage variables, not at the literal end of the contract) to make sure that  that when we upgrade the contract we ensure storage layout safety for future versions of the contracts.
- [x] Check that OrganizationImplementation.sol doesn't hit the 24kb Spurious Dragon limit
- [x] If your libraries rely on hardcoded configurations, consider passing them into the initialize function and storing them as immutable in the implementation if they never change for that deployment. E.g. we set the "ContractType" during deployment. We also might be able to just hardcode them as constants... Double check what would be the best approach for these.

- [x] Revist ImplementationWhitelist contract deployment and initialization. Do we want to have a factory contract for it?

- [x] Do we even need to duplicate OpenZeppelin's SignatureHelper library functions? Can we not just ECDSA.recover or ECDSA.tryRecover directly in LibOrganizationAccountTransaction? We don't use SignatureHelper anywhere else, and just use ECDSA functions. ANSWER: YES WE NEED IT FOR FOR ERC1271 SIGNATURES BECAUSE GUARDIAN IS A SAFE.
- [x] Do we have a bug when it comes to our EIP1271 signature validation? In LibOrganizationSignatures we assume that the signatures first contain the initializer's signature, then the review signatures. But I think when it comes to ur EIP1271 signatures, the signatures field also contains the guarian signature. ANSWER: NO BUG. WE EXTRACT THE GUARDIAN SIGNATURE SEPARATELY ALREADY.
- [x] Right now, I always assume that the "guardian" signature we would check for EIP1271 signatures would be an EOA. But now, I'm realizing the "guardian" could be a Safe multisig wallet, so we would need to check that signature as though it were another smart contract signature (EIP1271). Does our current EIP1271 solution support that? ANSWER: WE ALREADY DO. ALL GOOD.

- [ ] Should we use our SignatureChecker library functions instead of ECDSA.recover and ECDSA.tryRecover everywhere to support ERC1271 signatures for Members? If we do this, I think we need to assume our signatures or more than 65 bytes everywhere because the signatures need to include the signer's address to use it with the SignatureChecker functions.

- [x] In multiple places in our code, we have multiple @dev tags for functions. Is that bad practice? If yes, change all NATSPEC where we have multiple @dev tags to only have one @dev tag by making it a multiline @dev tag if needed.

- [ ] Transactions at the exact boundary of a time window could be executed twice in quick succession (once at end of old window, once at start of new window). **Impact:** Slightly more transactions than intended at window boundaries. **Recommendation:** Document this behavior or add boundary protection.

- [x] Should the disaster recovery function to execute a transaction be timelocked? Should the ERC1271 recovery check be timelocked? UPDATE: nah
- [x] Add tests for new storage variables from recovery changes to test slot
- [ ] Changer comments in LibOrganizationRecovery to use "case: " syntax to be consistent with our styling
- [x] Separate out logic for guardian recovery and logic for Transaction/ERC1271 recovery into two other libraries rather than one monolothic LibOrganizationRecovery library. It's too hard to read, maintain and audit as one monolothic library. Refactor the Interface for the libraries too to reflact the new library structure.
- [x] Do we need the if statement checking `guardianLayout.isRecoveryGuardianUpdate` in `LibOrganizationGuardian` at all? Wouldn't our normal-flow for guardian update simply not work anyway if we initiated it via the recovery flow? Is this because the flows are mutually exclusive? Should we fully separate the flows and not make them mutually exclusive? UPDATE: changed to two separate flows for clarity and simplicity, at the cost of more env vars and duplicated logic.
- [x] Our function `disableTransactionAndERC1271Recovery` in `LibOrganizationRecovery` sets `recoveryLayout.pendingTxRecoveryEnableTimestamp = 0;`, which is also how we cancel the timelock for enabling recovery in the `cancelEnableTransactionAndERC1271Recovery` function. Should it be able to cancel the timelock for enabling it to? It's weird because it bypassing the check to see if the timelock is pending (that check is in the cancel function, not the disable function). UPDATE: keeping as is because it's more secure, just adding natspec to document
- [x] Guardian recovery timelock changes:
    - We basically have two timelocks for updating a guardian via recovery (first to enable the recovery mode, the second to update the guardian via the recovery flow once the mode is enabled). Both timelocks are the same duration. Is this unreasonable / overkill? Do we just need the one to enable the "mode"?
    - After changing the guardian address via the recovery flow, should we exit recovery mode for the guardian update?
    - If we change the recovery guardian flow to just one timelock, then there's no need for a "recovery mode" for the guardian recovery update at all, and we can simplify things significantly. This is the simplest solution, at the cost of not having two time-locks. The main question is: is having two timelocks that much more secure than just the one? Is it worth the trade off in terms of the complexity of our contracts right now?
    UPDATE: CHANGED CODE TO REMOVE THE CONCEPT OF "GUARDIAN RECOVERY MODE". NOW THERE'S JUST ONE TIME LOCK.
- [x] Update the styleguide to not use solhint ignore comments for line-length if the foundry formatter is undoing your changes, and instead add a comment telling foundry formatter to skip the next item so that it doesn't undo your changes. Then find anywhere in our code where we currently use the solhint ignore comments for line length and format the line to not be too long and replace the solhint ignore comment with the forge fmt ignore comment to not have forge fmt undo your changes.

- [x] Add a check in `initiateEnableTransactionAndERC1271Recovery` to see if recovery is already enabled and revert error if it is.
- [ ] OrganizationImplementation is getting horrendously long. Refactor OrganizationImplementation into other contracts that it inherits from, similar to what we did with IOrganization. Refer to our interface files for how to logically separate these.
- [ ] Refactor InitializationParams to use existing structs for grouping initialization params to make everything more auditable, maintainable, and readable.
- [x] Remove solhint-disable from recovery changes
- [x] Rename all "TimelockDuration" variable names/function names, function params, etc. to specify what units its in (hours, seconds, milliseconds, etc.)
- [x] Rename all variables/function params/etc named `canFinalizeAt` to `canFinalizeAtTimestamp`
- [x] Move `msg.sender != pendingGuardianAddr` and `pendingGuardianAddr == address(0)` from `acceptGuardian` in the guardian library to the external function in OrganizationImplementation to be consistent with rest of code. Probably want a modifier for it.
- [x] Would it be cleaner to split out LibOrganizationRecoveryStorage into two separate storage libraries: one for LibOrganizationGuardianRecovery and one for LibOrganizationTxRecovery? Or use structs inside the current LibOrganizationRecoveryStorage to group the storage variables to make it easier to parse? My goal is readability, maintainability, and making my auditor's lives easier.
- [x] Who can call `acceptGuardian` from OrganizationImplementation? Function in LibOrganizationGuardian does not discrimentate between the normal flow and recovery flow. ANSWER: It's anyone. The idea here is `pendingGuardian` shouldn't be. UPDATE: fixed -- moved access control logic for this and `acceptGuardianRecovery` to OrganizationImplementation.sol and use modifiers to be consistent with our codebase
- [ ] Can we refactor our any of our code between LibOrganizationGuardian and LibOrganizationGuardianRecovery or LibOrganizationTxRecovery to prevent duplicate/reused code?
- [x] Should there be a separate timelock duration for guardian updates that aren't for recovery? I don't like that we use the recovery timelock duration for something that's not for recovery? I think there should be. Also, there should be separate timelock durations for account/erc1271 recovery and guardian recovery. Basically, all timelocks should have their own recoveries. The guardian timelock duration should also be something passed into the main `initialize` function 
- [x] We previously split out an older library name LibOrganizastionRecovery.sol into two new libraries: LibOrganizationGuardianRecovery.sol and LibOrganizationTxRecovery.sol. But we didn't split out the test file. Split LibOrganizationRecovery.t.sol test file into two test files: one for the guardian recovery library and one for the transaction/erc1271 recovery library

**Deployment scripts changes**
- [x] You defined the interfaces for the Safe contracts. Do you need to? Is there a way to "import" them into our foundry project so that we don't have to rewrite them ourselves?
- [x] For step 3, you wrote:
      ```
      // Step 3: Deploy Platform Libraries (if needed - currently inlined)
      // Note: Libraries with public functions are automatically deployed by Foundry
      // during contract deployment. For deterministic addresses, we would deploy
      // them separately via CREATE2 and link. For now, Foundry handles this.
      ```
      Does that mean the libraries will not be deployed at the same address across chains in the current implementation? If so, then this is unaccepetable. Everything needs to be deployed at the same address across chains, including the libraries. Update the deployment script to make this happen.
- [x] For the `_computeSafeProxyAddress` function, why do you have to compute this yourself, are there no functions already available on the safe proxy factory contracts for computing this, so you don't need to recompute it? Check if there is, and if there is, use it instead of re-inventing the wheel yourself. 
- [x] Also, in other places where you precompute addresses, can't you use an OpenZeppelin helper to help precompute the address, instead of totally reinventing the wheel each time? If you can, then please use the OpenZeppelin helper.
- [x] Deleted the `DeployContract.s.sol` file -- no longer used
- [x] Rename deployed -> deployedAddress
- [x] Rename deployer -> deployerAddress
- [x] Rename guardianOwners -> guardianSafeOwners, guardianThreshold -> guardianSafeThreshold, deployerOwners -> deployerSafeOwners, deployerThreshold -> deployerSafeThreshold
- [x] Add NATSPEC comments to all files in @script. 
- [x] In ICreate2Factory.sol we define the interface `ISafeSingletonFactory` . Do we need to? Can we not use the contract/interface directly from a foundry library/module, instead of having to reimplement it ourselves? If it's possible to use a contract/interface directly from a foundry library/module, do so and delete this interface.
- [x] In ICreate2Factory.sol we define the interface `ICreate2Factory`.  Do we need to? Can we not use the contract/interface directly from a foundry library/module, instead of having to reimplement it ourselves? If it's possible to use a contract/interface directly from a foundry library/module, do so and delete this interface.
- [x] In Create2Deployer.sol, you have a function isFactoryAvailable. Rename it to `isContractDeployedAtAddress` and use it everywhere in our scripts and script libraries where we check if something is deployed (in several places we just check that `code.length` of an address is > 0 instead of calling the function).
- [x] Rewrite DeployContracts.s.sol to use a more functional approach
- [x] Rewrite other scripts to use a more function approach too
- [x] In Create2Deployer.sol, change `getCreate2Factory` to just get the factory from the env variable and then have it check if it exists. If it doesn't, then throw and stop the script. Then, create a new script for deploying the Arachnid Factory contract if it doesn't exist yet (use built in foundry libraries or modules to do as much of this as possible instead of reinventing the wheel). The new work flow will be:
1. Run script to deploy arachnid factory (if it's not already and if you can)
2. Run script to deploy SafeSingletonFactory (if you there's no arachnid already. If there is, then this script should throw and warn you).
3. Run script to deploy libraries using the available factory from env var
4. Run script to deploy contracts using output from script to deploy libraries and using the available factory from env var
Update the readme to reflect this too.
- [ ] Per our workflow, `DeployContracts.s.sol` needs to be run after libraries have been deployed and with the `--libraries` flag. Can we check in the script that it's being run with the `--libraries` flag and revert if not? If we can check, then make the change. Also, move the parts in DeployContracts.s.sol in the `run` function that check/fetch the factory address and verify the libraries to the very top of the script. Our script should through if libraries aren't deployed where we expect.
- [x] Multiple scripts have a _getCreate2Factory function. Refactor them into one function so we don't reuse it that's in a new script helper library. If there's anything else related to Create2 that's reused in multiple places or simply makes sense to move there, move it there.
- [ ] Add comments to DeployLibraries.s.sol
- [ ] Hand-refactor DeployContracts.s.sol
- [ ] In DeployContracts.s.sol we have logic specific to deploying our Safes , move those into a new script helper library for readability and maintainability. If certain types/structs are then used in multiple places as a result of the refactor, consolidate them in a Types.sol file that's specifically for scripts.
- [ ] Hand-refactor DeployLibraries.s.sol
- [ ] Hand-refactor DeploySafeSingletonLibrary.s.sol
- [ ] Add script to deploy arachnid factory if not on chain
- [ ] Change all scripts to use revert strings instead of custom errors and update the styleguide to specifically say to use revert strings in scripts, but custom errors (with no revert string) in production contracts.
- [ ] Get rid of empty `catch` block in `_getCreate2Factory` in DeployLibraries.s.sol
- [x] Separate out the scripts for deploying the libraries and deploying everything else into separate script files (currently everything is in the `DeployPlatform.s.sol` command). If you need to, separate out shared helpers into a separate file. Have a DeployLibraries script and a DeployContracts script. Update README and bash script to take this into account.
- [x] Remove all occurrances of "Onchain Custody" and replace with "Multi-layer Security (MLS) Wallet"
- [ ] You should only have one interface per interface file. Extract the new interfaces you wrote into their own files
- [ ] Go through all the files you wrote and apply our styleguide to them.
- [ ] Fix the warning: "Natspec memory-saf-assembly special comment for inline assembly is deprecated and scheduled for removal. Use the memory-safe block annotation instead."
- [ ] Run `make check` and fix any warnings

**DO THESE AFTER ANY CHANGES**
- [x] Get rid of `contractType` in the upgrades storage library. I'm pretty sure we don't even use it anywhere (double check me that we don't use it anywhere though in case i'm wrong)
- [ ] Install `aderyn` stack analysis (run using `aderyn .` or `aderyn ./**/.sol`) and add it to our `make check` command and fix all issues
- [ ] Use Trail of Bits' Claude Code skills to audit our contracts: https://github.com/trailofbits/skills?tab=readme-ov-file
- [x] Change foundry.toml to have `evm_version = "paris" # Force older opcodes (No PUSH0) for maximum compatibility ` for the compiler settings (put under `solc` version line)
- [x] Format and compile our smart contracts project using foundry. Identify all warnings and linter errors and fix them. Make sure there are no compiler warnings. I want to check that there are no compiler warnings with and without the `--via-ir` flag (if compatible -- let me know if it's not compatable with the flag).
- [x] Choose and lock the best solidity compiler version for all files (should not have floating pragma).
- [x] Run slither to make sure there are no issues.
 
- [ ] Ask Cursor about common vulnerabilities from chat with Gemini
- [ ] Ask Gemini and Cursor about which solidity version to use
- [ ] Ask Gemini about which SPDX license to use
