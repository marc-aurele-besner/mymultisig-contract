import { MyMultiSigStandardTests, MyMultiSigExtendedTests, DeploymentType } from './shared/tests'

describe('MyMultiSig - Deployed From Factory With ChugSplash', function () {
  MyMultiSigStandardTests(DeploymentType.WithChugSplash)
  MyMultiSigExtendedTests(DeploymentType.WithChugSplash)
})
