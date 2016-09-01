require 'rails/generators/base'

class HerokuRailsDeployGenerator < Rails::Generators::Base
  source_paths << File.join(File.dirname(__FILE__), 'templates')

  def create_config_file
    template('heroku.yml', 'config/heroku.yml')
  end

  def create_executable_file
    template('deploy', 'bin/deploy')
    chmod('bin/deploy', 0755)
  end
end
