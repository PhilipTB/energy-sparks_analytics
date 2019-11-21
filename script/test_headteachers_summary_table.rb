# test report manager
require 'require_all'
require_relative '../lib/dashboard.rb'
require_rel '../test_support'
require './script/report_config_support.rb'

module Logging
  @logger = Logger.new('log/test-heads summary table ' + Time.now.strftime('%H %M') + '.log')
  logger.level = :debug
end

school_names = AnalysticsSchoolAndMeterMetaData.new.match_school_names('.*')

puts "Number of schools: #{school_names.length}"

html = ''

school_names.each do |school_name|
  # next unless school_name == 'Mundella'
  html += "<h2>#{school_name}</h2>"
  puts "==============================Doing #{school_name} ================================"

  meter_collection = SchoolFactory.new.load_or_use_cached_meter_collection(:name, school_name, :analytics_db)

  content = HeadTeachersSchoolSummaryTable.new(meter_collection)
  puts 'Invalid content' unless content.valid_content?
  content.analyse(nil)
  puts 'Content failed' unless content.make_available_to_users?
  puts HeadTeachersSchoolSummaryTable.front_end_template_tables
  puts content.front_end_template_table_data
  html += content.html
end

html_writer = HtmlFileWriter.new('Headteachers Tables')
html_writer.write(html)
html_writer.close


