/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./interfaces/KeeperCompatibleInterface.sol";

//import "../libraries/v08/access/Ownable.sol";

import "../core/interfaces/IPositionManager.sol";
import "../core/interfaces/IOrderBook.sol";

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}




contract OrderBookUpkeep is Ownable, KeeperCompatibleInterface {
    IPositionManager public positionManager;
    IOrderBook public orderBook;
    address payable public _executionFeeReceiver;
    uint256 public interval;
    uint256 public lastTimeStamp;

    constructor(uint256 _updateInterval) {
        interval = _updateInterval;
        lastTimeStamp = block.timestamp;
    }

    function initialize(address _positionManager,address _orderBook) external onlyOwner {
        require(_positionManager != address(0), "Address not valid.");
        require(_orderBook != address(0), "Address not valid.");
        positionManager = IPositionManager(_positionManager);
        orderBook = IOrderBook(_orderBook);
    }

    function setInterval(uint256 _interval) external onlyOwner {
        interval = _interval;
        lastTimeStamp = block.timestamp;
    }

    function setExecutionFeeReceiver(address payable _receiver) public onlyOwner {
        require(_receiver != address(0), "Receiver not valid.");
        _executionFeeReceiver = _receiver;
    }

    function setPositionManager(address _positionManager) public onlyOwner {
        require(_positionManager != address(0), "Address not valid.");
        positionManager = IPositionManager(_positionManager);
    }

    function setOrderBook(address _orderBook) public onlyOwner {
        require(_orderBook != address(0), "Address not valid.");
        orderBook = IOrderBook(_orderBook);
    }

    function checkUpkeep(
        bytes calldata /* checkData */
    ) external view override returns (bool upkeepNeeded, bytes memory performData) {
        upkeepNeeded =  ensureCheckUpdate();
        return (upkeepNeeded, "");
    }

    function performUpkeep(
        bytes calldata /*performData*/
    ) external override {
        lastTimeStamp = block.timestamp;
        executeInternal();
    }

    function ensureCheckUpdate() internal view returns (bool) {
        bool upkeepNeeded = (block.timestamp - lastTimeStamp) > interval;

        if ((block.timestamp - lastTimeStamp) > interval) {
            (upkeepNeeded,) = orderBook.getShouldExecuteOrderList(true);
        }
        return upkeepNeeded ;
    }

    function executeInternal() internal {
        bool shouldExecute;
        uint160[] memory orderList;
        (shouldExecute,orderList) = orderBook.getShouldExecuteOrderList(false);

        if(shouldExecute){
            uint256 orderLength = orderList.length/3;

            uint256 curIndex = 0;

            while (curIndex < orderLength) {
                address account = address(orderList[curIndex*3]);
                uint256 orderIndex = uint256(orderList[curIndex*3+1]);
                uint256 orderType = uint256(orderList[curIndex*3+2]);

                if(orderType== 0 ) {//SWAP
                    positionManager.executeSwapOrder(account,orderIndex, _executionFeeReceiver);
                }else if(orderType== 1 ) {//INCREASE
                    positionManager.executeIncreaseOrder(account,orderIndex, _executionFeeReceiver);
                }else if(orderType== 2 ) {//DECREASE
                    positionManager.executeDecreaseOrder(account,orderIndex, _executionFeeReceiver);
                }
                curIndex++;
            }

        }
    }
}
