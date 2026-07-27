import { deployAndSave } from './_lib'

async function main() {
    await deployAndSave('MockERC1155Upgradeable', async (c) => {
        await c.initialize('MockERC1155', 'MOCK', 'https://google.com')
    })
}

main().catch((error) => {
    console.error(error)
    process.exitCode = 1
})
