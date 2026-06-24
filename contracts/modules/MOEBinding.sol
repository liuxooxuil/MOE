// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./MOEBase.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

abstract contract MOEBinding is MOEBase {
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(address => mapping(address => bool)) public preUps;
    mapping(address => EnumerableSet.AddressSet) private upsChildList;

    struct User {
        address up;
        uint256 bnbTotal;
        uint256 lpTotal;
        uint256 staticDrawAt;
        uint256 directTotal;
        uint256 directBuyTotal;
        uint256 validTotal;
        bool staticDrawStatus;
        bool isBuy;
    }

    mapping(address => User) public users;

    function isCanBindInviter(address from, address to) public view returns (bool) {
        if (users[from].up == address(0) && from != inviteAddress && 
            to != _uniswapPair && from != _uniswapPair) {
            return false;
        }
        if (preUps[from][to] || from == to) return false;

        address current = to;
        uint8 depth = 0;
        while (current != address(0) && depth < 25) {
            if (current == from) return false;
            current = users[current].up;
            depth++;
        }
        return true;
    }

    function getUpsChildList(address account) public view returns (address[] memory) {
        return upsChildList[account].values();
    }
}