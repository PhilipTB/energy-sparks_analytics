# test report manager
require 'require_all'
require_relative '../lib/dashboard.rb'
require_rel '../test_support'

class ReportConfigSupport
  include Logging
  attr_reader :schools, :chart_manager
  attr_accessor :worksheet_charts, :excel_name 

  def initialize

    # @dashboard_page_groups = now in lib/dashboard/charting_and_reports/dashboard_configuration.rb
    # @school_report_groups = { # 2 main dashboards: 1 for electric only schools, one for electric and gas schools

    @schools = {
    # Bath
      'Bishop Sutton Primary School'      => :electric_and_gas,
      'Castle Primary School'             => :electric_and_gas,
      'Freshford C of E Primary'          => :electric_and_gas,
      'Marksbury C of E Primary School'   => :electric_only,
      'Paulton Junior School'             => :electric_and_gas,
      'Pensford Primary'                  => :electric_only,
      'Roundhill School'                  => :electric_and_gas,
      'Saltford C of E Primary School'    => :electric_and_gas,
      'St Marks Secondary'                => :electric_and_gas,
      'St Johns Primary'                  => :electric_and_gas,
      'St Saviours Junior'                => :electric_and_gas,
      'Stanton Drew Primary School'       => :electric_only,
      'Twerton Infant School'             => :electric_and_gas,
      'Westfield Primary'                 => :electric_and_gas,
    # Sheffield
      'Bankwood Primary School'           => :electric_and_gas,
 #     'Ecclesall Primary School'          => :electric_and_gas,
      'Ecclesfield Primary School'        => :electric_and_gas,
      'Hunters Bar School'                => :electric_and_gas,
      'Lowfields Primary School'          => :electric_only,
      'Meersbrook Primary School'         => :electric_and_gas,
      'Mundella Primary School'           => :electric_and_gas,
      'Phillimore School'                 => :electric_and_gas,
      'Shortbrook School'                 => :electric_and_gas,
      'Valley Park School'                => :electric_only,
      'Walkley School Tennyson School'    => :gas_only,
      'Whiteways Primary'                 => :electric_and_gas,
      'Woodthorpe Primary School'         => :electric_and_gas,
      'Wybourn Primary School'            => :electric_only,
    # Frome
      'Christchurch First School'         => :gas_only,
      'Critchill School'                  => :electric_and_gas,
      'Frome College'                     => :electric_only,
      'Hayesdown First School'            => :electric_only,
      'Oakfield School'                   => :electric_and_gas,
      'Selwood Academy'                   => :electric_and_gas,
      'St Johns First School'             => :electric_and_gas,
      'St Louis First School'             => :electric_and_gas,
      'Trinity First School'              => :electric_and_gas,
      'Vallis First School'               => :electric_and_gas
    }
    @benchmarks = []

    ENV['School Dashboard Advice'] = 'Include Header and Body'
    $SCHOOL_FACTORY = SchoolFactory.new

    @chart_manager = nil
    @school_metadata = nil
    @worksheet_charts = {}
    @failed_reports = []

    logger.debug "\n" * 8
  end

  def self.suppress_output(school_name)
    begin
      original_stdout = $stdout.clone
      $stdout.reopen(File.new('./Results/' + school_name + 'loading log.txt', 'w'))
      retval = yield
    rescue StandardError => e
      $stdout.reopen(original_stdout)
      raise e
    ensure
      $stdout.reopen(original_stdout)
    end
    retval
  end

  def do_all_schools(suppress_debug = false)
    @schools.keys.each do |school_name|
      load_school(school_name, suppress_debug)
      do_all_standard_pages_for_school
    end
    report_failed_charts
  end

  def report_failed_charts
    puts '=' * 100
    puts 'Failed charts'
    @failed_reports.each do |school_name, chart_name|
      puts sprintf('%-25.25s %-45.45s', school_name, chart_name)
    end
  end

  def self.banner(title)
    cols = 120
    len_before = ((cols - title.length) / 2).floor
    len_after = cols - title.length - len_before
    '=' * len_before + title + '=' * len_after
  end

  def setup_school(school, school_name)
    @school_name = school_name
    @school = school
    @chart_manager = ChartManager.new(@school)
  end

  def load_school(school_name, suppress_debug = false)
    logger.debug self.class.banner("School: #{school_name}")

    puts self.class.banner("School: #{school_name}")

    @excel_name = school_name

    @school_name = school_name

    @school = $SCHOOL_FACTORY.load_or_use_cached_meter_collection(:name, school_name, :analytics_db)

    @chart_manager = ChartManager.new(@school)
    
    @school # needed to run simulator
  end

  def report_benchmarks
    @benchmarks.each do |bm|
      puts bm
    end
    @benchmarks = []
  end

  def do_all_standard_pages_for_school
    @worksheet_charts = {}

    report_config = @schools[@school_name]
    report_groups = DashboardConfiguration::DASHBOARD_FUEL_TYPES[report_config]

    report_groups.each do |report_page|
      do_one_page(report_page, false)
    end

    save_excel_and_html
  end

  def save_excel_and_html
    write_excel
    write_html
  end

  def do_one_page(page_config_name, reset_worksheets = true)
    @worksheet_charts = {} if reset_worksheets
    page_config = DashboardConfiguration::DASHBOARD_PAGE_GROUPS[page_config_name]
    do_one_page_internal(page_config[:name], page_config[:charts])
  end

  def do_chart_list(page_name, list_of_charts)
    @worksheet_charts = {}
    do_one_page_internal(page_name, list_of_charts)
  end

  def write_excel
    excel = ExcelCharts.new(File.join(File.dirname(__FILE__), '../Results/') + @excel_name + '- charts test.xlsx')
    @worksheet_charts.each do |worksheet_name, charts|
      excel.add_charts(worksheet_name, charts)
    end
    excel.close
  end

  def write_html
    html_file = HtmlFileWriter.new(@school_name)
    @worksheet_charts.each do |worksheet_name, charts|
      html_file.write_header(worksheet_name)
      charts.each do |chart|
        html_file.write_header_footer(chart[:config_name], chart[:advice_header], chart[:advice_footer])
      end
    end
    html_file.close
  end

  def do_one_page_internal(page_name, list_of_charts)
    logger.debug self.class.banner("Running report page  #{page_name}")
    @worksheet_charts[page_name] = []
    list_of_charts.each do |chart_name|
      charts = do_charts_internal(chart_name)
      unless charts.nil?
        charts.each do |chart|
          ap(chart, limit: 20, color: { float: :red }) if ENV['AWESOMEPRINT'] == 'on'
          @worksheet_charts[page_name].push(chart) unless chart.nil?
        end
      end
    end
  end

  def do_charts_internal(chart_name)
    if chart_name.is_a?(Symbol)
      logger.debug self.class.banner(chart_name.to_s)
    else
      logger.debug "Running Composite Chart #{chart_name[:name]}"
    end
    chart_results = nil
    puts "Chart: #{chart_name}"
    bm = Benchmark.measure {
      chart_results = @chart_manager.run_chart_group(chart_name)
    }
    @benchmarks.push(sprintf("%20.20s %40.40s = %s", @school.name, chart_name, bm.to_s))
    if chart_results.nil?
      @failed_reports.push([@school.name, chart_name])
      puts "Nil chart result from #{chart_name}"
    end
    if chart_name.is_a?(Symbol)
      [chart_results]
    else
      chart_results[:charts]
    end
  end
end
