# paperclash test properties

The original `Paperclash.t.sol` suite remains intact. It covers deployment, exact
metadata and social URL, mint/transfer/approval events, ERC-20 failures, absent
administrative entry points, and token movements used during a launch.

The additions use the five discovery perspectives from the supplied Pashov fizz
reference and the algebraic-property and failure-review guidance from the supplied
Trail of Bits property-based-testing reference. The tests are original Solidity;
they require only the dependencies already vendored in this repository.

## Discovery and coverage

| Perspective | Property and basis | Coverage |
| --- | --- | --- |
| Conservation | The constructor creates exactly `10**27` base units (`src/Paperclash.sol:12,17`). Transfers must preserve this supply and the sum of balances. | Existing supply/model invariant; new split-transfer and round-trip properties. |
| State transitions | Approval replaces one owner's allowance for one spender. Spending consumes finite approval; rejection must roll back all changes (`ERC20.sol:132,154,284,305`). | Approval idempotence/isolation, failed delegated overdraw and zero-recipient properties, model checks after invalid approvals and transfers. |
| Round trips and rounding | CLASH transfers have no tax or unit conversion (`ERC20.sol:188`). Returning an amount restores balances, and splitting a transfer cannot change its result. | Repeated positive round trips, split direct/delegated transfers, and a stateful round-trip handler that also checks the intermediate balances. |
| Adversarial sequences | Self-transfers cannot bypass available balance; unlimited approval cannot create funds; returning funds cannot restore spent authorization (`ERC20.sol:193,305`). | Overdraw with identical sender/recipient, empty/refilled holder with infinite approval, and exhausted-allowance replay properties. |
| Token-specific behavior | `uint256.max` alone is infinite approval. Zero transfers succeed for valid accounts and emit `Transfer`; the one-unit case must work (`ERC20.sol:109,154,215,307`). | Largest finite allowance, self-approval, zero delegated transfer event, and one-base-unit transfer/approval/return tests. |

`ERC20.sol` above means
`lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol`. The expected supply,
name, symbol, decimals, and social URL are literal task expectations, not values
derived from the contract under test. No vault, shares, pricing, or conversion
properties apply to this token.

## Stateful model

Four actors form a closed set of holders and spenders. Transfers, approvals,
revocations, delegated transfers, invalid direct transfers, invalid approvals,
delegated transfers to zero, and round trips run in random order. Independent ghost
balances and allowances update only after expected successful operations. Failed
operations must return the exact ERC-6093 error and leave the model unchanged.

After every action, the invariants check all four balances, all sixteen actor
allowances, zero-address allowances, the complete supply, excluded-account
balances, and metadata. The round-trip handler checks both legs without changing
the final model. Unexpected handler reverts fail the campaign. A deterministic
handler test pins positive finite/infinite spending, both failure reasons,
revocation, full-balance movement, and invalid-address paths, checking the model
after each action.

Inline settings run each new fuzz property 1,000 times and the invariant campaign
for 256 sequences of 128 actions. New fuzz inputs use bounds without discarded
assumptions. Plain tests pin zero, one base unit, full supply, `uint256.max - 1`,
and `uint256.max` alongside the original boundary tests.

## Verification

Run `forge build` and `forge test` with
`FOUNDRY_FUZZ_SEED=0xa8eb6ce12f50aaa16f8c535db1795289777a500df4093848ffc91c28b6fc5eb8`.
Both commands support `--offline` using the vendored dependencies and installed
Solidity 0.8.26 compiler. Build artifacts can be kept in scratch by setting
`FOUNDRY_OUT=test/scratch/out` and `FOUNDRY_CACHE_PATH=test/scratch/cache`.

These tests exercise the actual Paperclash contract. The provided protected
factory/Uniswap checks belong to the separate launch harness, whose contracts and
deployment inputs are not in this repository. The local suite does not claim to
execute swaps or update an external coin page.
