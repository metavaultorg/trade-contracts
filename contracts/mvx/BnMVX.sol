// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../tokens/MintableBaseToken.sol";

contract BnMVX is MintableBaseToken {
    constructor() public MintableBaseToken("Bonus MVX", "bnMVX", 0) {}

    function id() external pure returns (string memory _name) {
        return "bnMVX";
    }
}
