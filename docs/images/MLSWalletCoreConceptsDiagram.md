# Core Concepts Diagram

```mermaid
flowchart TB
    %% ===== OWNERSHIP STRUCTURE =====
    subgraph org["Organization Contract"]
        direction TB
        subgraph state["Stored State"]
            Members["Members"]
            Groups["Groups"]
            Admins["Admins"]
            Policies["Policies"]
        end
    end

    org -->|"owns/manages"| Account1["Account 1<br/>(holds assets)"]
    org -->|"owns/manages"| Account2["Account 2<br/>(holds assets)"]
    org -->|"owns/manages"| AccountN["Account N"]

    %% ===== OPERATION FLOWS =====

    %% Admin Operations - enter and stay in Organization
    AdminOps(["Admin Operations<br/>(modify state)"])
    AdminOps ==>|"enter"| org

    %% Account Transactions - enter Organization, exit through Account
    AcctTx(["Account Transactions<br/>(transfers, DeFi, etc.)"])
    AcctTx -->|"1. enter"| org
    org -->|"2. forward & execute"| Account1

    %% Account Signatures - enter Account, delegate to Org, return through Account
    ExtCaller(["External Caller<br/>(e.g., Permit2, CoW)"])
    ExtCaller -.->|"1. isValidSignature()"| Account2
    Account2 -.->|"2. delegate validation"| org
    org -.->|"3. return result"| Account2

    %% Styling
    classDef orgStyle fill:#e1f5fe,stroke:#01579b,stroke-width:2px
    classDef accountStyle fill:#fff3e0,stroke:#e65100,stroke-width:2px
    classDef adminOpStyle fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px
    classDef txOpStyle fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    classDef sigOpStyle fill:#fce4ec,stroke:#c2185b,stroke-width:2px,stroke-dasharray: 5 5

    class org orgStyle
    class Account1,Account2,AccountN accountStyle
    class AdminOps adminOpStyle
    class AcctTx txOpStyle
    class ExtCaller sigOpStyle
```

## Legend

| Flow | Description | Path |
|------|-------------|------|
| **Admin Operations** (solid thick arrow) | Modify Organization state (members, groups, policies, admins) | Organization → Organization |
| **Account Transactions** (solid arrow) | Execute transactions from Accounts | Organization → Account |
| **Account Signatures** (dashed arrow) | ERC-1271 signature validation | Account → Organization → Account |
