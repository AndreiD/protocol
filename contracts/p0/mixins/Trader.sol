// SPDX-License-Identifier: BlueOak-1.0.0
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "contracts/interfaces/IBroker.sol";
import "contracts/interfaces/IMain.sol";
import "contracts/interfaces/ITrade.sol";
import "contracts/libraries/Fixed.sol";
import "contracts/p0/mixins/Component.sol";
import "contracts/p0/mixins/Rewardable.sol";

// Abstract trader affordances to be extended by our RevenueTraders and BackingManager
abstract contract TraderP0 is RewardableP0, ITrader {
    using FixLib for Fix;

    // All trades
    ITrade[] public trades;

    // First trade that is still open (or trades.length if all trades are settled)
    uint256 internal tradesStart;

    // The latest end time for any trade in `trades`.
    uint256 private latestEndtime;

    // === Governance params ===
    Fix public maxTradeSlippage; // {%}
    Fix public dustAmount; // {UoA}

    function init(ConstructorArgs calldata args) internal virtual override {
        maxTradeSlippage = args.params.maxTradeSlippage;
        dustAmount = args.params.dustAmount;
    }

    /// @return true iff this trader now has open trades.
    function hasOpenTrades() public view returns (bool) {
        return trades.length > tradesStart;
    }

    /// Settle any trades that can be settled
    function settleTrades() public {
        uint256 i = tradesStart;
        for (; i < trades.length && trades[i].canSettle(); i++) {
            ITrade trade = trades[i];
            (uint256 soldAmt, uint256 boughtAmt) = trade.settle();
            emit TradeSettled(trade, trade.sell(), trade.buy(), soldAmt, boughtAmt);
        }
        tradesStart = i;
    }

    /// Prepare an trade to sell `sellAmount` that guarantees a reasonable closing price,
    /// without explicitly aiming at a particular quantity to purchase.
    /// @param sellAmount {sellTok}
    /// @return notDust True when the trade is larger than the dust amount
    /// @return trade The prepared trade
    function prepareTradeSell(
        IAsset sell,
        IAsset buy,
        Fix sellAmount
    ) internal view returns (bool notDust, TradeRequest memory trade) {
        assert(sell.price().neq(FIX_ZERO) && buy.price().neq(FIX_ZERO));
        trade.sell = sell;
        trade.buy = buy;

        // Don't buy dust.
        if (sellAmount.lt(dustThreshold(sell))) return (false, trade);

        // {sellTok}
        Fix fixSellAmount = fixMin(sellAmount, sell.maxAuctionSize().div(sell.price()));
        trade.sellAmount = fixSellAmount.shiftLeft(int8(sell.erc20().decimals())).floor();

        // {buyTok} = {sellTok} * {UoA/sellTok} / {UoA/buyTok}
        Fix exactBuyAmount = fixSellAmount.mul(sell.price()).div(buy.price());
        Fix minBuyAmount = exactBuyAmount.mul(FIX_ONE.minus(maxTradeSlippage));
        trade.minBuyAmount = minBuyAmount.shiftLeft(int8(buy.erc20().decimals())).ceil();
        return (true, trade);
    }

    /// Assuming we have `maxSellAmount` sell tokens avaialable, prepare an trade to
    /// cover as much of our deficit as possible, given expected trade slippage.
    /// @param maxSellAmount {sellTok}
    /// @param deficitAmount {buyTok}
    /// @return notDust Whether the prepared trade is large enough to be worth trading
    /// @return trade The prepared trade
    function prepareTradeToCoverDeficit(
        IAsset sell,
        IAsset buy,
        Fix maxSellAmount,
        Fix deficitAmount
    ) internal view returns (bool notDust, TradeRequest memory trade) {
        // Don't sell dust.
        if (maxSellAmount.lt(dustThreshold(sell))) return (false, trade);

        // Don't buy dust.
        deficitAmount = fixMax(deficitAmount, dustThreshold(buy));

        // {sellTok} = {buyTok} * {UoA/buyTok} / {UoA/sellTok}
        Fix exactSellAmount = deficitAmount.mul(buy.price()).div(sell.price());
        // exactSellAmount: Amount to sell to buy `deficitAmount` if there's no slippage

        // idealSellAmount: Amount needed to sell to buy `deficitAmount`, counting slippage
        Fix idealSellAmount = exactSellAmount.div(FIX_ONE.minus(maxTradeSlippage));

        Fix sellAmount = fixMin(idealSellAmount, maxSellAmount);
        return prepareTradeSell(sell, buy, sellAmount);
    }

    /// @return {tok} The least amount of whole tokens ever worth trying to sell
    function dustThreshold(IAsset asset) internal view returns (Fix) {
        // {tok} = {UoA} / {UoA/tok}
        return dustAmount.div(asset.price());
    }

    function initiateTrade(TradeRequest memory req) internal {
        IBroker broker = main.broker();
        if (broker.disabled()) return; // correct interaction with BackingManager/RevenueTrader

        req.sell.erc20().approve(address(broker), req.sellAmount);
        ITrade trade = broker.initiateTrade(req);
        latestEndtime = Math.max(trade.endTime(), latestEndtime);

        trades.push(trade);
        emit TradeStarted(
            trade,
            req.sell.erc20(),
            req.buy.erc20(),
            req.sellAmount,
            req.minBuyAmount
        );
    }

    // === Setters ===

    function setMaxTradeSlippage(Fix val) external onlyOwner {
        emit MaxTradeSlippageSet(maxTradeSlippage, val);
        maxTradeSlippage = val;
    }

    function setDustAmount(Fix val) external onlyOwner {
        emit DustAmountSet(dustAmount, val);
        dustAmount = val;
    }
}
