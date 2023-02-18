import { UserChugSplashConfig } from '@chugsplash/core'

const config: UserChugSplashConfig = {
  options: {
    projectName: 'MyMultiSigFactory',
  },
  contracts: {
    MyMultiSigFactory: {
      contract: 'MyMultiSigFactoryWithChugSplash',
      variables: {
        _multiSigCount: 0,
        _multiSigs: [],
        _multiSigIndex: [],
        _multiSigCreatorCount: [],
        _multiSigIndexByCreator: [],
      },
    },
  },
}

export default config
