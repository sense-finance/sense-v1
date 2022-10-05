#!/bin/bash

# Bold High Intensity Green
BIGreen=$'\e[1;92m'

# go to pkg/core directory
cd "$(dirname "$3")";

# run for all possible combinations between ERC20 and non-ERC20 target, underlying and stake and 6, 8 and 18 decimals
for c in {true,false}\ {true,false}\ {true,false}\ {6,8,18}\ {6,8,18}\ {6,8,18} ; do
    IFS=' '
    targetType="ERC20" && [[ combination[0] == false ]]  && targetType="non-ERC20"
    underlyingType="ERC20" && [[ combination[1] == false ]]  && targetType="non-ERC20"
    stakeType="ERC20" && [[ combination[2] == false ]]  && targetType="non-ERC20"

    read -ra combination <<< "$c";
    echo "${BIYellow}--------------------------------------------------";
    echo "${BIYellow}TEST CASE INFO";
    echo "";
    echo "${BIYellow}Target is ${targetType} with ${combination[3]} decimals";
    echo "${BIYellow}Underlying is ${underlyingType} with ${combination[4]} decimals";
    echo "${BIYellow}Stake is ${stakeType} with ${combination[5]} decimals";
    echo "${BIYellow}--------------------------------------------------";
    
    export NON_ERC20_TARGET=${combination[0]};
    export NON_ERC20_UNDERLYING=${combination[1]};
    export NON_ERC20_STAKE=${combination[2]};
    export TARGET_DECIMALS=${combination[3]};
    export UNDERLYING_DECIMALS=${combination[4]};
    export STAKE_DECIMALS=${combination[5]};
    forge test --no-match-path "*.tm*";
done

# run, for ERC4626 target, all possible combinations between 6, 8 and 18 target (and underlying) decimals
# NOTE that in the case of ERC4626 tokens, target always have the underlyin's decimals
for c in {6,8,18}\ ; do
    IFS=' '
    read -ra combination <<< "$c";
    echo "${BIYellow}--------------------------------------------------";
    echo "${BIYellow}TEST CASE INFO";
    echo "";
    echo "${BIYellow}Target is ERC4626 with ${combination[0]} decimals";
    echo "${BIYellow}Underlying is ERC4626 with ${combination[0]} decimals";
    echo "${BIYellow}--------------------------------------------------";

    export ERC4626_TARGET=true;
    export TARGET_DECIMALS=${combination[0]};
    export UNDERLYING_DECIMALS=${combination[0]};
    forge test --match-path "**/*.t.sol" --no-match-path "**/Adapter.t.sol";
done