require_relative 'alert_analysis_base.rb'

class AlertGasOnlyBase < AlertAnalysisBase
  def initialize(school, report_type)
    super(school, report_type)
  end

  def maximum_alert_date
    @school.aggregated_heat_meters.amr_data.end_date
  end

  def needs_electricity_data?
    false
  end

  def self.template_variables
    specific = {'Gas Meters' => TEMPLATE_VARIABLES}
    specific.merge(self.superclass.template_variables)
  end

  TEMPLATE_VARIABLES = {
    non_heating_only: {
      description: 'Gas at this school is only used for hot water or in the kitchens',
      units:  TrueClass
    },
    kitchen_only: {
      description: 'Gas at this school is only used in the kitchens',
      units:  TrueClass
    },
    hot_water_only: {
      description: 'Gas at this school is only used just for hot water',
      units:  TrueClass
    },
    heating_only: {
      description: 'Gas at this school is only used heating and not for hot water or in the kitchens',
      units:  TrueClass
    }
  }.freeze

  def last_meter_data_date
    @school.aggregated_heat_meters.amr_data.end_date
  end

  def last_n_school_days_kwh(asof_date, school_days)
    kwhs = []
    days = last_n_school_days(asof_date, school_days)
    days.each do |date|
      kwhs.push(@school.aggregated_heat_meters.amr_data.one_day_kwh(date))
    end
    kwhs
  end

  protected def gas_cost(kwh)
    kwh * BenchmarkMetrics::GAS_PRICE
  end

  def pipework_insulation_cost
    meters_pipework = floor_area / 5.0
    Range.new(meters_pipework * 5, meters_pipework * 15) # TODO(PH,11Mar2019) - find real figure to replace these?
  end

  def electric_point_of_use_hotwater_costs
    number_of_toilets = (pupils / 30.0)
    Range.new(number_of_toilets * 300.0, number_of_toilets * 600.0)
  end

  protected def aggregate_meter
    @school.aggregated_heat_meters
  end

  def non_heating_only
    @school.aggregated_heat_meters.non_heating_only?
  end

  def kitchen_only
    @school.aggregated_heat_meters.kitchen_only?
  end

  def hot_water_only
    @school.aggregated_heat_meters.hot_water_only?
  end

  def heating_only
    @school.aggregated_heat_meters.heating_only?
  end
end