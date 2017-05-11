# heroku_rails_deploy

## v0.4.2
- Fix test for pending migrations.

## v0.4.1
- Fix bug checking environment.

## v0.4.0
- Refactor to expose environment from `Deployer`.

## v0.3.0
- Add support for Avro schema registration during deployment.
- Refuse to deploy when there are uncommitted changes.

## v0.2.2
- Fixes bug in getting branch name from executing system command

## v0.2.1
- Fixes bug in checking for valid production deploy

## v0.2.0
- Can only deploy master or gitflow prefixed branches (hotfix/.+ and release/.+)

## v0.1.0
- Initial version
