const core = require('@actions/core');
const exec = require('@actions/exec');

async function run() {
    try {
        const folder = __dirname.replace(/[/\\]dist$/, '')
        const script = `${folder}/action.ps1`
        await exec.exec('pwsh', ['-f', script])
    } catch (error) {
        core.setFailed(error.message)
    }
}
run()
