# Onchain Custody Smart Contracts
This repository contains the smart contracts for Onchain Custody.

> [!WARNING]
> The contracts in this repository are a "rough draft" whose only purpose is to reason through how Onchain Custody might be implemented.
>
> **This code is not production-ready, or even audit-ready, and should not be trusted.** It is not gas-optimized, tested, or fully functional.

## Onchain Custody Overview
Onchain Custody is a new category of cryptocurrency custody. It is non-custodial and provides all the benefits of self-custody while being significantly more secure than all other forms of custody (traditional custody, self-custody, and MPC).


### Policy Engine
The heart of Onchain Custody is the **policy engine**. The policy engine allows users to specify rules (a.k.a. "policies") that dictate:
1. what transactions can be executed
2. who can execute them

 For example, an organization might set a policy that allows its finance team to transfer up to $100,000 in USDC per month, so long as 2 out of 3 members of the finance team approve the transaction.

Policies aren't limited to just simple token transfers, however. They can also be used to set rules for complex smart contract interactions and DeFi activities.


### Multiple Redundant Layers of Security
What makes Onchain Custody significantly more secure than all other existing forms of custody is that it uses **multiple redundant layers of security**.

Each of the layers operates independantly and all layers need to be compromised simultaneously in order for funds to be stolen. In contrast, other forms of custody, such as traditional custody, self-custody, and MPC, only need a single layer of security to be compromised.

In Onchain Custody, the three redundant layers of security are:
1. The dedicated mobile wallet
2. The offchain "Guardian" service 
3. The onchain smart contracts

![Onchain Custody Security Layers Diagram](docs/images/OnchainCustodySecurityLayersDiagram.svg)



In order to execute a transaction, all three layers independently run the policy engine to verify that the transaction is valid.

The order of operations is the following:
1. **The dedicated mobile wallet runs the policy engine locally.** 

    It will not allows users to approve a transaction if its policy engine fails to validate the transaction.
2. **The offchain Guardian service runs the policy engine in a secure centralized server.**
    
    It will not approve the transaction if its policy engine fails to validate the transaction.
3. **The smart contracts run the policy engine onchain.** 

    It will not allow the transaction to execute if its policy engines fails to validate the transaction. It will also prevent the transaction from executing if any approvals are missing from the account owners or the offchain Guardian service.

## Core Concepts
There are several core concepts in Onchain Custody:

1. **Organizations**

    An organization is a business or other non-individual entity that is using Onchain Custody.

2. **Members**

    Members are individuals who are a part of an Organization.

3. **Groups**

    Groups are collections of Members within an Organization. For example, an Organization might have a "Finance team" Group.

4. **Accounts**
    
    Accounts are where funds are stored and where transactions are executed. An Organization can have many Accounts.

5. **Policies**

    Policies are rules that dictate what types of transactions can be executed and by whom.

5. **Admins**

    An organization's Admin is a privileged Member or Group that can modify the Organization. Specifically, Admins can manage an Organization's Members, Groups, Accounts, Policies, Whitelist, and Admins. 
    
    If the Admin for an Organization is set to a Group, then an Approval Threshold must also be set. The Approval Threshold dictates how many Members of the Admin Group must approve an operation. 
    
    Any Member of the Admin Group can *propose* a change to the Organization (e.g. adding a new Member), but the change will not take effect until enough Members in the Admin Group approve the proposed change.

6. **Address Whitelists**

    Address Whitelists are lists of trusted addresses. By default, transactions cannot be sent to non-whitelisted addresses, however this is a setting that Admins can change.

7. **Transactions**

    Transactions can send tokens, take a DeFi action, or interact with any arbitrary smart contract from an Account. A Transaction can only be executed if a Policy has been set that explicitly allows the Transaction. 
    
    Dependening on the Policy, the Transaction may be automatically approved, automatically rejected, or require other Members of the Organization to approve it.



## Policies
TODO: @ittai Explain policies in depth. Outline all configurable parameters of a policy, how proposing and approving transactions are influenced by policies, and give specific examples with diagrams.

## Mobile Wallet
Onchain Custody's dedicated mobile wallet is used by Organization Members and Admins to approve and reject transactions and other actions.

Under the hood, the mobile wallet securely stores a private key on a Member's mobile device. That private key is used to cryptographically sign approvals and rejections. 

The mobile wallet hosts a variety of features not found in other wallets that provide superior security and user experience.

### Mobile Wallet Security Features
The dedicated Onchain Custody mobile has a suite of security features that make it significantly more secure that other hardware and software wallets:

1. **The mobile wallet can only be used with Onchain Custody to limit the attack surface.**

    In other forms of custody, such a self-custody (i.e. multisignature wallets), users can manage their cryptographic private keys using any external wallet, like Metamask or Ledger. 
    
    Those wallets can be used to sign *any* transaction and can be used with *any* decentralized application. If the wallet is used with a malicious or compromised decentralized application, the user can be tricked into signing a malicious transaction with the same private key that manages their funds, potentially causing their funds to be stolen.

    By having a dedicated mobile wallet that can only be used with Onchain Custody, user's private keys aren't being used to interact with other potentially dangerous applications.

2. **The mobile wallet shows users what they're *actually* approving.**
    
    A well known security limitation of many wallets, especially hardware wallets like Ledger, is "blind signing". Instead of displaying a human-readable explanation of what is being signed, these wallets display an obscure technical string of letter and numbers that users can't interperet.

    Users are therefore likely to accidentally approve malicious transactions.

    In contrast, Onchain Custody's dedicate mobile wallet decodes transactions into a human-readable format locally on the user's device, so they know exactly what the transaction they're signing will do. This makes it possible for users to easily identify and reject malicious transactions.

    ![Blind signing vs human-readable explanations](docs/images/OnchainCustodyMobileWalletDataDecodingDiagram.svg)

3. **The mobile wallet runs the Policy Engine locally to verify that a transaction is actually valid.**

    This is part of Onchain Custody's approach of having "multiple redundant layers of security". Before a user can approve a transaction, the Policy Engine runs locally on their device to determine if the transaction is valid to prevent them from being present malicious transactions in the first place.

4. **The mobile wallet stores private keys in secure hardware enclaves and trusted execution environments (TEE).**

    Similar to hardware wallets, the mobile wallet secure stores private keys in Secure Enclaves and Trusted Execution Environments (TEE) which isolate the private keys and prevent other applications from accessing them at a hardware level.

5. **The mobile wallet is harder compromise with malware.**

    Due to the locked-down and sandboxed nature of modern mobile operating systems, it is signficantly more difficult for attackers to install malware on a user's mobile device than it is on their desktop, and the scope of what the malware can accompolish is far more limited.

    For example, in the Radiant Capital incident where over $50M was stolen, attackers compromised the computers used by Radiant Capital's mutlsig signers with malware. The malware intercepted transactions sent to their Ledger hardware wallets, replacing them with a malicious transaction. 
    
    Along with the "blind signing" limitations of their Ledger wallets, the signers were tricked into signing the malicious transaction that resulted in the theft of the organization's funds.



## Smart Contracts
### Organizations and Accounts
There are two main abstractions represented as smart contracts in Onchain Custody:
1. **Organizations**
        
    Each real-world organization is represented onchain by a dedicated organization smart contract. That contract is a source of truth for the organization's state, such as its members, groups, policies, admins, etc. Funds are *not* stored in the organization contract.

    *Located at `src/organization/OnchainCustodyOrganizationDiamond.sol`*

2. **Accounts**

    Funds are stored in "account" smart contracts (i.e. "smart accounts" or "smart contract wallets"). Each organization can have one or more accounts. Account smart contracts interact with their corresponding organization contracts to access important information regarding the organization. For example, when executing a transaction, an account contract will fetch its  organization's policies from the organization contract.

    *Located at `src/account/OnchainCustodyAccountDiamond.sol`*



![Onchain Custody Core Contracts Diagram](docs/images/OnchainCustodyCoreContractsDiagram.svg)


### Guardian protection
Every external and public function on any Onchain Custody contract is protected by the Offchain Guardian.

**That means that the first thing any external or public function does is check if `msg.sender` is the Offchain Guardian Service's EOA address.**

This is an important component of Onchain Custody's philosophy of "multiple redundant layers of security". 

In the unlikely scenario that an exploit is found further on in the smart contracts, a malicious actor would be unable to execute the exploit, unless they also simultaneously compromise the Offchain Guardian Service. This significantly increases the difficulty of an attack, and is a unique layer of security not provided by other custody solutions.

This similarly protects against attack scenarios where an attacker compromises the mobile devices of all the transactions signers and tricks them into signing a malicious payload. The attacker would not be able to execute the malicious transaction without also simultaneoulsy compromising the Offchain Guardian Service.

In the event that the Offchain Guardian Service is unavailable, users can use the Disaster Recovery mechanism to withdraw their funds out of Onchain Custody without the Offchain Guardian Service's involvement. 

>![WARNING]
> At the time of this writing, the Disaster Recovery mechanism has not yet been implemented. It will be implemented at the time of public release to ensure censorship resistance.


### Upgradability (ERC-2535 Diamond Standard)

> [!WARNING]
> We are exploring using the [ERC-1822 Universal Upgradeable Proxy Standard (UUPS)](https://eips.ethereum.org/EIPS/eip-1822) instead of the [ERC-2535 Diamond Standard](https://eips.ethereum.org/EIPS/eip-2535) for upgradability due to the heavy interdepencies between the diamond cut facets in Onchain Custody.

The smart contracts are upgradable according to the [ERC-2535 Diamond Standard](https://eips.ethereum.org/EIPS/eip-2535) by Nick Mudgen.


Onchain Custody's implementation of the ERC-2535 Diamond Standard is based on Nick Mudgen's [diamond-3-hardhat](https://github.com/mudgen/diamond-3-hardhat) reference implementation, with some notable changes:

1. **Facet cuts must be whitelisted.**

    In order to "cut the diamond", the facet cuts (facet addresses and selectors) must be whitelisted by a separate and global whitelist. 

    This is to negate attacks where users might be tricked into signing malicious payloads that cut the diamond in n efarious ways.

    The whitelist is implemented by `src/diamond/FacetCutsWhitelist.sol`. It is referenced by `src/diamond/libraries/LibDiamond.sol` in the function `enforceFacetsAreWhitelisted`.

2. **Diamond cuts require approval from an organization's admins.**

    In order to cut a diamond, sufficient approval signatures must be provided from the organization's admins.

    This is implemented in `src/diamond/facets/DiamondCutFacet.sol` in the function `diamondCut`.

3. **Diamond cuts require approval the offchain Guardian service.**

    In order to cut a diamond, the offchain Guardian service must also explicitly approve the action. This is part of Onchain Custody's **"multiple redundant layers of security"** model.

    This is implemented in `src/diamond/facets/DiamondCutFacet.sol` in the function `diamondCut`.


The implementation of the ERC-2535 Diamond Standard for Onchain Custody can be found in the directory `src/diamond`:
```
src/
├── diamond/
│   ├── Diamond.sol
│   ├── FacetCutsWhitelist.sol
│   ├── facets/
│   │   ├── DiamondCutFacet.sol
│   │   └── DiamondLoupeFacet.sol
│   ├── interfaces/
│   │   ├── IDiamondCut.sol
│   │   ├── IDiamondLoupe.sol
│   │   ├── IERC165.sol
│   │   └── IFacetCutsWhitelist.sol
│   └── libraries/
│       └── LibDiamond.sol
```


There are only two smart contracts in Onchain Custody that are upgradable:
1. **The Organization smart contract**
        
    Diamond is located at `sr/corganization/OnchainCustodyOrganizationDiamond.sol`

    Facets are located at `src/organization/facets/`

2. **The Account smart contract**

    Diamond is located at `src/account/OnchainCustodyAccountDiamond.sol`

    Facets are located at `src/account/facets/`




### Organizations
#### Files
```
src/organization
├── facets
│   ├── OrganizationAccountFactoryFacet.sol
│   ├── OrganizationAdminFacet.sol
│   ├── OrganizationGroupsFacet.sol
│   ├── OrganizationGuardianFacet.sol
│   ├── OrganizationInitializationFacet.sol
│   ├── OrganizationMembersFacet.sol
│   ├── OrganizationPolicyFacet.sol
│   └── OrganizationWhitelistFacet.sol
├── interfaces
│   ├── IOrganizationGroupsFacet.sol
│   ├── IOrganizationGuardianFacet.sol
│   └── IOrganizationMembersFacet.sol
├── OnchainCustodyOrganizationDiamond.sol
├── OnchainCustodyOrganizationFactory.sol
├── OrganizationInit.sol
└── OrganizationStorage.sol
```

#### Accounts

Each Account is represented as a Diamond proxy, which can be found at `src/account/OnchainCustodyAccountDiamond.sol`.

All facets for Accounts are located at `src/account/facets/`.

#### Transaction execution and rejection

The facet that's responsible for transaction execution and rejection on an Account is `src/account/facets/AccountTransactionFacet.sol`.

It has two external functions that are responsible for transaction execution and transaction rejection:

```solidity
 function executeTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint256 salt,
        bytes memory signatures
    ) external;

 function rejectTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint256 salt,
        bytes memory signatures
    ) external;
```

Both of these functions, like all other external or public functions in Onchain Custody, require `msg.sender` to be the Guardian service's EOA address.










#### Signature replay protection
> [!WARNING]
> The use of non-sequential nonces to prevent signature replays is still in the investigation phase, and may be replaced with a traditional sequential nonce, like in Safe smart accounts, if issues are found during consultations with audit firms.

Most self-custody smart accounts, like Safe, use a sequential nonce to prevent signature replay attacks. This however comes with an unituitive user experience, where transactions must be executed (or rejected) in the order they were proposed.

Instead, Onchain custody uses a non-sequential nonce to prevent signature replay attacks, while providing a more intuitive user experience where transactions can be executed (or rejected) in any order.





#### Files
```
src/account
├── AccountInit.sol
├── OnchainCustodyAccountDiamond.sol
├── facets
│   ├── AccountAdminFacet.sol
│   ├── AccountGuardianFacet.sol
│   ├── AccountOrganizationAddressStorage.sol
│   ├── AccountTransactionFacet.sol
│   └── AccountTransactionFacetStorage.sol
└── interfaces
    └── INativeTokenReceivedEventEmitter.sol
```