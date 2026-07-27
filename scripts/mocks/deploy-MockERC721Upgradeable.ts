import { deployAndSave } from './_lib'

async function main() {
    await deployAndSave('MockERC721Upgradeable', async (c) => {
        await c.initialize('MockERC721Upgradeable', 'MOCK')
    })
}

main().catch((error) => {
    console.error(error)
    process.exitCode = 1
})
