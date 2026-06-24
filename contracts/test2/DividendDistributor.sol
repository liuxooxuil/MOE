// SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.28;

// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";
// import "./ROMANToken.sol"; // We will adjust import after deployment
// import "./MainCardNFT.sol";
// import "./SubCardNFT.sol";

// /**
//  * @title DividendDistributor
//  * @dev 完整实现 NFT 正副卡分红逻辑
//  * - 手续费 70% → USDT 加权分红
//  * - 入单 3% → BNB
//  * - 防爆税超出 50% → ROMAN
//  * - 哈希游戏 5% → ROMAN
//  * - 激活要求：持有 NFT + ROMANToken 中 bnbTotal >= 0.2 BNB
//  * - 每个地址默认只能激活 1 张正卡 + 1 张副卡（白名单可多张）
//  */
// contract DividendDistributor is Ownable {
//     // ==================== 状态变量 ====================
//     ROMANToken public romanToken;
//     MainCardNFT public mainNFT;
//     SubCardNFT public subNFT;

//     address public usdt; // USDT 地址（BSC: 0x55d398326f99059fF775485246999027B3197955）

//     // 分红池（按来源分类，便于透明）
//     uint256 public feeUsdtPool;        // 手续费 → USDT
//     uint256 public investBnbPool;      // 入单 3% → BNB
//     uint256 public antiDumpRomanPool;  // 防爆税超出 → ROMAN
//     uint256 public hashGameRomanPool;  // 哈希游戏 5% → ROMAN

//     // 激活的 NFT 记录（实现“每个地址只能计算一张”）
//     mapping(address => uint256) public activeMainTokenId; // 用户当前激活的正卡 tokenId
//     mapping(address => uint256) public activeSubTokenId;  // 用户当前激活的副卡 tokenId

//     mapping(address => bool) public whitelist; // 白名单可激活多张

//     // 统计已激活数量（用于加权计算）
//     uint256 public totalActiveMain;
//     uint256 public totalActiveSub;

//     // 事件
//     event RewardReceived(string rewardType, uint256 amount, address from);
//     event Claimed(address indexed user, uint256 mainAmount, uint256 subAmount, address token);
//     event Activated(address indexed user, uint256 mainTokenId, uint256 subTokenId);
//     event Deactivated(address indexed user, uint256 mainTokenId, uint256 subTokenId);

//     constructor(
//         address payable _romanToken,
//         address _mainNFT,
//         address _subNFT,
//         address _usdt
//     ) Ownable(msg.sender) {
//         romanToken = ROMANToken(_romanToken);
//         mainNFT = MainCardNFT(_mainNFT);
//         subNFT = SubCardNFT(_subNFT);
//         usdt = _usdt;
//     }

//     // ==================== 管理员功能 ====================
//     function setWhitelist(address user, bool status) external onlyOwner {
//         whitelist[user] = status;
//     }

//     function updateContracts(
//         address payable _romanToken,
//         address _mainNFT,
//         address _subNFT
//     ) external onlyOwner {
//         romanToken = ROMANToken(_romanToken);
//         mainNFT = MainCardNFT(_mainNFT);
//         subNFT = SubCardNFT(_subNFT);
//     }

//     // ==================== 接收分红（由 ROMANToken 调用） ====================
//     receive() external payable {
//         // 接收 BNB（入单分成）
//         investBnbPool += msg.value;
//         emit RewardReceived("invest_bnb", msg.value, msg.sender);
//     }

//     function receiveUsdt(uint256 amount) external {
//         require(msg.sender == address(romanToken), "Only ROMANToken");
//         IERC20(usdt).transferFrom(msg.sender, address(this), amount);
//         feeUsdtPool += amount;
//         emit RewardReceived("fee_usdt", amount, msg.sender);
//     }

//     function receiveRoman(uint256 amount, string memory rewardType) external {
//         require(msg.sender == address(romanToken), "Only ROMANToken");
//         IERC20(address(romanToken)).transferFrom(msg.sender, address(this), amount);

//         if (keccak256(bytes(rewardType)) == keccak256(bytes("anti_dump"))) {
//             antiDumpRomanPool += amount;
//         } else if (keccak256(bytes(rewardType)) == keccak256(bytes("hash_game"))) {
//             hashGameRomanPool += amount;
//         }
//         emit RewardReceived(rewardType, amount, msg.sender);
//     }

//     // ==================== 激活 / 取消激活 ====================
// function activate(uint256 mainTokenId, uint256 subTokenId) external {
//     address user = msg.sender;

//     // 检查是否持有 NFT
//     require(mainNFT.ownerOf(mainTokenId) == user || mainTokenId == 0, "Not owner of main NFT");
//     require(subNFT.ownerOf(subTokenId) == user || subTokenId == 0, "Not owner of sub NFT");

//     // 检查激活条件：ROMANToken 中有 ≥0.2 BNB 投资
//     (uint256 bnbTotal, bool isBuy, ) = romanToken.getUserStatus(user);
//     require(bnbTotal >= 0.2 ether && isBuy, "Need at least 0.2 BNB investment to activate");

//     // 非白名单用户只能激活 1 张正卡 + 1 张副卡
//     if (!whitelist[user]) {
//         require(activeMainTokenId[user] == 0 || activeMainTokenId[user] == mainTokenId, "Already activated a main NFT");
//         require(activeSubTokenId[user] == 0 || activeSubTokenId[user] == subTokenId, "Already activated a sub NFT");
//     }

//     // 更新激活记录
//     if (mainTokenId != 0 && activeMainTokenId[user] != mainTokenId) {
//         if (activeMainTokenId[user] != 0) totalActiveMain--;
//         activeMainTokenId[user] = mainTokenId;
//         totalActiveMain++;
//     }

//     if (subTokenId != 0 && activeSubTokenId[user] != subTokenId) {
//         if (activeSubTokenId[user] != 0) totalActiveSub--;
//         activeSubTokenId[user] = subTokenId;
//         totalActiveSub++;
//     }

//     emit Activated(user, mainTokenId, subTokenId);
// }

//     function deactivate() external {
//         address user = msg.sender;
//         uint256 mainId = activeMainTokenId[user];
//         uint256 subId = activeSubTokenId[user];

//         if (mainId != 0) {
//             totalActiveMain--;
//             activeMainTokenId[user] = 0;
//         }
//         if (subId != 0) {
//             totalActiveSub--;
//             activeSubTokenId[user] = 0;
//         }

//         emit Deactivated(user, mainId, subId);
//     }

//     // ==================== 领取分红 ====================
//     function claim() external {
//         address user = msg.sender;
//         uint256 mainId = activeMainTokenId[user];
//         uint256 subId = activeSubTokenId[user];

//         require(mainId != 0 || subId != 0, "No active NFT");

//         uint256 mainShareUsdt = 0;
//         uint256 subShareUsdt = 0;
//         uint256 mainShareRoman = 0;
//         uint256 subShareRoman = 0;
//         uint256 mainShareBnb = 0;
//         uint256 subShareBnb = 0;

//         // ===== USDT 分红（手续费） =====
//         if (feeUsdtPool > 0 && totalActiveMain + totalActiveSub > 0) {
//             if (mainId != 0 && totalActiveMain > 0) {
//                 mainShareUsdt = feeUsdtPool * 70 / 100 / totalActiveMain; // 正卡占 70%
//             }
//             if (subId != 0 && totalActiveSub > 0) {
//                 subShareUsdt = feeUsdtPool * 30 / 100 / totalActiveSub;   // 副卡占 30%
//             }
//         }

//         // ===== ROMAN 分红（防爆税 + 哈希游戏） =====
//         uint256 totalRomanPool = antiDumpRomanPool + hashGameRomanPool;
//         if (totalRomanPool > 0 && totalActiveMain + totalActiveSub > 0) {
//             if (mainId != 0 && totalActiveMain > 0) {
//                 mainShareRoman = totalRomanPool * 70 / 100 / totalActiveMain;
//             }
//             if (subId != 0 && totalActiveSub > 0) {
//                 subShareRoman = totalRomanPool * 30 / 100 / totalActiveSub;
//             }
//         }

//         // ===== BNB 分红（入单 3%） =====
//         if (investBnbPool > 0 && totalActiveMain + totalActiveSub > 0) {
//             if (mainId != 0 && totalActiveMain > 0) {
//                 mainShareBnb = investBnbPool * 70 / 100 / totalActiveMain;
//             }
//             if (subId != 0 && totalActiveSub > 0) {
//                 subShareBnb = investBnbPool * 30 / 100 / totalActiveSub;
//             }
//         }

//         // 转账
//         if (mainShareUsdt + subShareUsdt > 0) {
//             IERC20(usdt).transfer(user, mainShareUsdt + subShareUsdt);
//         }
//         if (mainShareRoman + subShareRoman > 0) {
//             IERC20(address(romanToken)).transfer(user, mainShareRoman + subShareRoman);
//         }
//         if (mainShareBnb + subShareBnb > 0) {
//             payable(user).transfer(mainShareBnb + subShareBnb);
//         }

//         // 更新池子余额（简化处理，实际生产建议用快照）
//         feeUsdtPool -= (mainShareUsdt + subShareUsdt);
//         antiDumpRomanPool -= mainShareRoman + subShareRoman; // 简化
//         hashGameRomanPool -= mainShareRoman + subShareRoman;
//         investBnbPool -= (mainShareBnb + subShareBnb);

//         emit Claimed(user, mainShareUsdt + mainShareRoman + mainShareBnb,
//                      subShareUsdt + subShareRoman + subShareBnb, usdt);
//     }

//     // ==================== 紧急提取（仅 owner） ====================
//     function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
//         if (token == address(0)) {
//             payable(owner()).transfer(amount);
//         } else {
//             IERC20(token).transfer(owner(), amount);
//         }
//     }
// }

pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IROMANToken {
    function getUserStatus(address user) external view returns (uint256 bnbTotal, bool isBuy, bool staticDrawStatus);
}
interface INFTActivation {
    function hasPaidActivationFee(address user) external view returns (bool);
}

contract DividendDistributor is Ownable {
    IROMANToken public romanToken;
    address public mainNFT;
    address public subNFT;
    address public usdt;

    // Reward pools
    uint256 public feeUsdtPool;        // 70% trading fee → USDT
    uint256 public investBnbPool;      // 3% investment → BNB
    uint256 public antiDumpRomanPool;  // Anti-dump extra → ROMAN
    uint256 public hashGameRomanPool;  // Hash game 5% → ROMAN

    // Activation records
    mapping(address => uint256) public activeMainTokenId;
    mapping(address => uint256) public activeSubTokenId;
    mapping(address => bool) public whitelist;

    uint256 public totalActiveMain;
    uint256 public totalActiveSub;

    event RewardReceived(string rewardType, uint256 amount);
    event Activated(address indexed user, uint256 mainId, uint256 subId);
    event Claimed(address indexed user, uint256 usdtAmount, uint256 romanAmount, uint256 bnbAmount);

    constructor(
        address _romanToken,
        address _mainNFT,
        address _subNFT,
        address _usdt
    ) Ownable(msg.sender) {
        romanToken = IROMANToken(_romanToken);
        mainNFT = _mainNFT;
        subNFT = _subNFT;
        usdt = _usdt;
    }

    // Receive BNB from investment 3%
    receive() external payable {
        investBnbPool += msg.value;
        emit RewardReceived("invest_bnb", msg.value);
    }

    // Called by ROMANToken to send USDT (from trading fees)
    function receiveUsdt(uint256 amount) external {
        require(msg.sender == address(romanToken) || msg.sender == owner(), "Only ROMANToken or owner");
        IERC20(usdt).transferFrom(msg.sender, address(this), amount);
        feeUsdtPool += amount;
        emit RewardReceived("fee_usdt", amount);
    }

    // Called by ROMANToken to send ROMAN (anti-dump or hash game)
    function receiveRoman(uint256 amount, string memory rewardType) external {
        require(msg.sender == address(romanToken) || msg.sender == owner(), "Only ROMANToken or owner");
        IERC20(address(romanToken)).transferFrom(msg.sender, address(this), amount);

        if (keccak256(bytes(rewardType)) == keccak256(bytes("anti_dump"))) {
            antiDumpRomanPool += amount;
        } else if (keccak256(bytes(rewardType)) == keccak256(bytes("hash_game"))) {
            hashGameRomanPool += amount;
        }
        emit RewardReceived(rewardType, amount);
    }

    function setWhitelist(address user, bool status) external onlyOwner {
        whitelist[user] = status;
    }

    function activate(uint256 mainTokenId, uint256 subTokenId) external {
        address user = msg.sender;

        // Check ownership of NFTs
        if (mainTokenId != 0) {
            require(IERC721(mainNFT).ownerOf(mainTokenId) == user, "Not owner of main NFT");
        }
        if (subTokenId != 0) {
            require(IERC721(subNFT).ownerOf(subTokenId) == user, "Not owner of sub NFT");
        }

        // Check investment requirement
        (uint256 bnbTotal, bool isBuy, ) = romanToken.getUserStatus(user);
        require(bnbTotal >= 0.002 ether && isBuy, "Need at least 0.2 BNB investment"); // 测试先改为小数位

        // Activation logic (one per address unless whitelisted)
        if (!whitelist[user]) {
            require(activeMainTokenId[user] == 0 || activeMainTokenId[user] == mainTokenId, "Already activated different main NFT");
            require(activeSubTokenId[user] == 0 || activeSubTokenId[user] == subTokenId, "Already activated different sub NFT");
        }

        // Update main NFT
        if (mainTokenId != 0 && activeMainTokenId[user] != mainTokenId) {
            if (activeMainTokenId[user] != 0) totalActiveMain--;
            activeMainTokenId[user] = mainTokenId;
            totalActiveMain++;
        }

        // Update sub NFT
        if (subTokenId != 0 && activeSubTokenId[user] != subTokenId) {
            if (activeSubTokenId[user] != 0) totalActiveSub--;
            activeSubTokenId[user] = subTokenId;
            totalActiveSub++;
        }

        emit Activated(user, mainTokenId, subTokenId);
    }

    // function claim() external {
    //     address user = msg.sender;
    //     uint256 mainId = activeMainTokenId[user];
    //     uint256 subId = activeSubTokenId[user];

    //     require(mainId != 0 || subId != 0, "No active NFT");

    //     uint256 totalUsdt = 0;
    //     uint256 totalRoman = 0;
    //     uint256 totalBnb = 0;

    //     uint256 totalActive = totalActiveMain + totalActiveSub;
    //     if (totalActive == 0) return;

    //     // USDT from trading fees (70% main / 30% sub)
    //     if (feeUsdtPool > 0 && totalActiveMain + totalActiveSub > 0) {
    //         if (mainId != 0 && totalActiveMain > 0) {
    //             totalUsdt += (feeUsdtPool * 70) / 100 / totalActiveMain;
    //         }
    //         if (subId != 0 && totalActiveSub > 0) {
    //             totalUsdt += (feeUsdtPool * 30) / 100 / totalActiveSub;
    //         }
    //     }

    //     // ROMAN from anti-dump + hash game
    //     uint256 totalRomanPool = antiDumpRomanPool + hashGameRomanPool;
    //     if (totalRomanPool > 0 && totalActiveMain + totalActiveSub > 0) {
    //         if (mainId != 0 && totalActiveMain > 0) {
    //             totalRoman += (totalRomanPool * 70) / 100 / totalActiveMain;
    //         }
    //         if (subId != 0 && totalActiveSub > 0) {
    //             totalRoman += (totalRomanPool * 30) / 100 / totalActiveSub;
    //         }
    //     }

    //     // BNB from investment 3%
    //     if (investBnbPool > 0 && totalActiveMain + totalActiveSub > 0) {
    //         if (mainId != 0 && totalActiveMain > 0) {
    //             totalBnb += (investBnbPool * 70) / 100 / totalActiveMain;
    //         }
    //         if (subId != 0 && totalActiveSub > 0) {
    //             totalBnb += (investBnbPool * 30) / 100 / totalActiveSub;
    //         }
    //     }

    //     // Transfer
    //     if (totalUsdt > 0) {
    //         IERC20(usdt).transfer(user, totalUsdt);
    //     }
    //     if (totalRoman > 0) {
    //         IERC20(address(romanToken)).transfer(user, totalRoman);
    //     }
    //     if (totalBnb > 0) {
    //         payable(user).transfer(totalBnb);
    //     }

    //     // Update pools (simplified reset for ROMAN pools)
    //     feeUsdtPool -= totalUsdt;
    //     antiDumpRomanPool = 0;
    //     hashGameRomanPool = 0;
    //     investBnbPool -= totalBnb;

    //     emit Claimed(user, totalUsdt, totalRoman, totalBnb);
    // }
function claim() external {
    address user = msg.sender;

    // ==================== 1. 检查是否持有 NFT ====================
    bool hasMainNFT = (mainNFT != address(0)) && (IERC721(mainNFT).balanceOf(user) > 0);
    bool hasSubNFT  = (subNFT  != address(0)) && (IERC721(subNFT).balanceOf(user) > 0);

    require(hasMainNFT || hasSubNFT, "You must hold MainCardNFT or SubCardNFT");

    // ==================== 2. 检查是否已支付 0.2 BNB 激活费 ====================
    bool paidMain = false;
    bool paidSub  = false;

    if (hasMainNFT && mainNFT != address(0)) {
        paidMain = INFTActivation(mainNFT).hasPaidActivationFee(user);
    }

    if (hasSubNFT && subNFT != address(0)) {
        paidSub = INFTActivation(subNFT).hasPaidActivationFee(user);
    }

    require(paidMain || paidSub, "You must pay 0.2 BNB activation fee to NFT contract first");

    // ==================== 3. 原有计算逻辑（保留你的方式） ====================
    uint256 totalUsdt = 0;
    uint256 totalRoman = 0;
    uint256 totalBnb = 0;

    uint256 totalActive = totalActiveMain + totalActiveSub;
    if (totalActive == 0) return;

    // USDT from trading fees (70% main / 30% sub)
    if (feeUsdtPool > 0 && totalActiveMain + totalActiveSub > 0) {
        if (paidMain && totalActiveMain > 0) {
            totalUsdt += (feeUsdtPool * 70) / 100 / totalActiveMain;
        }
        if (paidSub && totalActiveSub > 0) {
            totalUsdt += (feeUsdtPool * 30) / 100 / totalActiveSub;
        }
    }

    // ROMAN from anti-dump + hash game
    uint256 totalRomanPool = antiDumpRomanPool + hashGameRomanPool;
    if (totalRomanPool > 0 && totalActiveMain + totalActiveSub > 0) {
        if (paidMain && totalActiveMain > 0) {
            totalRoman += (totalRomanPool * 70) / 100 / totalActiveMain;
        }
        if (paidSub && totalActiveSub > 0) {
            totalRoman += (totalRomanPool * 30) / 100 / totalActiveSub;
        }
    }

    // BNB from investment 3%
    if (investBnbPool > 0 && totalActiveMain + totalActiveSub > 0) {
        if (paidMain && totalActiveMain > 0) {
            totalBnb += (investBnbPool * 70) / 100 / totalActiveMain;
        }
        if (paidSub && totalActiveSub > 0) {
            totalBnb += (investBnbPool * 30) / 100 / totalActiveSub;
        }
    }

    // ==================== 4. 转账 ====================
    if (totalUsdt > 0) {
        IERC20(usdt).transfer(user, totalUsdt);
    }
    if (totalRoman > 0) {
        IERC20(address(romanToken)).transfer(user, totalRoman);
    }
    if (totalBnb > 0) {
        payable(user).transfer(totalBnb);
    }

    // ==================== 5. 更新池子 ====================
    feeUsdtPool -= totalUsdt;
    antiDumpRomanPool = 0;
    hashGameRomanPool = 0;
    investBnbPool -= totalBnb;

    emit Claimed(user, totalUsdt, totalRoman, totalBnb);
}

    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            payable(owner()).transfer(amount);
        } else {
            IERC20(token).transfer(owner(), amount);
        }
    }
}

// // Minimal IERC721 interface for activation check
// interface IERC721 {
//     function ownerOf(uint256 tokenId) external view returns (address);
// }