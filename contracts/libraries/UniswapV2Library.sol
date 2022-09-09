pragma solidity >=0.5.0;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';

import "./SafeMath.sol";

library UniswapV2Library {
    using SafeMath for uint;

    /**
        @dev 对地址进行从小到大排序并验证不能为零地址
        @notice: 地址为uint160类型，因此可以比较，uniswap v2统一将较小的地址记为token0
        @param tokenA 待排序的tokenA地址
        @param tokenB 待排序的tokenB地址
        @return {address} token0 比较后，地址较小的token地址
        @return {address} token1 比较后，地址较大的token地址
     */
    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'UniswapV2Library: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'UniswapV2Library: ZERO_ADDRESS');
    }

    /**
        @dev 获取tokenA和tokenB交易对的pair合约地址，根据create2原理获得，而非通过存储变量读取；
        @notice: 可参考：https://solidity-by-example.org/app/create2/
        @param factory 工厂合约地址
        @param tokenA tokenA地址
        @param tokenB tokenB地址
        @return {address} pair tokenA和tokenB交易对的合约地址
     */
    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,    // 工厂合约地址，即创建交易对合约的地址
                keccak256(abi.encodePacked(token0, token1)),    // salt, 有v2-core代码可知salt为token A和B地址确定
                hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f' // init code hash // 该字段为链下计算得出的，交易对合约的keccak256(creationCode)
            ))));
    }

    /**
        @dev 通过pairFor合约获取到对应的交易对合约地址，从而获取某个交易对中恒定乘积的各资产的值
        @param factory 工厂合约地址
        @param tokenA tokenA地址
        @param tokenB tokenB地址
        @return {uint} reserveA tokenA
        @return {uint} reserveB tokenA和tokenB交易对的合约地址
     */
    // fetches and sorts the reserves for a pair
    function getReserves(address factory, address tokenA, address tokenB) internal view returns (uint reserveA, uint reserveB) {
        // 先对传入的tokenA和B进行排序，因为在v2-core合约中, token0是地址较小的；
        (address token0,) = sortTokens(tokenA, tokenB);
        // 获取token A和B 交易对中恒定乘积的各资产的值
        (uint reserve0, uint reserve1,) = IUniswapV2Pair(pairFor(factory, tokenA, tokenB)).getReserves();
        // 因为返回的资产值是排序过的，而输入参数是不会有排序的，所以这里做了处理
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    /**
        @dev 根据比例由一种资产计算另一种资产的值
        @notice: 如果不涉及交易费用的话，此函数将返回给您代币 A 兑换得到的代币 B
        @param amountA 传入某tokenA的资产数量
        @param reserveA 交易对中tokenA的储备量
        @param reserveB 交易对中tokenB的储备量
        @return {uint} amountB 返回代币 A 兑换得到的代币 B的数量
     */
    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint amountB) {
        require(amountA > 0, 'UniswapV2Library: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        amountB = amountA.mul(reserveB) / reserveA;
    }

    /**
        @dev A/B 交易对中卖出 A 资产，计算买进的 B 资产的数量
        @notice: 重要：：：手续费从卖出的资产中扣除，这里为千之分三的交易手续费
        @param amountIn 传入某tokenA的资产数量
        @param reserveIn 交易对中tokenA的储备量，传入tokenA前；
        @param reserveOut 交易对中tokenB的储备量，传入tokenA前；
        @return {uint} amountOut 返回代币 A 兑换得到的代币 B的数量
     */
    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT'); // 传入tokenA数量必须大于0
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY'); // 当前资产储备量必须大于0；
        // 不考虑手续费时，能获得的tokenB资产为 B0 = A0 * B / ( A + A0)；这里考虑手续费，则将前面的A0使用997*A0/1000代替,这里即为A0'；
        uint amountInWithFee = amountIn.mul(997);   // 从卖出（也就是传入池中）的资产中扣除千分之三的手续费；
        uint numerator = amountInWithFee.mul(reserveOut); // A0' * B
        uint denominator = reserveIn.mul(1000).add(amountInWithFee); // A + A0'
        amountOut = numerator / denominator;    // A0' * B / ( A + A0')
    }

    /**
        @dev A/B 交易对中买进 B 资产，计算卖出的 A 资产的数量
        @notice: 重要：：：手续费从卖出的资产中扣除，这里为千分之三的交易手续费
        @param amountOut 希望买进的tokenB资产数量
        @param reserveIn 交易对中tokenA的储备量，卖出tokenB前；
        @param reserveOut 交易对中tokenB的储备量，卖出tokenB前；
        @return {uint} amountIn 返回买进 B 资产，需要卖出的 A 资产的数量；
     */
    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) internal pure returns (uint amountIn) {
        require(amountOut > 0, 'UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT'); // 购买（即从池中提取）的tokenB数量必须大于0
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');  // 当前资产储备量必须大于0；
        // 不考虑手续费时，需要的tokenA资产为 A0 = A * B0 / ( B - B0)；这里考虑手续费，则将前面的A0使用997*A0/1000代替,这里即为A0'；
        uint numerator = reserveIn.mul(amountOut).mul(1000); // 
        uint denominator = reserveOut.sub(amountOut).mul(997);
        amountIn = (numerator / denominator).add(1);
    }

    /**
        @dev 计算链式交易中卖出某资产，得到的中间资产和最终资产的数量。例如 A/B => B/C 卖出 A，得到 BC 的数量。
        @param factory 工厂合约地址，用于获取交易对合约地址
        @param amountIn 卖出amountIn数量的tokenA，tokenA对于path参数的第一个值，即path[0]
        @param path 链路中，对应的资产合约地址
        @return {uint[]} amounts 返回卖出tokenA资产，能够获得的其他资产的数量；例如 A/B => B/C 卖出 A，得到 BC 的数量。
     */
    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(address factory, uint amountIn, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'UniswapV2Library: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        for (uint i; i < path.length - 1; i++) {
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    /**
        @dev 计算链式交易中买进某资产，需要卖出的中间资产和初始资产数量。例如 A/B => B/C 买进 C，得到 AB 的数量
        @param factory 工厂合约地址，用于获取交易对合约地址
        @param amountIn 想要买入amountOut数量的tokenC，tokenC对于path参数的最后一个值，即path[path.length-1]
        @param path 链路中，对应的资产合约地址
        @return {uint[]} amounts 返回买入tokenC资产，需要卖出的其他资产的数量；。例如 A/B => B/C 买进 C，得到 AB 的数量
     */
    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn(address factory, uint amountOut, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'UniswapV2Library: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint i = path.length - 1; i > 0; i--) {
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }
}
