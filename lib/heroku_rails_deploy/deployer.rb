require 'optparse'
require 'shellwords'
require 'yaml'
require 'english'

module HerokuRailsDeploy
  class Deployer
    PRODUCTION_BRANCH_REGEX = /\A((master)|(release\/.+)|(hotfix\/.+))\z/
    PRODUCTION = 'production'.freeze

    attr_reader :config_file, :args

    class Options < Struct.new(:environment, :revision, :register_avro_schemas, :skip_avro_schemas)
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

        parser.on('--register-avro-schemas',
                  'Force the registration of Avro schemas when deploying to a non-production environment.') do |register_avro_schemas|
          options.register_avro_schemas = register_avro_schemas
        end

        parser.on('--skip-avro-schemas',
                  'Skip the registration of Avro schemas when deploying to production.') do |skip_avro_schemas|
          options.skip_avro_schemas = skip_avro_schemas
        end
      end.parse!(args)

      app_name = app_registry.fetch(options.environment) do
        raise OptionParser::InvalidArgument.new("Invalid environment '#{options.environment}'. " \
          "Must be in #{app_registry.keys.join(', ')}")
      end

      raise 'Only master, release or hotfix branches can be deployed to production' if production?(options) && !production_branch?(options.revision)

      uncommitted_changes = `git status --porcelain`
      raise "There are uncommitted changes:\n#{uncommitted_changes}" unless uncommitted_changes.blank?

      puts "Deploying to Heroku app #{app_name} for environment #{options.environment}"

      if !options.skip_avro_schemas && (production?(options) || options.register_avro_schemas)
        puts 'Checking for pending Avro schemas'
        pending_schemas = list_pending_schemas(app_name)
        if pending_schemas.any?
          puts 'Registering Avro schemas'
          register_avro_schemas!(registry_url(app_name), pending_schemas)
        else
          puts 'No pending Avro schemas'
        end
      end

      puts 'Pushing code'
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

    private

    def production?(options)
      options.environment == PRODUCTION
    end

    def production_branch?(revision)
      git_branch_name(revision).match(PRODUCTION_BRANCH_REGEX)
    end

    def push_code(app_name, revision)
      run_command!("git push --force #{app_remote(app_name)} #{revision}:master")
    end

    def git_branch_name(revision)
      branch_name = `git rev-parse --abbrev-ref #{Shellwords.escape(revision)}`.strip
      raise "Unable to get branch for #{revision}" unless $CHILD_STATUS.to_i.zero?
      branch_name
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

    def registry_url(app_name)
      result = Bundler.with_clean_env { `heroku config -a #{app_name} | grep AVRO_SCHEMA_REGISTRY_URL:` }
      exit_status = $CHILD_STATUS.exitstatus
      raise "Heroku command to determine schema registry URL failed with status #{exit_status}" unless exit_status.zero?
      result.split.last
    end

    def register_avro_schemas!(registry_url, schemas)
      cmd = "rake avro:register_schemas schemas=#{schemas.join(',')}"
      success = Bundler.with_clean_env { system("DEPLOYMENT_SCHEMA_REGISTRY_URL=#{registry_url} #{cmd}") }
      raise "Command '#{cmd}' failed" unless success
    end

    def list_pending_schemas(app_name)
      changed_files(app_name).select { |filename| /\.avsc$/ =~ filename }
    end

    def changed_files(app_name)
      `git diff --name-only #{remote_commit(app_name)}..#{current_commit}`.split("\n").map(&:strip)
    end

    def current_commit
      `git log --pretty=format:'%H' -n 1`
    end

    def remote_commit(app_name)
      `git ls-remote --heads #{app_remote(app_name)} master`.split.first
    end

    def app_remote(app_name)
      "git@heroku.com:#{app_name}.git"
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
