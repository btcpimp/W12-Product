pragma solidity ^0.4.24;

import "./IW12Crowdsale.sol";


interface IW12Fund {
    function setCrowdsale(IW12Crowdsale _crowdsale) external;

    function setSwap(address _swap) external;

    function transferOwnership(address newOwner) public;

    function recordPurchase(address buyer, uint tokenAmount) external payable;
}
