import { deployAndSave } from './_lib'

async function main() {
    await deployAndSave('MockERC1155')
}

main().catch((error) => {
    console.error(error)
    process.exitCode = 1
})
