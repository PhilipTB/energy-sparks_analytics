require_relative '../common/alert_floor_area_pupils_mixin.rb'
class AlertElectricityPeakKWVersusBenchmark < AlertElectricityOnlyBase
  include AlertFloorAreaMixin
  attr_reader :average_school_day_last_year_kw, :average_school_day_last_year_kw_per_pupil
  attr_reader :average_school_day_last_year_kw_per_floor_area, :exemplar_kw
  attr_reader :one_year_saving_versus_exemplar_£, :one_year_saving_versus_exemplar_kwh

  def initialize(school)
    super(school, :peakelectricbenchmark)
  end

  def self.template_variables
    specific = {'Average peak kW electricity usage versus benchmark' => TEMPLATE_VARIABLES}
    specific.merge(self.superclass.template_variables)
  end

  TEMPLATE_VARIABLES = {
    average_school_day_last_year_kw: {
      description: 'Average peak kW last year',
      units:  { kw: :electricity},
      benchmark_code: 'kwsc'
    },
    average_school_day_last_year_kw_per_pupil: {
      description: 'Average peak kW last year per pupil',
      units:  { kw: :electricity},
      benchmark_code: 'kwpp'
    },
    average_school_day_last_year_kw_per_floor_area: {
      description: 'Average peak kWh last year per floor area',
      units:  { kw: :electricity},
      benchmark_code: 'kwfa'
    },
    exemplar_kw: {
      description: 'Exemplar peak KW for school of same floor area',
      units:  { kw: :electricity},
      benchmark_code: 'kwex'
    },
    one_year_saving_versus_exemplar_kwh: {
      description: 'One year savings kWh versus exemplar for school of same floor area',
      units:  { kwh: :electricity}
    },
    one_year_saving_versus_exemplar_£: {
      description: 'One year savings £ versus exemplar for school of same floor area',
      units:  :£,
      benchmark_code: 'tex£'
    },
    electricity_intraday_comparison_chart_6_months_apart: {
      description: 'Compares intraday usage 6 months apart',
      units: :chart
    }
  }

  def electricity_intraday_comparison_chart_6_months_apart
    :intraday_line_school_days_6months
  end

  def enough_data
    days_amr_data >= 60 ? :enough : :not_enough
  end

  def timescale
    'up to a year'
  end

  private def calculate(asof_date)
    @average_school_day_last_year_kw = average_schoolday_peak_kw(asof_date)
    @average_school_day_last_year_kw_per_pupil = @average_school_day_last_year_kw / pupils(asof_date - 365, asof_date)
    @average_school_day_last_year_kw_per_floor_area = @average_school_day_last_year_kw / floor_area(asof_date - 365, asof_date)
    benchmark_kw_m2 = BenchmarkMetrics::BENCHMARK_ELECTRICITY_PEAK_USAGE_KW_PER_M2
    @exemplar_kw = benchmark_kw_m2 * floor_area(asof_date - 365, asof_date)

    @rating = calculate_rating_from_range(benchmark_kw_m2, 0.02, @average_school_day_last_year_kw_per_floor_area)

    # arbitrarily saving is 4 hours of peak usage for every school day of the year
    @one_year_saving_versus_exemplar_kwh = 4.0 * 190.0 * [@average_school_day_last_year_kw_per_floor_area - benchmark_kw_m2, 0.0].max * floor_area(asof_date - 365, asof_date)
    @one_year_saving_versus_exemplar_£ = @one_year_saving_versus_exemplar_kwh * BenchmarkMetrics::ELECTRICITY_PRICE

    set_savings_capital_costs_payback(Range.new(@one_year_saving_versus_exemplar_£, @one_year_saving_versus_exemplar_£), nil)

    @term = :longterm
  end

  alias_method :analyse_private, :calculate

  private def average_schoolday_peak_kw(asof_date)
    start_date = [asof_date - 365, aggregate_meter.amr_data.start_date].max
    peak_kws = []
    (start_date..asof_date).each do |date|
      peak_kws.push(aggregate_meter.amr_data.statistical_peak_kw(date)) if occupied?(date)
    end
    peak_kws.sum / peak_kws.length
  end

end
