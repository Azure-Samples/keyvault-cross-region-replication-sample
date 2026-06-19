# Sample Requirements

## Release 1

- Sample scope is only Certificate replication from one KeyVault to another, but the design should be flexible enough to allow for future expansion to include secrets and keys replication as well
- PowerShell is used as a language
- KeyVault replication from one region to KeyVault in another is done by subscribing to EventGrid events and using a Function App to handle the replication logic
- The Function App is triggered by EventGrid events when a new secret is created or updated in the source KeyVault
- There is a need to handle the replication of secrets, keys, and certificates from the source KeyVault to the destination KeyVault
- There is a need for initial synchronization of existing secrets, keys, and certificates from the source KeyVault to the destination KeyVault
- There is a need for constant failure check to make sure event was not missed and replication is successful
- Every failure is logged and an alert is sent to the responsible team for further investigation
- Application Insights is used for logging and monitoring the Function App
- Alerts are configured in Application Insights to notify the responsible team in case of failures or issues with the replication process
- The Function App should be designed to handle retries in case of transient failures during the replication process
- The Function App should be designed to handle rate limiting and throttling scenarios when interacting with the KeyVault APIs
- The Function App should be designed to handle scenarios where the destination KeyVault is temporarily unavailable or experiencing issues
- Test Automation suite is available to regression test the functionality of the replication process and ensure that it continues to work as expected after any changes or updates
- The Test Automation environment is deployed with Bicep templates to ensure consistency and reproducibility of the test environment
- GH Action is used to automate the deployment of the Test Automation environment and run the regression tests as part of the CI/CD pipeline, The same pipeline is used to deploy the Function App and other related resources to the production environment, ensuring that the deployment process is consistent and repeatable across different environments
- Function App exposes health check endpoints to allow for monitoring and alerting on the health of the replication process. The health check endpoints provide information on the status of the replication process, including the number of secrets, keys, and certificates that have been successfully replicated, as well as any failures or issues that have occurred.
- Application Insights is used to monitor the health check endpoints and provide alerts in case of any issues or failures with the replication process. The health check endpoints are also used to provide visibility into the performance and efficiency of the replication process, allowing for optimization and improvement over time.
- Project is separated into "Infrastructure" (Bicep), "App" (Function app and associated application components), Tests (for test automation)
- Solution design is available here ./README.md
- All pre-requisites are documented in ./README.md and installed (e.g. Azure CLI, PowerShell modules, Function SDK, etc) - script is provided to install all pre-requisites
- GHCP iterates and validates Sample is completed and functional, and all requirements are met until it completes (I do not need to keep re-testing - I only need to test once and then GHCP will validate the requirements are met)

## Release 1.1

- Test Data is generated and managed to support the Test Automation suite, allowing for comprehensive testing of various scenarios and edge cases related to the replication process
- How to use this sample is documented in the README, including instructions on how to deploy the infrastructure, run the Function App, and execute the Test Automation suite. The documentation also includes information on the architecture and design of the solution, as well as any relevant considerations or best practices for using the sample effectively.

## Release 2

- Function App is containerized and deployed to Azure Functions using a Docker container (if PowerShell support is available in Azure Functions containers by the time of release 2, otherwise this requirement will be adjusted accordingly)
- Function App is deployed with Private Endpoint to enhance security and restrict access to the Function App
- Function App is deployed with Managed Identity to allow for secure authentication and authorization when accessing Azure resources
- Application Insights continue to be used and is able to monitor Private Endpoint configured Function App and provide the same functionality as in Release 1