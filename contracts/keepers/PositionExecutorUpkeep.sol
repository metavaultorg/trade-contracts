/// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

pragma experimental ABIEncoderV2;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "./interfaces/KeeperCompatibleInterface.sol";
import "./interfaces/AggregatorV3Interface.sol";

import "../libraries/access/Ownable.sol";

import "../core/interfaces/IPositionRouter.sol";
import "../core/interfaces/IVault.sol";

contract PositionExecutorUpkeep is Ownable, KeeperCompatibleInterface {
    IPositionRouter public positionRouter;
    address payable public _executionFeeReceiver;
    uint256 public interval;
    uint256 public lastTimeStamp;

    constructor(uint256 _updateInterval) public {
        interval = _updateInterval;
        lastTimeStamp = block.timestamp;
    }

    function initialize(address _positionRouter) external onlyOwner {
        positionRouter = IPositionRouter(_positionRouter);
    }

    function setInterval(uint256 _interval) external onlyOwner {
        interval = _interval;
        lastTimeStamp = block.timestamp;
    }

    function setExecutionFeeReceiver(address payable _receiver) public onlyOwner {
        require(_receiver != address(0), "Receiver not valid.");
        _executionFeeReceiver = _receiver;
    }

    function checkUpkeep(bytes calldata checkData) external override returns (bool upkeepNeeded, bytes memory performData) {
        upkeepNeeded = ensureCheckUpdate();
    }

    function performUpkeep(bytes calldata performData) external override {
        if (ensureCheckUpdate()) {
            lastTimeStamp = block.timestamp;
            executeInternal();
        }
    }

    function ensureCheckUpdate() internal returns (bool upkeepNeeded) {
        upkeepNeeded = (block.timestamp - lastTimeStamp) > interval;

        if ((block.timestamp - lastTimeStamp) > interval) {
            (uint256 ipRequestKeysStart, uint256 ipRequestKeysLength, uint256 dpRequestKeysStart, uint256 dpRequestKeysLength) = positionRouter.getRequestQueueLengths();

            uint256 ipCount = ipRequestKeysLength - ipRequestKeysStart;
            uint256 dpCount = dpRequestKeysLength - dpRequestKeysStart;

            upkeepNeeded = false;
            if (ipCount > 0 || dpCount > 0) {
                upkeepNeeded = true;
            }
        }
    }

    function executeInternal() internal {
        (uint256 ipRequestKeysStart, uint256 ipRequestKeysLength, uint256 dpRequestKeysStart, uint256 dpRequestKeysLength) = positionRouter.getRequestQueueLengths();

        uint256 ipCount = ipRequestKeysLength - ipRequestKeysStart;
        uint256 dpCount = dpRequestKeysLength - dpRequestKeysStart;

        if (dpCount > 0) {
            positionRouter.executeDecreasePositions(dpRequestKeysLength, _executionFeeReceiver);
        }

        if (ipCount > 0) {
            positionRouter.executeIncreasePositions(ipRequestKeysLength, _executionFeeReceiver);
        }
    }
}
