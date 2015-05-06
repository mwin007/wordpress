#!/usr/bin/env ruby

###
# This file hands over integration tests for rspec.
# Tests are generated from config.yml
###

require 'capybara/poltergeist'
require 'rspec'
require 'rspec/retry'
require 'capybara/rspec'
require 'capybara/dsl'
require 'yaml' #load variables from config file if wp-cli is not present
require 'uri' #parse the url from wp-cli

path = File.dirname(__FILE__)

# Load default RSPEC MATCHERS
require_relative 'lib/matchers.rb'

RSpec.configure do |config|
  config.include Capybara::DSL
  config.verbose_retry = true
  config.default_retry_count = 1
end

Capybara.configure do |config|
  config.javascript_driver = :poltergeist
  config.default_driver = :poltergeist # Tests can be more faster with rack::test.
end
 
Capybara.register_driver :poltergeist do |app|
  Capybara::Poltergeist::Driver.new(app, 
    debug: false,
    js_errors: false,
    phantomjs_logger: '/dev/null', 
    timeout: 60,
    :phantomjs_options => [
       '--webdriver-logfile=/dev/null',
       '--load-images=no',
       '--debug=no', 
       '--ignore-ssl-errors=yes', 
       '--ssl-protocol=TLSv1'
    ],
    window_size: [1920,1080] 
   )
end

##
# Config file tells us about the environment
##

# We never test a production site directly in WP-Palvelu
# Instead we make a clone of the site and redirect queries into the clone.
# This is done with the cookie found from ENV
shadow_hash = ENV['CONTAINER'].partition('_').last unless ENV['CONTAINER'].nil?

# Try to query siteurl with wp-cli
# This works because we always have just 1 wordpress installation / instance
if `wp core is-installed`
  target_url = `wp option get home`.strip
else
  exit(1) #fail if wp-cli isn't working
end

# Parse wp-cli siteurl into smaller parts
uri = URI(target_url)

# Create random test user, try to login with it and delete it after tests
username = "wp-palvelu-tester-#{Time.now.to_i}"
password = rand(36**32).to_s(36)
`wp user create #{username} #{username}@#{uri.host} --user_pass=#{password} --role=administrator`

# If we couldn't create user just skip the last test
unless $?.success?
  username = nil
end

# Cleanup afterwise
RSpec.configure do |config|
  config.after(:suite) { `wp user delete #{username} --yes` }
end

puts "testing #{target_url}..."
### Begin tests ###
describe "wordpress: #{target_url} - ", :type => :request, :js => true do 

  subject { page }

  before(:each) do
    page.driver.add_header("User-Agent", "wp-palvelu-testbot")
    page.driver.add_header("cookie", "wpp_shadow=#{shadow_hash};") unless shadow_hash.nil?
  end

  describe "frontpage" do

    before do
      visit "#{uri.scheme}://#{uri.host}#{uri.path}/"
    end

    it "Healthy status code 200, 301, 302, 503" do
      expect(page).to have_status_of [200,301,302,503]
    end

    it "Page includes stylesheets" do
      expect(page).to have_css
    end

    ### Add customised business critical frontend tests here #####
    
  end

  describe "admin-panel" do

    before do
      #Our sites always have https on
      visit "https://#{uri.host}#{uri.path}/wp-login.php"
    end

    it "There's a login form" do
      expect(page).to have_id "wp-submit"
    end

    #Only run these if we could create random test user
    if username
      it "Logged in to WordPress Dashboard" do
        within("#loginform") do
          fill_in 'log', :with => username
          fill_in 'pwd', :with => password
        end
        click_button 'wp-submit'
        # Should obtain cookies and be able to visit /wp-admin
        visit "https://#{uri.host}#{uri.path}/wp-admin/"
        expect(page).to have_id "wpadminbar"
      end
    end

  end
 
end