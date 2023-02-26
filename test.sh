#\/usr/bin/bash

BLUE='\033[0;34m'
BBLUE='\033[1;34m'
BGREEN='\033[1;32m'
BYELLOW='\033[1;33m'
BRED='\033[1;31m'
NC='\033[0m'

printf "${BLUE}
 __  __       __  __       _ _   _     _       
|  \/  |     |  \/  |     | | | (_)   (_)      
| \  / |_   _| \  / |_   _| | |_ _ ___ _  __ _ 
| |\/| | | | | |\/| | | | | | __| / __| |/ _\` |
| |  | | |_| | |  | | |_| | | |_| \__ \ | (_| |
|_|  |_|\__, |_|  |_|\__,_|_|\__|_|___/_|\__, |
         __/ |                            __/ |
        |___/                            |___/ 
${BBLUE}Let's make sure git is installed 📦
${NC}"

# Verify if git is installed
if ! [ -x "$(command -v git)" ]; then
  printf "${BRED}Git is not installed. Please install it before running this script.
${NC}"
  exit 1
fi

printf "${BGREEN}Let's make sure the branch is up to date 🔄
${NC}"

# Make sure the branch is up to date
git pull

printf "${BYELLOW}Let's verify if Yarn is installed 📦
${NC}"

# Verify if Yarn is installed
if ! [ -x "$(command -v yarn)" ]; then
  printf "${BRED}Yarn is not installed. Please install it before running this script.
${NC}"
  exit 1
fi

printf "${BGREEN}Let's install the dependencies 📦
${NC}"

# Install the dependencies
yarn

printf "${BBLUE}Let's make sure the dependencies are up to date 📦
${NC}"

# Make sure the dependencies are up to date
yarn outdated

printf "${BYELLOW}Let's make sure we build the latest version of the contracts ABI 📦
${NC}"

yarn build

printf "${BYELLOW}Let's make sure the contracts are compiled 📦
${NC}"

# Make sure the contracts are compiled
yarn hardhat compile

printf "${BYELLOW}Let's run the tests 🧪
${NC}"

# Run hardhat test
yarn hardhat test

printf "${BBLUE}Let's run foundry tests 🧪
${NC}"

# Run foundry test
forge test