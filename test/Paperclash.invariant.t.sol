// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Paperclash} from "../src/Paperclash.sol";

/// @dev Maintains independent balance and allowance accounting for four token holders.
contract PaperclashHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Paperclash private immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(Paperclash token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        expectedBalance[actors_[0]] = SUPPLY;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool unlimited) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        // Exercise small approvals and the full uint256 domain, including finite values above supply.
        if (unlimited) amount = type(uint256).max;
        else if (amount % 2 == 0) amount = bound(amount, 0, SUPPLY);
        else if (amount == type(uint256).max) amount -= 1;
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[owner][spender] = 0;
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amount, bool valid) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 approved = expectedAllowance[from][spender];
        uint256 held = expectedBalance[from];
        if (valid) {
            amount = bound(amount, 0, held < approved ? held : approved);
        }

        bool expectedSuccess = amount <= held && amount <= approved;
        vm.prank(spender);
        (bool success, bytes memory result) =
            address(token).call(abi.encodeCall(token.transferFrom, (from, to, amount)));
        assertEq(success, expectedSuccess, "unexpected transferFrom authorization or balance result");

        if (success) {
            assertTrue(abi.decode(result, (bool)));
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
            if (approved != type(uint256).max) {
                expectedAllowance[from][spender] -= amount;
            }
        } else if (amount > approved) {
            assertEq(
                result,
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount),
                "wrong allowance failure"
            );
        } else {
            assertEq(
                result,
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount),
                "wrong balance failure"
            );
        }
    }

    function invalidTransfer(uint256 fromSeed, uint256 toSeed, uint256 amount, bool zeroRecipient) external {
        address from = actors[fromSeed % actors.length];
        address to = zeroRecipient ? address(0) : actors[toSeed % actors.length];
        uint256 held = expectedBalance[from];
        amount = zeroRecipient ? bound(amount, 0, held) : bound(amount, held + 1, type(uint256).max);
        bytes memory error = zeroRecipient
            ? abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
            : abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount);
        _assertRejected(from, abi.encodeCall(token.transfer, (to, amount)), error);
    }

    function invalidApproval(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        _assertRejected(
            owner,
            abi.encodeCall(token.approve, (address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
    }

    function transferFromToZero(uint256 fromSeed, uint256 spenderSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        // Reach receiver validation after spending the allowance, so rollback is checked by the model.
        amount = bound(amount, 0, expectedAllowance[from][spender]);
        _assertRejected(
            spender,
            abi.encodeCall(token.transferFrom, (from, address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
    }

    function roundTrip(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        uint256 fromIndex = fromSeed % actors.length;
        address from = actors[fromIndex];
        address to = actors[(fromIndex + 1 + toSeed % (actors.length - 1)) % actors.length];
        uint256 fromBefore = expectedBalance[from];
        uint256 toBefore = expectedBalance[to];
        amount = bound(amount, 0, fromBefore);

        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), fromBefore - amount);
        assertEq(token.balanceOf(to), toBefore + amount);
        vm.prank(to);
        assertTrue(token.transfer(from, amount));
        assertEq(token.balanceOf(from), fromBefore, "round trip lost or created value");
        assertEq(token.balanceOf(to), toBefore, "round trip changed counterparty balance");
        // The model stays unchanged: this operation must be an identity for balances and allowances.
    }

    function _assertRejected(address caller, bytes memory data, bytes memory error) private {
        vm.prank(caller);
        (bool success, bytes memory result) = address(token).call(data);
        assertFalse(success, "invalid action succeeded");
        assertEq(result, error, "unexpected revert reason");
        // Do not update either ghost mapping: the invariants require every account to be unchanged.
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract PaperclashInvariantTest is StdInvariant, Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;

    Paperclash private token;
    PaperclashHandler private handler;

    function setUp() public {
        token = new Paperclash();
        address[4] memory actors =
            [makeAddr("holder 0"), makeAddr("holder 1"), makeAddr("holder 2"), makeAddr("holder 3")];
        handler = new PaperclashHandler(token, actors);
        assertTrue(token.transfer(actors[0], SUPPLY));

        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.revoke.selector;
        selectors[3] = handler.transferFrom.selector;
        selectors[4] = handler.invalidTransfer.selector;
        selectors[5] = handler.invalidApproval.selector;
        selectors[6] = handler.transferFromToZero.selector;
        selectors[7] = handler.roundTrip.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyIsFixedAndAllBalancesMatchTheModel() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 actual = token.balanceOf(actor);
            assertEq(actual, handler.expectedBalance(actor));
            sum += actual;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_AllAllowancesMatchTheModel() public view {
        for (uint256 i; i < 4; ++i) {
            assertEq(token.allowance(handler.actors(i), address(0)), 0);
            assertEq(token.allowance(address(0), handler.actors(i)), 0);
            for (uint256 j; j < 4; ++j) {
                address owner = handler.actors(i);
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }

    function invariant_MetadataNeverChanges() public view {
        assertEq(token.name(), "paperclash");
        assertEq(token.symbol(), "CLASH");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.SOCIAL_URL(), "https://x.com/robobet_fun");
    }

    /// @dev Pins the handler's meaningful success/failure branches without depending on random coverage.
    function test_HandlerExercisesStatefulBoundaries() public {
        handler.approve(0, 1, type(uint256).max, false); // Largest finite allowance.
        _assertModel();
        handler.transferFrom(0, 2, 1, 1, true);
        _assertModel();
        handler.transferFromToZero(0, 1, 1);
        _assertModel();
        handler.transferFrom(0, 2, 1, SUPPLY, false); // Approved, but the holder is now one unit short.
        _assertModel();
        handler.invalidTransfer(0, 0, SUPPLY, false); // Overdraw even when sender equals receiver.
        _assertModel();
        handler.invalidTransfer(0, 1, 0, true);
        _assertModel();
        handler.invalidApproval(0, type(uint256).max);
        _assertModel();
        handler.roundTrip(2, 0, 1);
        _assertModel();
        handler.revoke(0, 1);
        _assertModel();
        handler.transferFrom(0, 2, 1, 1, false);
        _assertModel();
        handler.approve(0, 1, 0, true);
        _assertModel();
        handler.transferFrom(0, 1, 1, SUPPLY - 1, true); // Spend the full balance with infinite allowance.
        _assertModel();
        handler.transfer(1, 0, SUPPLY - 1);
        _assertModel();
        handler.transfer(2, 0, 1);
        _assertModel();
        assertEq(token.balanceOf(handler.actors(0)), SUPPLY);
        assertEq(token.allowance(handler.actors(0), handler.actors(1)), type(uint256).max);
    }

    function _assertModel() private view {
        invariant_SupplyIsFixedAndAllBalancesMatchTheModel();
        invariant_AllAllowancesMatchTheModel();
        invariant_MetadataNeverChanges();
    }
}
