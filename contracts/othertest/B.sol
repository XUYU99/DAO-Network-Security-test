// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./C.sol";

contract B is C {
    function getFavorNumber() public pure returns (uint256) {
        uint256 favorNum = 222333;
        return favorNum;
    }
}
