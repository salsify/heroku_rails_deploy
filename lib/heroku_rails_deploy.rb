require 'heroku_rails_deploy/version'
require 'heroku_rails_deploy/deployer'

module HerokuRailsDeploy
  def self.deploy(root_dir, args)
    config_file = File.join(root_dir, 'config', 'heroku.yml')
    Deployer.new(config_file, args).run
  end
end
