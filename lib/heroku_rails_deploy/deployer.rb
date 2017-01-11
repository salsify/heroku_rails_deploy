require 'optparse'
require 'yaml'

module HerokuRailsDeploy
  class Deployer
    PRODUCTION_BRANCH_REGEX = /\A((master)|(release\/.+)|(hotfix\/.+))\z/

    attr_reader :config_file, :args

    class Options < Struct.new(:environment, :revision)
      def self.create_default(app_registry)
        new(app_registry.keys.first, 'HEAD')
      end
    end

    def initialize(config_file, args)
      @config_file = config_file
      @args = args
    end

    def run
      raise "Missing config file #{config_file}" unless File.file?(config_file)
      app_registry = YAML.load(File.read(config_file))

      options = Options.create_default(app_registry)
      OptionParser.new do |parser|
        parser.on_tail('-h', '--help', 'Show this message') do
          puts parser
          # rubocop:disable Lint/NonLocalExitFromIterator
          return
          # rubocop:enable Lint/NonLocalExitFromIterator
        end

        parser.on('-e', '--environment ENVIRONMENT',
                  "The environment to deploy to. Must be in #{app_registry.keys.join(', ')} (default #{app_registry.keys.first})") do |environment|
          options.environment = environment
        end

        parser.on('-r', '--revision REVISION',
                  'The git revision to push. (default HEAD)') do |revision|
          options.revision = revision
        end
      end.parse!(args)

      app_name = app_registry.fetch(options.environment) do
        raise OptionParser::InvalidArgument.new("Invalid environment '#{options.environment}'. " \
          "Must be in #{app_registry.keys.join(', ')}")
      end

      raise 'Only master, release or hotfix branches can be deployed to production' if options.environment == 'production' && !production_branch?

      puts "Pushing code to Heroku app #{app_name} for environment #{options.environment}"
      push_code(app_name, options.revision)

      puts 'Checking for pending migrations'
      if pending_migrations?(app_name)
        puts 'Running migrations'
        run_migrations(app_name)
        puts 'Restarting dynos'
        restart_dynos(app_name)
      else
        puts 'No migrations required'
      end
    end

    def production_branch?
      git_branch_name.match(PRODUCTION_BRANCH_REGEX)
    end

    def push_code(app_name, revision)
      run_command!("git push --force git@heroku.com:#{app_name}.git #{revision}:master")
    end

    def git_branch_name
      run_command('git rev-parse --abbrev-ref HEAD')
    end

    def run_migrations(app_name)
      run_heroku_command!(app_name, 'run rake db:migrate')
    end

    def restart_dynos(app_name)
      run_heroku_command!(app_name, 'ps:restart')
    end

    def pending_migrations?(app_name)
      !run_heroku_command(app_name, 'run rake db:abort_if_pending_migrations')
    end

    def run_heroku_command!(app_name, command)
      success = run_heroku_command(app_name, command)
      raise "Heroku command '#{command}' failed" unless success
    end

    def run_heroku_command(app_name, command)
      cli_command = "heroku #{command} --app #{app_name}"
      if command.start_with?('run ')
        # If we're running a shell command, return the underlying
        # shell command exit code
        cli_command << ' --exit-code'
      end
      run_command(cli_command)
    end

    def run_command!(command)
      success = run_command(command)
      raise "Command '#{command}' failed" unless success
    end

    def run_command(command)
      puts command
      Bundler.with_clean_env { system(command) }
    end
  end
end
