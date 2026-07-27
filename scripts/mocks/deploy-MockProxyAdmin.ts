import { deployAndSave } from './_lib'

async function main() {
    await deployAndSave('MockProxyAdmin')
}

main().catch((error) => {
    console.error(error)
    process.exitCode = 1
})
