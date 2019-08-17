#======================== Hot Water Efficiency =================================
require_relative 'alert_gas_model_base.rb'

class AlertHotWaterEfficiency < AlertGasModelBase
  MIN_EFFICIENCY = 0.7

  attr_reader :hot_water_efficiency_summer_unoccupied_methdology_percent
  attr_reader :hot_water_annual_summer_unoccupied_methdology_kwh, :hot_water_annual_summer_unoccupied_methdology_£
  attr_reader :average_summer_school_day_kwh, :average_summer_holiday_kwh, :average_summer_weekend_day_kwh
  attr_reader :hot_water_summer_methdology_percent_of_annual_gas
  attr_reader :annual_benchmark_hot_water_kwh, :point_of_use_annual_standing_loss_kwh
  attr_reader :point_of_use_annual_total_£, :point_of_use_annual_total_kwh
  attr_reader :saving_replacing_gas_hot_water_with_electric_point_of_use_£
  attr_reader :one_year_saving_£, :capital_cost
  attr_reader :efficiency_relative_to_theoretical_demand_percent
  attr_reader :heat_model_annual_heating_kwh, :heat_model_annual_hotwater_kwh
  attr_reader :heat_model_daily_hotwater_usage_kwh, :heat_model_daily_holiday_hotwater_usage_kwh
  attr_reader :heat_model_hot_water_efficiency

  def initialize(school)
    super(school, :hotwaterefficiency) 
    @relevance = :never_relevant if @relevance != :never_relevant && heating_only # set before calculation
  end

  def timescale
    'year'
  end

  def enough_data
    hw_model = AnalyseHeatingAndHotWater::HotwaterModel.new(@school)
    summer_holidays = hw_model.find_period_before_and_during_summer_holidays(@school.holidays, aggregate_meter.amr_data)
    summer_holidays.nil? ? :not_enough : :enough 
  end

  def self.template_variables
    specific = {'Hot water efficiency' => TEMPLATE_VARIABLES}
    specific.merge(self.superclass.template_variables)
  end

  TEMPLATE_VARIABLES = {
    hot_water_efficiency_summer_unoccupied_methdology_percent: {
      description: 'Efficiency of hot water system (summer unoccupied methodology)',
      units:  :percent
    },
    efficiency_relative_to_theoretical_demand_percent: {
      description: 'Efficiency of hot water system (relative to 5l/pupil/day 38C demand)',
      units:  :percent
    },
    hot_water_summer_methdology_percent_of_annual_gas: {
      description: 'Gas consumption for hot water (&kitchen) as a percent off annual gas consumption',
      units:  :percent
    },
    hot_water_annual_summer_unoccupied_methdology_kwh: {
      description: 'Estimate of annual hot water(& kitchen) consumption (kWh, summer unoccupied methodology)',
      units:  {kwh: :gas}
    },
    hot_water_annual_summer_unoccupied_methdology_£: {
      description: 'Estimate of annual hot water(& kitchen) consumption (£, summer unoccupied methodology)',
      units:  :£
    },
    average_summer_school_day_kwh: {
      description: 'Average summer school day kWh',
      units:  {kwh: :gas}
    },
    average_summer_holiday_kwh: {
      description: 'Average summer holiday day kWh',
      units:  {kwh: :gas}
    },
    average_summer_weekend_day_kwh: {
      description: 'Average summer weekend day kWh',
      units:  {kwh: :gas}
    },
    summer_hot_water_efficiency_chart: {
      description: 'Chart of summer gas consumption before and during summer holidays',
      units: :chart
    },
    annual_benchmark_hot_water_kwh: {
      description: 'Annual benchmark hot water usage (kWh, based on 5 litres/pupil/school day at 38C)',
      units:  {kwh: :electricity}
    },
    point_of_use_annual_standing_loss_kwh: {
      description: 'Potential standing losses from point of use electricity hot water (kWh, 30 pupils per appliance, assumed left on all year, no timers)',
      units:  {kwh: :electricity}
    },
    point_of_use_annual_total_kwh: {
      description: 'Annual electricity requirements for point of use electricity hot water throughout school (kWh)',
      units:  {kwh: :electricity}
    },
    point_of_use_annual_total_£: {
      description: 'Annual electricity requirements for point of use electricity hot water throughout school (£)',
      units:  :£
    },
    saving_replacing_gas_hot_water_with_electric_point_of_use_£: {
      description: 'Potential savings moving from gas boiler hot water to electric point of use (£)',
      units:  :£
    },
    heat_model_annual_heating_kwh: {
      description: 'Annual heating gas consumption (kWh, heat model)',
      units:  {kwh: :gas}
    },
    heat_model_annual_hotwater_kwh: {
      description: 'Annual hot water gas consumption estimate (kWh, heat model)',
      units:  {kwh: :gas}
    },
    heat_model_daily_hotwater_usage_kwh: {
      description: 'Daily school day hot water gas consumption estimate (kWh, heat model)',
      units:  {kwh: :gas}
    },
    heat_model_daily_holiday_hotwater_usage_kwh: {
      description: 'Daily holiday day hot water gas consumption estimate (kWh, heat model)',
      units:  {kwh: :gas}
    },
    heat_model_hot_water_efficiency: {
      description: 'Heating model hot water efficiency estimate',
      units:  :percent
    }
  }

  def summer_hot_water_efficiency_chart
    :hotwater_alert
  end

  private def calculate(asof_date)
    calculate_model(asof_date) # so gas_model_only base varaiables are expressed even if no hot water
    if @relevance != :never_relevant && heating_only
      @relevance = :never_relevant
      @rating = nil
    else
      @relevance = :relevant
      calculate_hot_water_model(asof_date)

      @hot_water_efficiency_summer_unoccupied_methdology_percent = [@hot_water_model.overall_efficiency, 0.0].max
      @hot_water_annual_summer_unoccupied_methdology_kwh = @hot_water_model.annual_hotwater_kwh_estimate
      @average_summer_school_day_kwh = @hot_water_model.avg_school_day_gas_consumption
      @average_summer_holiday_kwh = @hot_water_model.avg_holiday_day_gas_consumption
      @average_summer_weekend_day_kwh = @hot_water_model.avg_weekend_day_gas_consumption
      kwh_annual = annual_kwh(@school.aggregated_heat_meters, asof_date)
      @hot_water_summer_methdology_percent_of_annual_gas = @hot_water_annual_summer_unoccupied_methdology_kwh / kwh_annual
      @annual_benchmark_hot_water_kwh, @point_of_use_annual_standing_loss_kwh, @point_of_use_annual_total_kwh = AnalyseHeatingAndHotWater::HotwaterModel.annual_point_of_use_electricity_meter_kwh(pupils)
      @hot_water_annual_summer_unoccupied_methdology_£ = @hot_water_annual_summer_unoccupied_methdology_kwh * BenchmarkMetrics::GAS_PRICE
      @point_of_use_annual_total_£ = @point_of_use_annual_total_kwh * BenchmarkMetrics::ELECTRICITY_PRICE
      @saving_replacing_gas_hot_water_with_electric_point_of_use_£ = [@hot_water_annual_summer_unoccupied_methdology_£ - @point_of_use_annual_total_£, 0.0].max

      heating_model_analysis(asof_date)

      @one_year_saving_£ = Range.new(@saving_replacing_gas_hot_water_with_electric_point_of_use_£, @saving_replacing_gas_hot_water_with_electric_point_of_use_£)
      @capital_cost = electric_point_of_use_hotwater_costs

      @efficiency_relative_to_theoretical_demand_percent = @annual_benchmark_hot_water_kwh / @hot_water_annual_summer_unoccupied_methdology_kwh

      @rating = calculate_rating_from_range(0.6, 0.0, @hot_water_efficiency_summer_unoccupied_methdology_percent)

      @term = :shortterm
      @bookmark_url = add_book_mark_to_base_url('HotWaterEfficiency')
    end
  end
  alias_method :analyse_private, :calculate

  private def heating_model_analysis(asof_date)
    meter_date_1_year_before = meter_date_one_year_before(@school.aggregated_heat_meters, asof_date)
    heating_model_hot_water = @heating_model.hot_water_analysis(meter_date_1_year_before, asof_date)
    scale = scale_up_to_one_year(@school.aggregated_heat_meters, asof_date)
 
    unless heating_model_hot_water.nil?
      @heat_model_annual_heating_kwh                = heating_model_hot_water[:annual_heating_kwh] * scale
      @heat_model_annual_hotwater_kwh               = heating_model_hot_water[:annual_hotwater_kwh] * scale
      @heat_model_daily_hotwater_usage_kwh          = heating_model_hot_water[:daily_hotwater_usage_kwh]
      @heat_model_daily_holiday_hotwater_usage_kwh  = heating_model_hot_water[:daily_holiday_hotwater_usage_kwh]
      @heat_model_hot_water_efficiency              = heating_model_hot_water[:hot_water_efficiency]
    else # school should really have :heating_only meter attribute set to flag no hot water
      @heat_model_annual_heating_kwh                = 0.0
      @heat_model_annual_hotwater_kwh               = 0.0
      @heat_model_daily_hotwater_usage_kwh          = 0.0
      @heat_model_daily_holiday_hotwater_usage_kwh  = 0.0
      @heat_model_hot_water_efficiency              = 0.0
    end
  end

  def calculate_hot_water_model(_as_of_date)
    @hot_water_model = AnalyseHeatingAndHotWater::HotwaterModel.new(@school)
  end
end
