import { deployAndSave } from './_lib'

async function main() {
    await deployAndSave('MockERC20Upgradeable', async (c) => {
        await c.initialize('MockERC20Upgradeable', 'MOCK')
    })
}

main().catch((error) => {
    console.error(error)
    process.exitCode = 1
})
