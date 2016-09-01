# HerokuRailsDeploy

This gem provides a simple Heroku deploy script for Rails applications. Deploys
following the following steps:

1. Push code to Heroku
2. If there are pending migrations, run them and restart the Heroku dynos

## Installation

Add this line to your application's Gemfile:

```ruby
group :development do
  gem 'heroku_rails_deploy', require: false
end
```

Then execute:

    $ bundle

Then run the generator to create the deploy script and configuration file:

    $ rails generate heroku_rails_deploy
    
Finally follow the instructions in `config/heroku.yml` to configure the 
environments/Heroku applications for your project e.g.

```yml
production: my-app-prod
staging: my-app-staging
```

## Usage

From your application's root directory run the `bin/deploy` script with the `--help`
argument to print usage:

```
$ bin/deploy --help
Usage: deploy [options]
    -e, --environment ENVIRONMENT    The environment to deploy to. Must be in production, staging (default production)
    -r, --revision REVISION          The git revision to push. (default HEAD)
    -h, --help                       Show this message
```

A typical deploy command will look something like:
```
$ bin/deploy --environment production
```

Note you can omit the environment to deploy to your default environment.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then,
run `rake spec` to run the tests. You can also run `bin/console` for an
interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. 

To release a new version, update the version number in `version.rb`, and then
run `bundle exec rake release`, which will create a git tag for the version,
push git commits and tags, and push the `.gem` file to
[rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at
https://github.com/salsify/heroku_rails_deploy.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
