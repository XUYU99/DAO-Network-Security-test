// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./B.sol";

contract A is B {
    function getName() public pure returns (uint256) {
        uint256 fname = 111222;
        return fname;
    }
}
