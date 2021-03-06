pragma solidity ^0.4.24;

import "../openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "../openzeppelin-solidity/contracts/ReentrancyGuard.sol";
import "../openzeppelin-solidity/contracts/math/SafeMath.sol";
import "../solidity-bytes-utils/contracts/BytesLib.sol";
import "./interfaces/IW12Crowdsale.sol";
import "./interfaces/IW12Fund.sol";
import "./W12Fund.sol";


contract W12Crowdsale is IW12Crowdsale, Ownable, ReentrancyGuard {
    using SafeMath for uint;
    using BytesLib for bytes;

    struct Stage {
        uint32 endDate;
        uint8 discount;
        uint32 vesting;
        uint[] volumeBoundaries;
        uint8[] volumeBonuses;
    }

    struct Milestone {
        uint32 endDate;
        uint8  tranchePercent;
        uint32 voteEndDate;
        uint32 withdrawalWindow;
        bytes name;
        bytes description;
    }

    WToken public token;
    uint tokenDecimals;
    uint32 public startDate;
    uint public price;
    uint8 public serviceFee;
    address public serviceWallet;
    IW12Fund public fund;

    Stage[] public stages;
    Milestone[] public milestones;
    uint32[] public milestoneDates;

    event TokenPurchase(address indexed buyer, uint amountPaid, uint tokensBought);
    event StagesUpdated();
    event MilestonesSet();

    event debug(uint value);

    constructor (address _token, uint _tokenDecimals, uint32 _startDate, uint _price, address _serviceWallet, uint8 _serviceFee, IW12Fund _fund) public {
        require(_token != address(0));
        require(_serviceFee >= 0 && _serviceFee < 100);
        require(_fund != address(0));

        token = WToken(_token);
        tokenDecimals = _tokenDecimals;

        __setParameters(_startDate, _price, _serviceWallet);
        serviceFee = _serviceFee;
        fund = _fund;
    }

    function stagesLength() external view returns (uint) {
        return stages.length;
    }

    function milestonesLength() external view returns (uint) {
        return milestones.length;
    }

    function getMilestone(uint index) public view returns (uint32, uint8, uint32, uint32, bytes, bytes) {
        return (
            milestones[index].endDate,
            milestones[index].tranchePercent,
            milestones[index].voteEndDate,
            milestones[index].withdrawalWindow,
            milestones[index].name,
            milestones[index].description
        );
    }

    function getStageVolumeBoundaries(uint stageNumber) external view returns (uint[]) {
        return stages[stageNumber].volumeBoundaries;
    }

    function getStageVolumeBonuses(uint stageNumber) external view returns (uint8[]) {
        return stages[stageNumber].volumeBonuses;
    }

    function __setParameters(uint32 _startDate, uint _price, address _serviceWallet) internal {
        require(_startDate >= now);
        require(_price > 0);
        require(_serviceWallet != address(0));

        startDate = _startDate;
        price = _price;
        serviceWallet = _serviceWallet;
    }

    function setParameters(uint32 _startDate, uint _price, address _serviceWallet) external onlyOwner {
        __setParameters(_startDate, _price, _serviceWallet);
    }

    function setStages(uint32[] stage_endDates, uint8[] stage_discounts, uint32[] stage_vestings) external onlyOwner {
        require(stage_endDates.length <= uint8(-1));
        require(stage_endDates.length > 0);
        require(stage_endDates.length == stage_discounts.length);
        require(stage_endDates.length == stage_vestings.length);

        uint8 stagesCount = uint8(stage_endDates.length);
        stages.length = stagesCount;

        for(uint8 i = 0; i < stagesCount; i++) {
            require(stage_discounts[i] >= 0 && stage_discounts[i] < 100);
            require(startDate < stage_endDates[i]);
            // Checking that stages entered in historical order
            if(i < stagesCount - 1)
                require(stage_endDates[i] < stage_endDates[i+1], "Stages are not in historical order");

            // Reverting stage order for future use
            stages[stagesCount - i - 1].endDate = stage_endDates[i];
            stages[stagesCount - i - 1].discount = stage_discounts[i];
            stages[stagesCount - i - 1].vesting = stage_vestings[i];
        }

        emit StagesUpdated();
    }

    function setStageVolumeBonuses(uint stage, uint[] volumeBoundaries, uint8[] volumeBonuses) external onlyOwner {
        require(volumeBoundaries.length == volumeBonuses.length);
        require(stage < stages.length);

        delete stages[stage].volumeBoundaries;
        delete stages[stage].volumeBonuses;

        stages[stage].volumeBoundaries = volumeBoundaries;
        stages[stage].volumeBonuses = volumeBonuses;
    }

    function setMilestones(uint32[] dates, uint8[] tranchePercents, uint32[] offsets, bytes namesAndDescriptions) external onlyOwner {
        require(milestones.length == 0);
        require(dates.length <= uint8(-1));
        require(dates.length > 3);
        require(dates.length % 3 == 0);
        require(tranchePercents.length.mul(2) == offsets.length);
        require(tranchePercents.length.mul(3) == dates.length);
        require(namesAndDescriptions.length >= tranchePercents.length * 2);

        uint offset = 0;
        uint8 totalPercents = 0;

        for(uint8 i = 0; i < uint8(dates.length); i += 3) {
            require(dates[i] > now);
            require(dates[i + 1] >= dates[i]);
            require(dates[i + 2] >= dates[i + 1]);
            require(offset.add(offsets[i / 3]).add(offsets[i / 3 + 1]) <= namesAndDescriptions.length);
            require(tranchePercents[i / 3] < 100);

            bytes memory name = namesAndDescriptions.slice(offset, offsets[i / 3 * 2]);
            bytes memory description = namesAndDescriptions.slice(offset + offsets[i / 3 * 2], offsets[i / 3 * 2 + 1]);

            require(name.length > 0);
            require(description.length > 0);

            milestones.push(Milestone({
                endDate: dates[i],
                tranchePercent: tranchePercents[i / 3],
                voteEndDate: dates[i + 1],
                withdrawalWindow: dates[i + 2],
                name: name,
                description: description
            }));

            offset += offsets[i / 3] + offsets[i / 3 + 1];
            totalPercents += tranchePercents[i / 3];
        }

        milestoneDates = dates;
        require(totalPercents == 100);
    }

    function getCurrentMilestoneIndex() public view returns (uint index) {
        uint milestonesCount = milestones.length;

        if(milestonesCount == 0)
            revert();

        for(index = 0; index < milestonesCount && now > milestoneDates[index * 3]; index++) {}

        if(index == milestonesCount)
            return index - 1;
    }

    // returns last milestone if completely ended or active milestone at now
    function getCurrentMilestone() external view returns (uint32, uint8, uint32, uint32, bytes, bytes) {
        uint index = getCurrentMilestoneIndex();

        return getMilestone(index);
    }

    function buyTokens() payable nonReentrant public {
        require(msg.value > 0);
        require(startDate <= now);
        require(stages.length > 0);

        (uint8 discount, uint32 vesting, uint8 volumeBonus) = getCurrentStage();

        // return funds if ICO was closed
        if(stages.length == 0) {
            msg.sender.transfer(msg.value);
            return;
        }

        uint stagePrice = discount > 0 ? price.mul(100 - discount).div(100) : price;

        uint tokenAmount = msg.value
            .mul(100 + volumeBonus)
            .div(stagePrice)
            .mul(10**(tokenDecimals - 2));

        require(token.vestingTransfer(msg.sender, tokenAmount, vesting));

        if(serviceFee > 0)
            serviceWallet.transfer(msg.value.mul(serviceFee).div(100));

        fund.recordPurchase.value(address(this).balance).gas(100000)(msg.sender, tokenAmount);

        emit TokenPurchase(msg.sender, msg.value, tokenAmount);
    }

    function getWToken() external view returns(WToken) {
        return token;
    }

    function getFund() external view returns(IW12Fund) {
        return fund;
    }

    function getCurrentStage() internal returns(uint8 discount, uint32 vesting, uint8 volumeBonus) {
        if(stages.length == 0)
            return (0, 0, 0);

        Stage storage lastStage = stages[stages.length - 1];

        if(lastStage.endDate >= now) {
            volumeBonus = 0;
            uint lastLowerBoundary = 0;

            if(lastStage.volumeBoundaries.length > 0)
                for (uint i = 0; i < lastStage.volumeBoundaries.length - 1; i++)
                    if(msg.value >= lastLowerBoundary && msg.value < lastStage.volumeBoundaries[i]) {
                        volumeBonus = lastStage.volumeBonuses[i];
                        break;
                    }
                    else
                        lastLowerBoundary = lastStage.volumeBoundaries[i];

            return (lastStage.discount, lastStage.vesting, volumeBonus);
        }

        stages.length--;
        return getCurrentStage();
    }

    function () payable external {
        buyTokens();
    }

    function isEnded() public view returns (bool) {
        return stages[stages.length - 1].endDate < now;
    }

    function claimRemainingTokens() external onlyOwner {
        require(isEnded());

        require(token.transfer(owner, token.balanceOf(address(this))));
    }
}
