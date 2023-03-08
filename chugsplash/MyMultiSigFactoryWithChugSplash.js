module.exports = {
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
      },
      constructorArgs: {},
    },
  },
}
