require 'optparse'
require 'shellwords'
require 'yaml'
require 'english'
require 'private_attr'

module HerokuRailsDeploy
  class Deployer
    extend PrivateAttr

    PRODUCTION_BRANCH_REGEX = /\A((master)|(release\/.+)|(hotfix\/.+))\z/
    PRODUCTION = 'production'.freeze

    attr_reader :config_file, :args
    private_attr_reader :options, :app_registry

    class Options < Struct.new(:environment, :revision, :register_avro_schemas, :skip_avro_schemas)
      def self.create_default(app_registry)
        new(app_registry.keys.first, 'HEAD')
      end
    end

    def initialize(config_file, args)
      raise "Missing config file #{config_file}" unless File.file?(config_file)
      @app_registry = YAML.load(File.read(config_file))
      @config_file = config_file
      @args = args
      @options = parse_options
    end

    def run
      return unless options

      app_name = app_registry.fetch(options.environment) do
        raise OptionParser::InvalidArgument.new("Invalid environment '#{options.environment}'. " \
          "Must be in #{app_registry.keys.join(', ')}")
      end

      raise 'Only master, release or hotfix branches can be deployed to production' if production?(options) && !production_branch?(options.revision)

      no_uncommitted_changes!

      puts "Deploying to Heroku app #{app_name} for environment #{options.environment}"

      if !options.skip_avro_schemas && (production? || options.register_avro_schemas)
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

    def production?
      options.try(:environment) == PRODUCTION
    end

    private

    def parse_options
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

      options
    end

    def production_branch?(revision)
      git_branch_name(revision).match(PRODUCTION_BRANCH_REGEX)
    end

    def no_uncommitted_changes!
      uncommitted_changes = run_command!('git status --porcelain', quiet: true)
      raise "There are uncommitted changes:\n#{uncommitted_changes}" unless uncommitted_changes.blank?
    end

    def push_code(app_name, revision)
      run_command!("git push --force #{app_remote(app_name)} #{revision}:master")
    end

    def git_branch_name(revision)
      run_command!("git rev-parse --abbrev-ref #{Shellwords.escape(revision)}", quiet: true).strip
    rescue
      raise "Unable to get branch for #{revision}"
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
      run_heroku_command(app_name, command, validate: true)
    rescue
      raise "Heroku command '#{command}' failed"
    end

    def run_heroku_command(app_name, command, validate: nil)
      cli_command = "heroku #{command} --app #{app_name}"
      if command.start_with?('run ')
        # If we're running a shell command, return the underlying
        # shell command exit code
        cli_command << ' --exit-code'
      end
      run_command(cli_command, validate: validate)
    end

    def registry_url(app_name)
      result = run_command!("heroku config -a #{app_name} | grep AVRO_SCHEMA_REGISTRY_URL:", quiet: true)
      result.split.last
    end

    def register_avro_schemas!(registry_url, schemas)
      cmd = "rake avro:register_schemas schemas=#{schemas.join(',')}"
      run_command!("DEPLOYMENT_SCHEMA_REGISTRY_URL=#{registry_url} #{cmd}", print_command: cmd)
    end

    def list_pending_schemas(app_name)
      changed_files(app_name).select { |filename| /\.avsc$/ =~ filename }
    end

    def changed_files(app_name)
      run_command("git diff --name-only #{remote_commit(app_name)}..#{current_commit}", quiet: true).split("\n").map(&:strip)
    end

    def current_commit
      run_command!("git log --pretty=format:'%H' -n 1", quiet: true)
    end

    def remote_commit(app_name)
      run_command!("git ls-remote --heads #{app_remote(app_name)} master", quiet: true).split.first
    end

    def app_remote(app_name)
      "git@heroku.com:#{app_name}.git"
    end

    def run_command!(command, print_command: nil, quiet: false)
      run_command(command, print_command: print_command, quiet: quiet, validate: true)
    end

    def run_command(command, print_command: nil, validate: nil, quiet: false)
      printed_command = print_command || command
      puts printed_command unless quiet
      output = Bundler.with_clean_env { `#{command}` }
      exit_status = $CHILD_STATUS.exitstatus
      raise "Command '#{printed_command}' failed" if validate && exit_status.nonzero?
      output
    end
  end
end
