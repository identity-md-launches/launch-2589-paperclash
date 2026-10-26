# paperclash (CLASH)

`src/Paperclash.sol:Paperclash` is a fixed-supply ERC-20 for Ethereum (chain ID 1).
Its constructor mints all **1,000,000,000 CLASH** to the deploying caller in one
`Transfer` event. It uses the unmodified OpenZeppelin Contracts v5.0.2 ERC-20
implementation, with no transfer tax, burn, rebase, mint authority, owner, pause,
blacklist, upgrade mechanism, or external contract dependency.

## Token and social metadata

| Field | Value |
| --- | --- |
| Solidity identifier | `Paperclash` |
| Name | `paperclash` |
| Symbol | `CLASH` |
| Decimals | `18` |
| Supply in whole tokens | `1000000000` |
| Supply in base units | `1000000000000000000000000000` |
| Constructor arguments | None (`[]`) |
| Deployment value | `0` ETH |
| Social / X | https://x.com/robobet_fun |

`INITIAL_SUPPLY()` exposes the supply constant, and `SOCIAL_URL()` returns the
exact social URL above. The URL is permanent. The standard ERC-20 metadata
functions remain `name()`, `symbol()`, and `decimals()`.

**Social integration assumption:** the requested link is display metadata. The
on-chain getter and this documentation provide it to integrations. ERC-20 has
no standardized social field and cannot update third-party coin pages itself.
The launch/page operator must put **https://x.com/robobet_fun** in the coin's
X/Twitter social field; an integration can also read `SOCIAL_URL()` directly.
No X account authentication or external service call is needed by the token.

## Design and behavior

- Every successful transfer delivers the full requested amount and returns
  `true`. Transfers to the zero address revert. Zero-value transfers to valid
  addresses and transfers to oneself are supported.
- `approve` replaces an allowance and emits `Approval`. `transferFrom` requires
  an allowance for the caller, including when that caller is the deployer or
  the holder itself. A finite allowance decreases by the amount spent; the
  maximum `uint256` allowance remains unchanged. OpenZeppelin v5 does not emit
  an `Approval` event when spending an allowance, so clients should query
  `allowance()` for its current value.
- Insufficient balances, insufficient allowances, and invalid addresses revert
  with the vendored OpenZeppelin ERC-6093 custom errors. A failed transfer
  restores every balance and allowance through transaction rollback.
- Construction and transfers do not call outside contracts. Contract recipients
  need no callback or registration. There are no pool/factory exemptions to
  maintain, since every transfer is untaxed and unrestricted by recipient type.
- The contract rejects normal ETH transfers. It has no recovery function for
  tokens sent to itself or ETH forcibly credited to it. Holders should transfer
  only to destinations they control or intentionally fund.

The only supply-changing operation is the internal `_mint` invoked by the
constructor. The inherited internal mint/burn helpers have no external entry
point in `Paperclash`. No one has an ongoing administrative role.

## Build and check

Use Foundry with Solidity **0.8.26** installed. `foundry.toml` pins that compiler,
the Cancun EVM target, optimizer settings (200 runs), and `bytecode_hash = "none"`.
Dependencies are committed as ordinary Solidity files under `lib/`, including
licenses and provenance in `lib/VENDORED.md`. No dependency download, RPC,
environment file, FFI, or filesystem cheatcode permission is needed to build or
test. An offline machine needs only Foundry and the pinned compiler installed.

```sh
forge build
FOUNDRY_FUZZ_SEED=0xa8eb6ce12f50aaa16f8c535db1795289777a500df4093848ffc91c28b6fc5eb8 forge test
forge fmt --check
```

Unit and fuzz tests cover allocation to both an EOA and a CREATE2 factory,
constructor/transfer/approval events, exact delivery, self and zero transfers,
finite and infinite approvals, revocation, unauthorized spending, arithmetic
boundaries, rollback on failure, unsupported privileged calls, and token-side
launch distribution/claim/buy/sell movements. Stateful invariant tests compare
balances and allowances against an independent model over randomized transfers,
approvals, revocations, and authorized/unauthorized delegated transfers.

The default suite uses 512 runs per fuzz test and 128 sequences of 64 calls per
invariant. Tests create their own isolated fixtures, read no environment values,
and use no fork or predeployed contracts. The supplied protected launch checks
depend on the network's separate factory, manifest, and Uniswap v4 harness; the
local launch-flow test models the ERC-20 movements rather than an actual swap.

## Deployment and launch handoff

Deploy the creation bytecode for **`Paperclash`**, without constructor arguments
or ETH. There is no initialization step. The token does not need an owner,
recipient, router, oracle, signer, or other address configured. The constructor
must be invoked by the intended initial supply recipient: in the IdentityMD
launch this is the launch factory. It receives the entire supply, even if an
external wallet initiated the factory transaction. Direct deployment instead
credits the direct deployer, as requested.

The token itself allocates no shares. The launch factory is responsible for
distribution and pool creation using the supplied launch terms:

| Launch parameter | Supplied value |
| --- | --- |
| Chain | Ethereum, `1` |
| Pair | Native ETH |
| Pool allocation | `8000` basis points of supply: `800000000` CLASH |
| Swarm allocation | `100000000` CLASH, delivered by the factory to its distributor |
| Remainder allocation | `100000000` CLASH |
| Remainder recipient | `0x1ee3ffadfe138415a2ddaedeebe5f46616fa413d` |
| Initial market cap | `10000000000000000000` wei (10 ETH) |
| Pool fee | `12500` (1.25%, a pool fee; the token has no transfer fee) |
| Tick spacing | `60` |
| Initial-price provenance | `79228162514264337593543950336` |

The launch system derives the actual opening pool price from the market cap,
token supply, and deployed token address. Pool and distribution settings are
launch responsibilities and are not constructor arguments or token constants.
The later manifest step supplies `launch.json`; this project does not create it.
No application contracts are required, and test helper contracts are not launch
artifacts. This deliverable does not broadcast or sign transactions.

## After launch

The launch operator should verify the deployed source and metadata against the
build, confirm the supply and launch allocations, and publish the token's
address with the X social link on the coin page and relevant listings. The
social link must be copied exactly; publishing it is an off-chain responsibility.

There are no owner-only setters, maintenance transactions, or required follow-up
contract calls. Holders control their balances and approvals. Integrators should
request only the allowance they need, and users can revoke approvals with
`approve(spender, 0)`. Replacing a nonzero allowance has the usual ERC-20 ordering
race: a spender can use the old allowance before replacement, then the new one.
When changing spenders' limits, confirm revocation before granting a new limit.

The provided security checklist was reviewed against the token. No external
calls, signatures, randomness, pricing logic, or upgrade paths are introduced.
Local build, unit, fuzz, and invariant checks are the validation provided here;
Slither and Mythril were not run. Independent adversarial review and deployment
verification remain the launch process's responsibilities.
