// Tests/infra/test-env.bicep — Deploys an isolated test environment by composing the
// same modules as the production infrastructure. Unique resource names are supplied by
// Deploy-TestEnvironment.ps1 at deploy time.

using '../../Infrastructure/main.bicep'
