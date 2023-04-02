import { MyMultiSigStandardTests, MyMultiSigExtendedTests, DeploymentType } from './shared/tests'

describe('MyMultiSig - Deployed From Factory', function () {
  MyMultiSigStandardTests(DeploymentType.WithFactory)
  MyMultiSigExtendedTests(DeploymentType.WithFactory)
})
