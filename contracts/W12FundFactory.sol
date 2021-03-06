pragma solidity ^0.4.24;

import "./W12Fund.sol";
import "./interfaces/IW12FundFactory.sol";


contract W12FundFactory is IW12FundFactory {
    event FundCreated(address indexed fund);

    function createFund(address swap) external returns (IW12Fund result) {
        result = new W12Fund();

        result.setSwap(swap);
        result.transferOwnership(msg.sender);

        emit FundCreated(result);
    }
}
