#======================== Change in Daily Electricity Consumption =============
require_relative 'alert_electricity_only_base.rb'

class AlertChangeInDailyElectricityShortTerm < AlertElectricityOnlyBase
  MAXDAILYCHANGE = 1.15

  def initialize(school)
    super(school, :changeinelectricityconsumption)
  end

  def analyse_private(asof_date)
    days_in_week = 5
    beginning_of_week, last_weeks_consumption = schoolday_energy_usage_over_period(asof_date, days_in_week)
    beginning_of_last_week, week_befores_consumption = schoolday_energy_usage_over_period(beginning_of_week - 1, days_in_week)

    @analysis_report.term = :shortterm
    @analysis_report.add_book_mark_to_base_url('ElectricityChange')

    if last_weeks_consumption > week_befores_consumption * MAXDAILYCHANGE
      last_weeks_baseload = average_baseload(asof_date - 7, asof_date)
      @analysis_report.summary = 'Your daily electricity consumption has increased'
      text = sprintf('Your electricity consumption has increased from %.0f kWh ', week_befores_consumption)
      text += sprintf('last week (5 school days following %s) ', beginning_of_last_week.to_formatted_s(:long_ordinal))
      text += sprintf('to %.0f kWh ', last_weeks_consumption)
      text += sprintf('this week (5 school days following %s) ', beginning_of_week.to_formatted_s(:long_ordinal))
      text += sprintf('over the last year to %.1f last week. ', last_weeks_baseload)
      cost = BenchmarkMetrics::ELECTRICITY_PRICE * 195.0 * (last_weeks_consumption - week_befores_consumption) / days_in_week
      text += sprintf('If this continues it will costs you an additional £%.0f over the next year.', cost)
      description1 = AlertDescriptionDetail.new(:text, text)
      @analysis_report.rating = 2.0
      @analysis_report.status = :poor
    else
      @analysis_report.summary = 'Your daily electricity consumption is good'
      text = sprintf('Your weekly school day electricity consumption was %.0f kWh (£%.0f) this week ',
                     last_weeks_consumption,
                     last_weeks_consumption * BenchmarkMetrics::ELECTRICITY_PRICE)
      text += sprintf('compared with %.0f kWh (£%.0f) last week.',
                      week_befores_consumption,
                      week_befores_consumption * BenchmarkMetrics::ELECTRICITY_PRICE)
      description1 = AlertDescriptionDetail.new(:text, text)
      @analysis_report.rating = 10.0
      @analysis_report.status = :good
    end
    @analysis_report.add_detail(description1)
  end

  def schoolday_energy_usage_over_period(asof_date, school_days)
    list_of_school_days = last_n_school_days(asof_date, school_days)
    total_kwh = 0.0
    list_of_school_days.each do |date|
      total_kwh += days_energy_consumption(date)
    end
    [list_of_school_days[0], total_kwh]
  end

  def days_energy_consumption(date)
    amr_data = @school.aggregated_electricity_meters.amr_data
    amr_data.one_day_kwh(date)
  end
end