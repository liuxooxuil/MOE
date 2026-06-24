// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./MOEBinding.sol";

abstract contract MOERewards is MOEBinding {
    function calculateRewardRates() public view returns (uint256 staticRate, uint256 dynamicRate, uint256 nftRate, uint256 projectRate) {
        uint256 poolTokenAmount = getPoolTokenAmount();
        if (poolTokenAmount > 1_000_000_000e18) return (1500, 750, 300, 60);
        else if (poolTokenAmount > 500_000_000e18) return (1250, 625, 300, 60);
        else if (poolTokenAmount > 100_000_000e18) return (1000, 500, 300, 60);
        else return (500, 250, 300, 60);
    }

    function calculateStaticReward(address user) public view returns (uint256) {
        User memory _user = users[user];
        if (!_user.isBuy || !_user.staticDrawStatus || block.timestamp < _user.staticDrawAt) {
            return 0;
        }
        (uint256 staticRate, , , ) = calculateRewardRates();
        return (_user.bnbTotal * staticRate) / 100000;
    }

    function getDynamicRewardRate(uint256 generation) public pure returns (uint256) {
        if (generation == 1) return 10;
        if (generation == 2) return 5;
        if (generation == 3) return 3;
        if (generation >= 4 && generation <= 17) return 1;
        if (generation == 18) return 3;
        if (generation == 19) return 5;
        if (generation == 20) return 10;
        return 0;
    }

    function calculateDynamicReward(address user, uint256 staticReward) internal returns (uint256 sendTotal) {
        User memory _user = users[user];
        address current = _user.up;
        uint256 generation = 1;
        uint256 maxGeneration = 20;

        while (current != address(0) && generation <= maxGeneration) {
            uint256 rate = getDynamicRewardRate(generation);
            uint256 reward = (staticReward * rate) / 100;
            if (reward > 0 && users[current].validTotal >= generation) {
                IERC20(_uniswapPair).transfer(current, reward);
                sendTotal += reward;
            }
            current = users[current].up;
            generation++;
        }
    }

    function processStaticReward(address user) internal {
        User memory _user = users[user];
        require(_user.isBuy, "User has not bought");
        require(_user.staticDrawStatus, "Static reward not available");
        require(block.timestamp >= _user.staticDrawAt, "Reward not matured");

        uint256 staticReward = calculateStaticReward(user);
        require(staticReward > 0, "No static reward available");

        (, uint256 dynamicRate, uint256 nftRate, uint256 projectRate) = calculateRewardRates();

        uint256 bnbTotal = _user.bnbTotal;
        uint256 dynamicReward = (bnbTotal * dynamicRate) / 100000;
        uint256 nftReward = (bnbTotal * nftRate) / 100000;
        uint256 projectReward = (bnbTotal * projectRate) / 100000;

        uint256 rewardTotal = staticReward + dynamicReward + nftReward + projectReward;
        uint256 tokenTotal = getBNBForTokenAmount(rewardTotal);   // will be implemented in Liquidity

        // lpAmounts logic will call distributeLPReward from liquidity module
    }
}