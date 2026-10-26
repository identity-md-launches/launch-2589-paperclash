// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title paperclash (CLASH)
/// @notice A fixed-supply ERC-20 with the project's permanent social link.
/// @dev The deploying caller receives the entire supply. During the IdentityMD launch this is
/// the factory, which handles distribution. There are no administrative or additional mint functions.
contract Paperclash is ERC20 {
    /// @notice One billion tokens, expressed in the token's 18-decimal base units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @notice Project social URL for coin pages and other integrations to display.
    string public constant SOCIAL_URL = "https://x.com/robobet_fun";

    constructor() ERC20("paperclash", "CLASH") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
