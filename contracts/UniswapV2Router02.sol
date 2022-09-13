pragma solidity =0.6.6;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/lib/contracts/libraries/TransferHelper.sol';

import './interfaces/IUniswapV2Router02.sol';
import './libraries/UniswapV2Library.sol';
import './libraries/SafeMath.sol';
import './interfaces/IERC20.sol';
import './interfaces/IWETH.sol';

contract UniswapV2Router02 is IUniswapV2Router02 {
    using SafeMath for uint;
    // 使用两个状态变量分别记录了`factory`合约的地址`WETH`合约的地址
    // 状态变量的override关键词：如果`external`函数的参数和返回值同公共状态变量的`getter`函数相符的话，这个公共状态变量可以重写该函数
    // 这里重写了function factory() external pure returns (address); WETH类似;
    address public immutable override factory;
    address public immutable override WETH;

    modifier ensure(uint deadline) { // 判定当前区块（创建）时间不能超过最晚交易时间
        require(deadline >= block.timestamp, 'UniswapV2Router: EXPIRED');
        _;
    }

    /**
        @dev 构造函数, 将上面两个`immutable`状态变量初始化
        @param _factory `factory`合约的地址
        @param _WETH `WETH`合约的地址
     */
    constructor(address _factory, address _WETH) public {   
        factory = _factory;
        WETH = _WETH;
    }

    /**
        @dev 回调函数, 接收 ETH
        @notice: 从 Solidity 0.6.0 起，没有匿名回调函数了。
        它拆分成两个,一个专门用于接收 ETH，就是这个`receive`函数。另外一个在找不到匹配的函数时调用，叫`fallback`函数
     */
    receive() external payable {    
        // 限定只能从`WETH`合约直接接收 ETH，也就是在 WETH 提取为 ETH 时
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    // **** ADD LIQUIDITY ****
    /**
        @dev 增加流动性:计算拟向交易对合约注入的代币数量，为`internal`函数，提供给多个外部接口调用
        @notice: 交易对数量按比例注入的原因是：在Core合约中，计算LP token数量是根据注入的两种代币的数量进行计算，然后取最小值。
        如果不按比例交易对比例来充，就会有一个较大值和一个较小值，取最小值流行性提供者就会有损失。
        如果按比例充，则两种代币计算的结果一样的，也就是理想值，不会有损失。
        @param tokenA 交易对中两种代币的地址之一
        @param tokenB 交易对中两种代币的另一个地址
        @param amountADesired 计划注入的tokenA代币数量
        @param amountBDesired 计划注入的tokenB代币数量
        @param amountAMin 计划注入tokenA代币的最小值（否则重置）
        @param amountBMin 计划注入tokenB代币的最小值（否则重置）    
        @return amountA 拟向该交易对合约注入的tokenA代币数量
        @return amountB 拟向该交易对合约注入的tokenB代币数量
     */
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal virtual returns (uint amountA, uint amountB) {
        // create the pair if it doesn't exist yet, 如果交易对不存在（获取的地址为零值），则创建之
        // 这里不能通过库函数的pairFor计算获取，因为不管目前交易对存不存在，都能获取到交易对合约地址
        if (IUniswapV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            IUniswapV2Factory(factory).createPair(tokenA, tokenB);
        }
        // 获取交易对资产池中两种代币 reserve 数量，当然如果是刚创建的，就都是 0
        (uint reserveA, uint reserveB) = UniswapV2Library.getReserves(factory, tokenA, tokenB);
        
        if (reserveA == 0 && reserveB == 0) { // 如果是刚创建的交易对，则拟注入的代币全部转化为流动性
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else { // 选择以哪种代币作为标准计算实际注入数量
            uint amountBOptimal = UniswapV2Library.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = UniswapV2Library.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }
    
    /**
        @dev 增加流动性:计算拟向交易对合约注入的代币数量，为`internal`函数，提供给多个外部接口调用
        @notice: 交易对数量按比例注入的原因是：在Core合约中，计算LP token数量是根据注入的两种代币的数量进行计算，然后取最小值。
        如果不按比例交易对比例来充，就会有一个较大值和一个较小值，取最小值流行性提供者就会有损失。
        如果按比例充，则两种代币计算的结果一样的，也就是理想值，不会有损失。
        @param tokenA 交易对中两种代币的地址之一
        @param tokenB 交易对中两种代币的另一个地址
        @param amountADesired 计划注入的tokenA代币数量
        @param amountBDesired 计划注入的tokenB代币数量
        @param amountAMin 计划注入tokenA代币的最小值（否则重置）
        @param amountBMin 计划注入tokenB代币的最小值（否则重置）
        @param to 接受流动性代币的地址
        @param deadline 最迟交易时间
        @return amountA 拟向该交易对合约注入的tokenA代币数量
        @return amountB 拟向该交易对合约注入的tokenB代币数量    
        @return liquidity 流动性提供者拟获得的流动性代币数量    
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        // 计算需要向交易对合约转移（注入）的实际代币数量。
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        // 获取交易对地址（注意，如果交易对不存在，在对`_addLiquidity`调用时会创建），这里通过库函数获取交易对合约地址可能是因为节省gas
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        // 将实际注入的代币转移至交易对
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        // 调用交易对合约的`mint`函数来给接收者增发流动性
        liquidity = IUniswapV2Pair(pair).mint(to);
    }

    /**
        @dev 增加流动性:交易对的其中一种货币为ETH
        @notice: 随本函数发送的 ETH 数量就是拟注入的ETH数量
        @param token 交易对中的ERC20代币
        @param amountTokenDesired 计划注入的ERC20代币数量
        @param amountTokenMin 计划注入ERC20代币的最小值（否则重置）
        @param amountETHMin 计划注入ETH代币的最小值（否则重置）
        @param to 接受流动性代币的地址
        @param deadline 最迟交易时间
        @return amountToken 拟向该交易对合约注入的ERC20代币数量
        @return amountETH 拟向该交易对合约注入的ETH代币数量    
        @return liquidity 流动性提供者拟获得的流动性代币数量    
    */
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external virtual override payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        (amountToken, amountETH) = _addLiquidity( // 调用`_addLiquidity`函数来计算优化后的注入代币值
            token,
            WETH,   // 使用WETH代替ETH
            amountTokenDesired,
            msg.value,  //传入ETH代币数量为WETH代币数量
            amountTokenMin,
            amountETHMin
        );
        address pair = UniswapV2Library.pairFor(factory, token, WETH); // 计算并获取token和WETH地址的交易对
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken); // 将实际注入的ERC20代币转移至交易对
        IWETH(WETH).deposit{value: amountETH}(); // ETH 兑换成 WETH
        assert(IWETH(WETH).transfer(pair, amountETH));  // 将刚刚兑换的 WETH 转移至交易对合约
        liquidity = IUniswapV2Pair(pair).mint(to);  // 调用交易对合约的`mint`函数来给接收者增发流动性
        // refund dust eth, if any, 返还多余的ETH
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
    }

    // **** REMOVE LIQUIDITY ****
    /**
        @dev 移除流动性: 移除（燃烧）流动性（代币），从而提取交易对中注入的两种代币
        @notice: 
        @param tokenA 交易对中两种代币的地址之一
        @param tokenB 交易对中两种代币的另一个地址
        @param liquidity 燃烧的流动性代币数量
        @param amountAMin 提取的tokenA最小代币数量（保护用户）
        @param amountBMin 提取的tokenB最小代币数量（保护用户）
        @param to 接受交易对代币的地址
        @param deadline 最迟交易时间
        @return amountA 最终提取的tokenA代币数量
        @return amountB 最终提取的tokenB代币数量      
    */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB); // 计算并获取token和WETH地址的交易对
        // send liquidity to pair，先将流动性代币转入交易对地址
        IUniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity); 
        // 调用交易对的`burn`函数，燃烧掉刚转过去的流动性代币，提取相应的两种代币给接收者
        (uint amount0, uint amount1) = IUniswapV2Pair(pair).burn(to);
        // 用于判断amount0 和 amount1数量对应的token，因为交易对合约返回的结果按代币地址从小到大排序
        (address token0,) = UniswapV2Library.sortTokens(tokenA, tokenB);
        // 分别获取tokenA和tokenB可提取数量
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        // 确保提取的数量不能小于用户指定的下限，否则重置交易（防止LP三明治攻击）
        require(amountA >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
    }

    /**
        @dev 移除流动性:期望获得一种货币为ETH，意味着该交易对必须为一个 ERC20/WETH 交易对
        @notice: 只有交易对中包含了 WETH 代币，才能提取交易对资产池中的 WETH，然后再将 WETH 兑换成 ETH 给接收者
        @param token 交易对中的ERC20代币
        @param liquidity 燃烧的流动性代币数量
        @param amountTokenMin 计划注入ERC20代币的最小值（否则重置）
        @param amountETHMin 计划注入ETH代币的最小值（否则重置）
        @param to 接受流动性代币的地址
        @param deadline 最迟交易时间
        @return amountToken 最终提取的ERC20代币数量
        @return amountETH 最终提取的ETH数量
    */
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountToken, uint amountETH) {
        // 调用上一个函数`removeLiquidity`来进行流动性移除操作，只不过将提取资产的接收地址改成本合约
        (amountToken, amountETH) = removeLiquidity( 
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken); // 将燃烧流动性提取的ERC20 代币（非 WETH）转移给接收者
        IWETH(WETH).withdraw(amountETH); // 将燃烧流动性提取的 WETH 换成 ETH
        TransferHelper.safeTransferETH(to, amountETH); // 将兑换的 ETH 发送给接收者
    }

    /**
        @dev 移除流动性: 移除（燃烧）流动性（代币），从而提取交易对中注入的两种代币
        @notice: 它和`removeLiquidity`函数的区别在于本函数支持使用线下签名消息来进行授权验证，
        从而不需要提前进行授权（这样会有一个额外交易），授权和交易均发生在同一个交易里
        @param approveMax 是否授权流动性代币给该地址的数量为 uint256 最大值 (2 ** 256 -1)
        @param v 用于链下签名的验证数据, 具体见核心合约的permit函数
        @param r 同r
        @param s 同s
        @return amountA 最终提取的tokenA代币数量
        @return amountB 最终提取的tokenB代币数量      
    */
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountA, uint amountB) {
        // 计算并获取交易对合约地址
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        // 授权的流动性代币uul
        uint value = approveMax ? uint(-1) : liquidity;
        // 利用链下签名验证数据，进行ERC20token授权操作
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        // 移除流动性
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    /**
        @dev 移除流动性: 移除（燃烧）流动性（代币），从而提取交易对中注入的两种代币
        @notice: 功能同`removeLiquidityWithPermit`类似，只不过将最后提取的资产由 ERC20 变为 ETH
        @param approveMax 是否授权流动性代币给该地址的数量为 uint256 最大值 (2 ** 256 -1)
        @param v 用于链下签名的验证数据, 具体见核心合约的permit函数
        @param r 同r
        @param s 同s
        @return amountToken 最终提取的ERC20代币数量
        @return amountETH 最终提取的ETH数量  
    */
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountToken, uint amountETH) {
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        uint value = approveMax ? uint(-1) : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    /**
        @dev 移除流动性:期望获得一种货币为ETH，意味着该交易对必须为一个 ERC20/WETH 交易对
        @notice: 相比`removeLiquidityETH`函数：
        1.  函数返回参数及`removeLiquidity`函数返回值中没有了`amountToken`。
            因为它的一部分可能要支付手续费，所以`removeLiquidity`函数的返回值不再为当前接收到的代币数量。
        2.  不管损耗多少，它把本合约接收到的所有此类 TOKEN 直接发送给接收者。
        3.  WETH 不是可支付转移手续费的代币，因此它不会有损耗。
        @param token 交易对中的ERC20代币
        @param liquidity 燃烧的流动性代币数量
        @param amountTokenMin 计划注入ERC20代币的最小值（否则重置）
        @param amountETHMin 计划注入ETH代币的最小值（否则重置）
        @param to 接受流动性代币的地址
        @param deadline 最迟交易时间
        @return amountETH 最终提取的ETH数量
    */
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountETH) {
        (, amountETH) = removeLiquidity( // 
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    /**
        @dev 移除流动性:期望获得一种货币为ETH，意味着该交易对必须为一个 ERC20/WETH 交易对
        @notice: 功能同`removeLiquidityETHSupportingFeeOnTransferTokens`函数相同，但是支持使用链下签名消息进行授权
    */
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountETH) {
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        uint value = approveMax ? uint(-1) : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(
            token, liquidity, amountTokenMin, amountETHMin, to, deadline
        );
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    /**
        @dev 内部函数，将交易资产的核心逻辑抽象为一个函数
        @notice: 需要事先将初始数量的代币发送到第一个交易对（ 这是 UniswapV2 的先转移后交易特性决定的）
        @param amounts swap链路中，每个token的待转移数量，其中
        1. `amounts[0]`为用户卖出的path[0]代币的初始资产数量
        2. `amounts[length-1]`为用户最终买进的path[length-1]代币的资产数量
        3. `amounts[中间值]`则为前一个交易对（A/B 交易对）的买进值，同时也是下一个交易对（B/C 交易对）的卖出值
        @param path swap链路中，每个ERC20的合约地址
        @param _to 接受流动性代币的地址
        @return amountETH 最终提取的ETH数量
    */
    function _swap(uint[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]); // 来获取当前交易对中的两种代币地址
            (address token0,) = UniswapV2Library.sortTokens(input, output); // 获取较小的代币地址
            uint amountOut = amounts[i + 1]; // 从`amounts`中获取当前交易对的买进值（同时也是下一交易对的卖出值，如果还有交易对的话）
            // 经过地址排序后，这里需要判断input是token0还是token1
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            // 计算当前交易对的接收地址。因为 UniswapV2 是一个交易代币先行转入系统，所以下一个交易对就直接是前一个交易对的接收地址了（如果还有下一个交易对）
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;
            // 计算了当前交易对的地址，然后调用了该地址交易对合约的`swap`接口
            IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }

    /**
        @dev 指定卖出固定数量的某种资产，买进特定数量（该值由计算得来）的另一种资产；同时支持交易对链
        @notice: 这里，用户欲卖出的资产转移到了第一个交易对合约中，该资产是一种 ERC20 代币，因此必须先得到用户的授权
        @param amountIn 卖出的初始资产数量，这里的初始资产就是path[0]
        @param amountOutMin 期望得到的最小数量的资产
        @param path 交易对链：swap链路中，每个ERC20的合约地址
        @param to 接受地址
        @param deadline 最迟交易时间
        @return amounts 交易对链中，每个token的待转移数量，见_swap函数
    */
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        // 计算当前该链式交易的`amounts`，注意它使用了自定义工具库的`getAmountsOut`函数进行链上实时计算的，
        // 所以得出的值是准确的最新值。`amounts[0]`就是卖出的初始资产数量，也就是`amountIn`。
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        // 验证最终买进的代币数量不能小于用户限定的最小值（防止价格波动较大，超出用户的预期）
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        // 将拟卖出的初始资产转移到第一个交易对合约地址中去，这正好映证了`_swap`函数的注释，必须先转移卖出资产到交易对
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        // 调用`_swap`函数进行交易操作
        _swap(amounts, path, to);
    }

    /**
        @dev 指定交易时买进的资产数量，而卖出的资产数量则不指定，该值可以通过计算得来；同时支持交易对链
        @param amountOut 拟买进的资产的数量，这里的买进资产就是path[length-1]
        @param amountInMax 期望指定卖出资产（path[0]）的最大值（保护用户，防止价格波动过大从而使卖出资产数量大大超过用户预期）
        @param path 交易对链：swap链路中，每个ERC20的合约地址
        @param to 接受地址
        @param deadline 最迟交易时间
        @return amounts 交易对链中，每个token的待转移数量，见_swap函数
    */
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        // 调用库函数来计算返回值`amounts`，因为它是同一个交易里合约实时计算，所以不必担心时效性问题，总是交易时的最新值
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }
    
    /**
        @dev 同`swapExactTokensForTokens`类似，只不过将初始卖出的 Token 换成了 ETH
        @notice 注意这里函数参数不再有`amountInMax`，因为随方法发送的 ETH 数量就是用户指定的最大值（WETH 与 ETH 是等额 1:1 兑换的）
    */
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsOut(factory, msg.value, path);
        // 验证最终买进的资产数量必须大于用户指定的值，防止价格波动太大
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0]}();
        // 本函数没有转移用户的 ERC20 代币，所以没有授权操作。
        // ETH 兑换后的 WETH 就在本合约里，是合约自己的资产，所以调用了 WETH 合约的`transfer`方法而不是`transferFrom`方法
        assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }

    /**
        @dev 同`swapTokensForExactTokens`类似，只不过指定买进的不是 Token（ERC20 代币），而是 ETH
        @notice 交易链的最后一个代币地址必须为 WETH，这样才会买进 WETH，然后再将它兑换成等额 ETH
    */
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        // 验证计算得到的卖出资产数量必须小于用户限定的最大值，价格保护
        require(amounts[0] <= amountInMax, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }
    
    /**
        @dev 同 ``swapExactTokensForTokens`函数类似，只不过将最后获取的ERC20代币改成ETH了
        @notice 交易链的最后一个代币地址必须为WETH，这样才能卖进WETH然后再兑换成等额ETH
    */
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        // 交易链的最后一个代币地址必须为WETH，这样才能卖进WETH然后再兑换成等额ETH
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        // 将WETH换成ETH，并转移给用户
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    /**
        @dev 同 ``swapTokensForExactTokens`函数类似，只不过将卖出的ERC20代币改成ETH了
        @notice 交易链的第一个代币地址必须为WETH，这样才能卖进WETH然后再兑换成等额ETH
    */
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        // refund dust eth, if any
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
        /**
        @dev 内部函数，将交易资产的核心逻辑抽象为一个函数
        @notice: 
            1. 需要事先将初始数量的代币发送到第一个交易对（ 这是 UniswapV2 的先转移后交易特性决定的）
            2. 该函数和本合约的`_swap`主要区别就是交易链交易过程中转移的资产数量不再提前使用工具库函数计算好，而是在函数内部根据实际数值计算。
        @param path swap链路中，每个ERC20的合约地址
        @param _to 接受流动性代币的地址
        @return amountETH 最终提取的ETH数量
    */
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]); // 来获取当前交易对中的两种代币地址
            (address token0,) = UniswapV2Library.sortTokens(input, output); // 获取较小的代币地址
            IUniswapV2Pair pair = IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output)); // 获取交易对地址
            uint amountInput;  // 卖出资产的数量
            uint amountOutput; // 买进资产的数量
            { // scope to avoid stack too deep errors, 根据交易对地址实际拥有的path中代币余额进行计算amount0Out和amount1Out
            // 获取交易对资产池中两种资产的值（用于恒定乘积计算的），注意这两个值是按代币地址（不是按代币数量）从小到大排过序的
            (uint reserve0, uint reserve1,) = pair.getReserves();
            // 将交易对资产池中两种资产的值和第一行中获取的两个代币地址对应起来
            (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            // 计算当前交易对卖出资产的数量（交易对地址的代币余额减去交易对资产池中的值，即最新的资产值减去池中的资产值）
            amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
            // 根据恒定乘积算法来计算当前交易对买进的资产值
            amountOutput = UniswapV2Library.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            // 经过地址排序后，这里需要判断input是token0还是token1
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            // 计算当前交易对的接收地址。因为 UniswapV2 是一个交易代币先行转入系统，所以下一个交易对就直接是前一个交易对的接收地址了（如果还有下一个交易对）
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0)); // 调用了该地址交易对合约的`swap`接口
        }
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) {
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amountIn
        );
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        payable
        ensure(deadline)
    {
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
        uint amountIn = msg.value;
        IWETH(WETH).deposit{value: amountIn}();
        assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amountIn));
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        ensure(deadline)
    {
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint amountOut = IERC20(WETH).balanceOf(address(this));
        require(amountOut >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(uint amountA, uint reserveA, uint reserveB) public pure virtual override returns (uint amountB) {
        return UniswapV2Library.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountOut)
    {
        return UniswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountIn)
    {
        return UniswapV2Library.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint amountIn, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return UniswapV2Library.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint amountOut, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return UniswapV2Library.getAmountsIn(factory, amountOut, path);
    }
}
