// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

contract PriceFeedMockV3 {
    Slot0 public slot0;

    uint256 public decimals;
    string private _name;

    struct Slot0 {
        // the current price
        uint160 sqrtPriceX96;
        // the current tick
        int24 tick;
        // the most-recently updated index of the observations array
        uint16 observationIndex;
        // the current maximum number of observations that are being stored
        uint16 observationCardinality;
        // the next maximum number of observations to store, triggered in observations.write
        uint16 observationCardinalityNext;
        // the current protocol fee as a percentage of the swap fee taken on withdrawal
        // represented as an integer denominator (1/x)%
        uint8 feeProtocol;
        // whether the pool is locked
        bool unlocked;
    }

    constructor(string memory name) public {
        _name = name;
    }

    function setSqrtPriceX96(uint160 sqrtPriceX96) public {
        slot0.sqrtPriceX96 = sqrtPriceX96;
    }

    function setSlot0(
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint8 feeProtocol,
        bool unlocked
    ) public {
        slot0.sqrtPriceX96 = sqrtPriceX96;
        slot0.tick = tick;
        slot0.observationIndex = observationIndex;
        slot0.observationCardinality = observationCardinality;
        slot0.observationCardinalityNext = observationCardinalityNext;
        slot0.feeProtocol = feeProtocol;
        slot0.unlocked = unlocked;
    }
}
