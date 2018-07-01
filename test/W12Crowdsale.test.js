import * as time from '../openzeppelin-solidity/test/helpers/increaseTime';

const BigNumber = web3.BigNumber;

require('chai')
    .use(require('chai-as-promised'))
    .use(require('chai-bignumber')(BigNumber))
    .should();

const crypto = require('crypto');

const W12CrowdsaleFactory = artifacts.require('W12CrowdsaleFactory');
const W12Crowdsale = artifacts.require('W12Crowdsale');
const WToken = artifacts.require('WToken');
const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
const oneToken = new BigNumber(10).pow(18);

function generateRandomAddress() {
    return `0x${crypto.randomBytes(20).toString('hex')}`;
};

contract('W12Crowdsale', async (accounts) => {
    let sut;
    let token;
    const tokenOwner = accounts[9];
    let factory;
    let startDate;
    const serviceWallet = generateRandomAddress();

    beforeEach(async () => {
        factory = await W12CrowdsaleFactory.new();
        token = await WToken.new('TestToken', 'TT', 18, {from: tokenOwner});
        startDate = Math.floor(Date.now() / 1000) + 10;

        const txOutput = await factory.createCrowdsale(token.address, startDate, oneToken, serviceWallet, 10, tokenOwner);
        const crowdsaleCreatedLogEntry = txOutput.logs.filter(l => l.event === 'CrowdsaleCreated')[0];

        sut = W12Crowdsale.at(crowdsaleCreatedLogEntry.args.crowdsaleAddress);
        await token.addTrustedAccount(sut.address, {from: tokenOwner});
        await token.mint(sut.address, oneToken.mul(10000), 0, {from: tokenOwner});
    });

    describe('constructor', async () => {
        it('should create crowdsale', async () => {
            (await sut.startDate()).should.bignumber.equal(startDate);
            (await sut.token()).should.be.equal(token.address);
            (await sut.price()).should.bignumber.equal(oneToken);
            (await sut.serviceFee()).should.bignumber.equal(10);
            (await sut.serviceWallet()).should.be.equal(serviceWallet);
        });

        it('should reject crowdsale with start date in the past', async () => {
            await factory.createCrowdsale(token.address, Math.floor(Date.now() - 100 / 1000), oneToken, serviceWallet, 10, tokenOwner).should.be.rejected;
        });
    });

    describe('token purchase', async () => {
        let expectedStages;

        beforeEach(async () => {
            expectedStages = [
                {
                    name: 'Phase 1',
                    endDate: startDate + time.duration.minutes(60),
                    vestingTime: 0,
                    discount: 5
                },
                {
                    name: 'Phase 2',
                    endDate: startDate + time.duration.minutes(120),
                    vestingTime: startDate + time.duration.minutes(180),
                    discount: 10
                }
            ];

            await sut.setStages(
                expectedStages.map(s => s.endDate),
                expectedStages.map(s => s.discount),
                expectedStages.map(s => s.vestingTime),
                {from: tokenOwner}
            );
        });

        it('should be able to set stages', async () => {
            const actualNumberOfStages = await sut.stagesLength().should.be.fulfilled;

            actualNumberOfStages.should.bignumber.equal(expectedStages.length);

            let counter = expectedStages.length;
            expectedStages.forEach(async expectedStage => {
                const actualStage = await sut.stages(--counter).should.be.fulfilled;

                actualStage[0].should.bignumber.equal(expectedStage.endDate);
                actualStage[1].should.bignumber.equal(expectedStage.discount);
                actualStage[2].should.bignumber.equal(expectedStage.vestingTime);
            });
        });

        it('should be able to buy some tokens', async () => {
            time.increaseTimeTo(startDate);
            const buyer = accounts[8];

            await sut.buyTokens({ value: oneToken.mul(10), from: buyer }).should.be.fulfilled;

            (await token.balanceOf(buyer)).should.bignumber.equal(10);
            web3.eth.getBalance(serviceWallet).should.bignumber.equal(oneToken);
        });
    });
});