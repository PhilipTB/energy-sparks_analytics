# test report manager
require 'ruby-prof'
require 'benchmark/memory'
require 'require_all'
require_relative '../lib/dashboard.rb'
require_rel '../test_support'
require './script/report_config_support.rb'

script = {
  logger1:                  { name: TestDirectoryConfiguration::LOG + "/targetting %{time}.log", format: "%{severity.ljust(5, ' ')}: %{msg}\n" },
  schools:                  ['trinity*'],
  source:                   :unvalidated_meter_data,
  logger2:                  { name: "./log/targetting %{school_name} %{time}.log", format: "%{datetime} %{severity.ljust(5, ' ')}: %{msg}\n" },
  reports:                  {
                              charts: [
                                adhoc_worksheet: { name: 'Test', charts: %i[
                                  targeting_and_tracking_monthly_electricity
                                  ]},
                              ],
                              control: {
                              }
                            }, 
}

RunTests.new(script).run