import constants from '../../constants'
import errors from './errors'
import functions from './functions'
import setup from './setup'

export default {
  ...constants,
  errors,
  ...functions,
  ...setup,
}
