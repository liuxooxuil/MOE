// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract HashGame is Ownable {
    IERC20 public immutable token;
    address public nft;

    uint256 public constant MIN_BET = 100 * 1e18;
    uint256 public constant MAX_BET = 100_000 * 1e18;
    uint256 public constant GAME_STOP_THRESHOLD = 10_000 * 1e18;

    mapping(address => bool) public whitelist;
    bool public gameActive = true;

    event BetPlaced(address indexed player, uint256 amount, bool isOdd, bool win, uint256 payout);
    event GameStatusChanged(bool active);
    event WhitelistUpdated(address indexed account, bool status);

    constructor(address _token, address _nft) Ownable(msg.sender) {
        token = IERC20(_token);
        nft = _nft;
    }

    function bet(uint256 amount) external {
        require(gameActive, "Game is stopped");

        bool isWhitelisted = whitelist[msg.sender];

        if (!isWhitelisted) {
            require(amount >= MIN_BET && amount <= MAX_BET, "Bet amount must be 100 ~ 100000");
        }

        uint256 contractBalance = token.balanceOf(address(this));
        if (contractBalance < GAME_STOP_THRESHOLD) {
            gameActive = false;
            emit GameStatusChanged(false);
            revert("Game stopped: insufficient balance");
        }

        require(token.transferFrom(msg.sender, address(this), amount), "Token transfer failed");

        // ==================== 5% 自动转给 NFT ====================
        uint256 toNFT = (amount * 5) / 100;
        if (toNFT > 0 && nft != address(0)) {
            token.transfer(nft, toNFT);
        }

        // ==================== 哈希单双判断 ====================
        bytes32 hash = keccak256(abi.encodePacked(block.timestamp, msg.sender, block.number, amount));
        uint8 lastDigit = _getLastDigitFromHash(hash);
        bool isOdd = (lastDigit % 2 == 1);

        bool win = isOdd;

        uint256 payout = 0;

        if (win && !isWhitelisted) {
            uint256 winAmount = amount * 2;
            uint256 available = token.balanceOf(address(this));

            if (available >= winAmount) {
                payout = winAmount;
            } else {
                payout = available;
                gameActive = false;
                emit GameStatusChanged(false);
            }

            if (payout > 0) {
                token.transfer(msg.sender, payout);
            }
        }

        emit BetPlaced(msg.sender, amount, isOdd, win, payout);
    }

    function _getLastDigitFromHash(bytes32 hash) internal pure returns (uint8) {
        for (uint256 i = 31; i >= 0; i--) {
            uint8 char = uint8(hash[i]);
            if (char >= 48 && char <= 57) {
                return char - 48;
            }
        }
        return 0;
    }

    // ==================== 管理员功能 ====================
    function addToWhitelist(address account) external onlyOwner {
        whitelist[account] = true;
        emit WhitelistUpdated(account, true);
    }

    function removeFromWhitelist(address account) external onlyOwner {
        whitelist[account] = false;
        emit WhitelistUpdated(account, false);
    }

    function setNFT(address _nft) external onlyOwner {
        nft = _nft;
    }

    function forceStopGame() external onlyOwner {
        gameActive = false;
        emit GameStatusChanged(false);
    }

    function startGame() external onlyOwner {
        require(token.balanceOf(address(this)) >= GAME_STOP_THRESHOLD, "Balance too low to start");
        gameActive = true;
        emit GameStatusChanged(true);
    }

    function isGameActive() external view returns (bool) {
        return gameActive && token.balanceOf(address(this)) >= GAME_STOP_THRESHOLD;
    }
}