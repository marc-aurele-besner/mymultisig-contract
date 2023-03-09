import { UserChugSplashConfig } from '@chugsplash/core'

const config: UserChugSplashConfig = {
  options: {
    projectName: 'MyMultiSigFactoryWithChugSplash',
  },
  contracts: {
    MyMultiSigFactoryWithChugSplash: {
      contract: 'MyMultiSigFactoryWithChugSplash',
      variables: {
        _multiSigCount: 0,
        _multiSigs: {},
        _multiSigIndex: {},
        _multiSigCreatorCount: {},
        _multiSigIndexByCreator: {},
        _multiSigCreationType: {},
      },
      constructorArgs: {},
    },
  },
}

export default config
